import Combine
import Foundation
import Speech
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var phase: Phase = .idle
    @Published var liveText = ""
    @Published var lastResult = ""
    @Published var lastRawTranscript = ""
    @Published var notice: String?
    @Published var permissions = PermissionSnapshot()
    @Published var elapsed: TimeInterval = 0
    @Published var downloadProgress: Double?

    let settings = SettingsStore()
    private let hud = HUDController()
    private let hotkey = HotkeyManager()
    private var engine: SpeechEngine = SpeechEngineFactory.make()
    private var recordingStartedAt: Date?
    private var tick: Timer?
    private var runningTask: Task<Void, Never>?
    private var lastHotkeyAt = Date.distantPast
    private var failureGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case polishing
        case inserting
        case downloadingModel
        case error(String)

        var isBusy: Bool {
            switch self {
            case .idle, .error: return false
            default: return true
            }
        }
    }

    var menuBarSymbol: String {
        switch phase {
        case .recording: return "mic.fill"
        case .transcribing, .polishing, .inserting, .downloadingModel: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "waveform"
        }
    }

    var hudTitle: String {
        switch phase {
        case .idle: return "清正语音"
        case .recording: return "正在听…"
        case .transcribing: return "正在转写…"
        case .polishing: return "正在整理…"
        case .inserting: return "正在插入…"
        case .downloadingModel: return "正在下载语音模型…"
        case .error: return "出错了"
        }
    }

    var hudPlaceholder: String {
        switch phase {
        case .recording: return "对着麦克风说话，再按一次 Control-Option-空格 结束"
        case .downloadingModel:
            if let downloadProgress {
                return "已完成 \(Int(downloadProgress * 100))%"
            }
            return "第一次使用中文或英文时需要下载设备端模型"
        default: return " "
        }
    }

    var elapsedLabel: String {
        guard phase == .recording else { return "" }
        let seconds = Int(elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var statusLine: String {
        switch phase {
        case .idle:
            return lastResult.isEmpty ? "按 Control-Option-空格 开始说话" : "上次已插入到当前应用"
        case .recording:
            return "录音中，再按一次快捷键结束"
        case .transcribing:
            return "正在把语音转成文字"
        case .polishing:
            return "正在整理文本"
        case .inserting:
            return "正在粘贴到当前应用"
        case .downloadingModel:
            return "正在准备本地语音模型"
        case .error(let message):
            return message
        }
    }

    func start() {
        hud.attach(model: self)
        hotkey.onTrigger = { [weak self] in
            self?.handleHotkey()
        }
        hotkey.register()
        refreshPermissions()
        Task { await installModelIfNeeded(interactive: false) }
    }

    func handleHotkey() {
        let now = Date()
        guard now.timeIntervalSince(lastHotkeyAt) > 0.25 else { return }
        lastHotkeyAt = now
        Task { await toggleRecording() }
    }

    func toggleRecording() async {
        if phase == .recording {
            await finishRecording()
        } else if !phase.isBusy {
            await beginRecording()
        }
    }

    func retryLastInsert() {
        let text = lastResult.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await insert(text) }
    }

    func refreshPermissions() {
        permissions = Permissions.snapshot()
    }

    func requestPermissions() async {
        _ = await Permissions.requestMicrophone()
        _ = await Permissions.requestSpeech()
        _ = Permissions.isAccessibilityTrusted(prompt: true)
        refreshPermissions()
    }

    func installModelIfNeeded(interactive: Bool) async {
        do {
            if let progress = try await engine.prepareLocale(settings.resolvedLocale(), onProgress: { [weak self] value in
                Task { @MainActor in
                    self?.downloadProgress = value
                    if self?.phase == .idle || self?.phase == .downloadingModel {
                        self?.phase = .downloadingModel
                        self?.hud.show()
                    }
                }
            }) {
                downloadProgress = progress
            }
            if phase == .downloadingModel {
                phase = .idle
                hud.hide(after: 0.6)
            }
            downloadProgress = nil
        } catch {
            if interactive {
                fail(error.localizedDescription)
            }
        }
    }

    private func beginRecording() async {
        notice = nil
        if !Permissions.microphoneGranted {
            _ = await Permissions.requestMicrophone()
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            _ = await Permissions.requestSpeech()
        }
        refreshPermissions()
        guard permissions.microphone else {
            fail("没有麦克风权限。打开菜单栏窗口，点「授予权限」。")
            return
        }
        guard permissions.speech else {
            fail("没有语音识别权限。打开菜单栏窗口，点「授予权限」。")
            return
        }

        liveText = ""
        elapsed = 0
        recordingStartedAt = Date()
        phase = .recording
        hud.show()
        startTick()

        do {
            try await engine.start(locale: settings.resolvedLocale()) { [weak self] partial in
                Task { @MainActor in
                    self?.liveText = partial
                }
            }
        } catch {
            stopTick()
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        stopTick()
        phase = .transcribing
        runningTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.engine.stop()
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.fail("没听清，请靠近麦克风再试一次。")
                    return
                }
                self.lastRawTranscript = trimmed
                self.liveText = trimmed
                let polished = await self.polish(trimmed)
                self.lastResult = polished
                self.liveText = polished
                await self.insert(polished)
            } catch is CancellationError {
                self.phase = .idle
                self.hud.hide()
            } catch {
                self.fail(error.localizedDescription)
            }
        }
        runningTask = task
        await task.value
    }

    private func polish(_ raw: String) async -> String {
        phase = .polishing
        let polisher = PolisherFactory.make(settings: settings)
        do {
            let output = try await polisher.polish(raw)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? MockPolisher.normalize(raw) : trimmed
        } catch {
            notice = "整理失败，已改用本地规则：\(error.localizedDescription)"
            return MockPolisher.normalize(raw)
        }
    }

    private func insert(_ text: String) async {
        phase = .inserting
        refreshPermissions()
        guard permissions.accessibility else {
            lastResult = text
            fail("文本已准备好，但没有辅助功能权限，无法贴进其它应用。可先复制，或去系统设置勾选「清正语音」。")
            return
        }
        do {
            try await TextInserter.shared.insert(text)
            phase = .idle
            liveText = text
            hud.hide(after: 1.1)
        } catch {
            lastResult = text
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        engine.cancel()
        stopTick()
        failureGeneration += 1
        let generation = failureGeneration
        phase = .error(message)
        hud.show()
        hud.hide(after: 4)
        Task {
            try? await Task.sleep(for: .seconds(4.1))
            if generation == failureGeneration, case .error = phase {
                phase = .idle
            }
        }
    }

    private func startTick() {
        stopTick()
        tick = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
                if self.elapsed >= 60 {
                    await self.finishRecording()
                }
            }
        }
    }

    private func stopTick() {
        tick?.invalidate()
        tick = nil
    }
}
