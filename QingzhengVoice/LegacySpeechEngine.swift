import AVFoundation
import Foundation
import Speech

@MainActor
final class LegacySpeechEngine: SpeechEngine {
    let maximumRecordingSeconds: TimeInterval = 55
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var tapInstalled = false
    private var lastText = ""
    private var onPartial: ((String) -> Void)?
    private var finalWaiter: CheckedContinuation<String, Error>?
    private var pendingFinal: String?

    func prepareLocale(_ locale: Locale, onProgress: @escaping (Double) -> Void) async throws -> Double? {
        guard let recognizer = makeRecognizer(locale) else { throw SpeechFailure.localeUnavailable }
        self.recognizer = recognizer
        return nil
    }

    func start(locale: Locale, onPartial: @escaping (String) -> Void) async throws {
        cancelSession(keepRecognizer: true)
        self.onPartial = onPartial
        lastText = ""

        let recognizer = self.recognizer ?? makeRecognizer(locale)
        guard let recognizer else {
            throw SpeechFailure.localeUnavailable
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        self.request = request

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechFailure.noAudioFormat }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.lastText = result.bestTranscription.formattedString
                    self.onPartial?(self.lastText)
                    if result.isFinal {
                        self.pendingFinal = self.lastText
                        self.finishWaiter(self.lastText)
                    }
                }
                if let error, self.finalWaiter != nil {
                    self.finishWaiter(self.lastText.isEmpty ? nil : self.lastText, error: error)
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    func stop() async throws -> String {
        request?.endAudio()
        stopMic()
        if let pendingFinal {
            let text = pendingFinal
            cancelSession(keepRecognizer: true)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = try await withCheckedThrowingContinuation { continuation in
            finalWaiter = continuation
            Task {
                try await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    self.finishWaiter(self.lastText)
                }
            }
        }
        cancelSession(keepRecognizer: true)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        task?.cancel()
        request?.endAudio()
        stopMic()
        if let finalWaiter {
            finalWaiter.resume(returning: lastText)
            self.finalWaiter = nil
        }
        cancelSession(keepRecognizer: true)
    }

    private func makeRecognizer(_ locale: Locale) -> SFSpeechRecognizer? {
        for candidate in LocaleResolver.candidates(locale) {
            if let recognizer = SFSpeechRecognizer(locale: candidate), recognizer.isAvailable {
                return recognizer
            }
        }
        return SFSpeechRecognizer()
    }

    private func stopMic() {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
    }

    private func finishWaiter(_ text: String?, error: Error? = nil) {
        guard let finalWaiter else { return }
        self.finalWaiter = nil
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalWaiter.resume(returning: text)
        } else if let error {
            finalWaiter.resume(throwing: error)
        } else {
            finalWaiter.resume(returning: text ?? "")
        }
    }

    private func cancelSession(keepRecognizer: Bool) {
        task?.cancel()
        stopMic()
        task = nil
        request = nil
        onPartial = nil
        pendingFinal = nil
        if !keepRecognizer {
            recognizer = nil
        }
    }
}
