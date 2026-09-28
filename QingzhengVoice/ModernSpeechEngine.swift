import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
@MainActor
final class ModernSpeechEngine: SpeechEngine {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var warmTranscriber: SpeechTranscriber?
    private var warmFormat: AVAudioFormat?
    private var warmLocale: Locale?
    private var audioEngine: AVAudioEngine?
    private var tapInstalled = false
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?
    private var finalized = ""
    private var volatile = ""
    private var onPartial: ((String) -> Void)?

    func prepareLocale(_ locale: Locale, onProgress: @escaping (Double) -> Void) async throws -> Double? {
        let resolved = try await resolve(locale)
        let transcriber = makeTranscriber(resolved)
        let downloaded = try await ensureModel(for: transcriber, locale: resolved, onProgress: onProgress)
        warmTranscriber = transcriber
        warmLocale = resolved
        if let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) {
            warmFormat = format
            let analyzer = makeAnalyzer(transcriber)
            try await analyzer.prepareToAnalyze(in: format)
        }
        return downloaded
    }

    func start(locale: Locale, onPartial: @escaping (String) -> Void) async throws {
        cancelSession(keepWarm: true)
        self.onPartial = onPartial
        finalized = ""
        volatile = ""

        let resolved = try await resolve(locale)
        let transcriber: SpeechTranscriber
        if let warmTranscriber, let warmLocale, Self.sameLanguage(warmLocale, resolved) {
            transcriber = warmTranscriber
        } else {
            transcriber = makeTranscriber(resolved)
            _ = try await ensureModel(for: transcriber, locale: resolved, onProgress: { _ in })
            warmTranscriber = transcriber
            warmLocale = resolved
        }
        self.transcriber = transcriber

        let analyzer = makeAnalyzer(transcriber)
        self.analyzer = analyzer

        let format = warmFormat ?? await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard let format else { throw SpeechFailure.noAudioFormat }
        warmFormat = format
        try await analyzer.prepareToAnalyze(in: format)

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let piece = String(result.text.characters)
                    await MainActor.run {
                        guard let self else { return }
                        if result.isFinal {
                            self.finalized += piece
                            self.volatile = ""
                        } else {
                            self.volatile = piece
                        }
                        self.onPartial?(self.displayText)
                    }
                }
            } catch {}
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        analyzerTask = Task {
            try? await analyzer.start(inputSequence: stream)
        }
        try startMic(targetFormat: format, continuation: continuation)
    }

    func stop() async throws -> String {
        stopMic()
        inputContinuation?.finish()
        inputContinuation = nil
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        try await Task.sleep(for: .milliseconds(250))
        let text = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelSession(keepWarm: true)
        Task { try? await rewarm() }
        return text
    }

    func cancel() {
        cancelSession(keepWarm: true)
        Task { try? await rewarm() }
    }

    private var displayText: String { finalized + volatile }

    private func rewarm() async throws {
        guard let transcriber = warmTranscriber, let format = warmFormat else { return }
        let analyzer = makeAnalyzer(transcriber)
        try await analyzer.prepareToAnalyze(in: format)
    }

    private func makeAnalyzer(_ transcriber: SpeechTranscriber) -> SpeechAnalyzer {
        SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
        )
    }

    private func resolve(_ locale: Locale) async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        for candidate in LocaleResolver.candidates(locale) {
            if let match = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                return match
            }
            if supported.contains(where: { Self.sameLanguage($0, candidate) }) {
                return candidate
            }
        }
        throw SpeechFailure.localeUnavailable
    }

    private func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    private func ensureModel(
        for transcriber: SpeechTranscriber,
        locale: Locale,
        onProgress: @escaping (Double) -> Void
    ) async throws -> Double? {
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { Self.sameLanguage($0, locale) }) {
            return nil
        }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return nil
        }
        let progress = request.progress
        let poller = Task {
            while !Task.isCancelled && !progress.isFinished {
                onProgress(progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
            onProgress(1)
        }
        defer { poller.cancel() }
        try await request.downloadAndInstall()
        return 1
    }

    private func startMic(targetFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
            throw SpeechFailure.noAudioFormat
        }
        let converter = try AudioBufferConverter(from: micFormat, to: targetFormat)
        input.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in
            guard let converted = try? converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func stopMic() {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
    }

    private func cancelSession(keepWarm: Bool) {
        stopMic()
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        analyzerTask?.cancel()
        analyzer = nil
        transcriber = nil
        resultsTask = nil
        analyzerTask = nil
        onPartial = nil
        volatile = ""
        if !keepWarm {
            warmTranscriber = nil
            warmFormat = nil
            warmLocale = nil
        }
    }

    private static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        if a.identifier == b.identifier { return true }
        let left = a.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let right = b.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return left == right || left.hasPrefix(right.prefix(2)) && right.hasPrefix(left.prefix(2)) && left.contains("zh") == right.contains("zh")
    }
}
