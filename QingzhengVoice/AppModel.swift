import Combine
import Foundation
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
    @Published var modelReady = false

    let settings = SettingsStore()
    private let hud = HUDController()
    private let hotkey = HotkeyManager()
    private var engine: SpeechEngine = SpeechEngineFactory.make()
    private var insertTarget: FocusTarget?
    private var lastExternalTarget: FocusTarget?
    private var focusWatch: Timer?
    private var stopAfterStart = false
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
        case arming
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
        case .recording, .arming: return "mic.fill"
        case .transcribing, .polishing, .inserting, .downloadingModel: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "waveform"
        }
    }

    var hudTitle: String {
        switch phase {
        case .idle: return "清正语音"
        case .arming: return "正在打开麦克风…"
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
        case .arming: return "马上开始听，再按一次可取消"
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
            if !permissions.microphone || !permissions.speech {
                return "先在菜单栏授予麦克风和语音识别，热键才不会弹出权限框"
            }
            if !permissions.accessibility {
                return "辅助功能未开：能转写，但不能写进其它输入框"
            }
            if modelReady {
                return notice ?? "模型已就绪。光标放在任意输入框，按 Control-Option-空格"
            }
            return notice ?? "正在预热本地语音模型…"
        case .arming:
            return "正在打开麦克风"
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
        if !hotkey.register() {
            notice = "Control-Option-空格 已被其它应用占用，快捷键没有注册成功"
        }
        watchExternalFocus()
        refreshPermissions()
        Task { await installModelIfNeeded(interactive: false) }
    }

    func handleHotkey() {
        let now = Date()
        guard now.timeIntervalSince(lastHotkeyAt) > 0.25 else { return }
        lastHotkeyAt = now
        if phase == .recording {
            Task { await finishRecording() }
            return
        }
        if phase == .arming {
            stopAfterStart = true
            return
        }
        guard !phase.isBusy else { return }
        pinTarget()
        Task { await beginRecording() }
    }

    func toggleRecording() async {
        if phase == .recording {
            await finishRecording()
        } else if phase == .arming {
            stopAfterStart = true
        } else if !phase.isBusy {
            pinTarget()
            await beginRecording()
        }
    }

    func retryLastInsert() {
        let text = lastResult.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let current = FocusTarget.capture()
        if !current.isOwnApp {
            insertTarget = current
        }
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
            modelReady = false
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
            modelReady = true
            if phase == .downloadingModel {
                phase = .idle
                hud.hide(after: 0.6)
            }
            downloadProgress = nil
        } catch {
            modelReady = false
            notice = error.localizedDescription
            if interactive {
                fail(error.localizedDescription)
            }
        }
    }

    private func beginRecording() async {
        notice = nil
        refreshPermissions()
        if insertTarget == nil {
            pinTarget()
        }
        guard permissions.microphone else {
            fail("没有麦克风权限。请先点菜单栏「授予权限」，不要在输入框里等弹窗。")
            return
        }
        guard permissions.speech else {
            fail("没有语音识别权限。请先点菜单栏「授予权限」，热键路径不会弹出系统框以免抢焦点。")
            return
        }

        liveText = ""
        elapsed = 0
        phase = .arming
        hud.show()

        do {
            try await engine.start(locale: settings.resolvedLocale()) { [weak self] partial in
                Task { @MainActor in
                    self?.liveText = partial
                }
            }
        } catch {
            stopAfterStart = false
            fail(error.localizedDescription)
            return
        }
        if stopAfterStart {
            stopAfterStart = false
            await finishRecording()
            return
        }
        recordingStartedAt = Date()
        phase = .recording
        startTick()
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
            fail("文本已准备好，但没有辅助功能权限，无法写进其它输入框。")
            return
        }
        guard let target = insertTarget else {
            lastResult = text
            fail(InsertFailure.noTargetField.localizedDescription)
            return
        }
        do {
            try await TextInserter.shared.insert(text, into: target)
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
                if self.elapsed >= self.engine.maximumRecordingSeconds {
                    await self.finishRecording()
                }
            }
        }
    }

    private func stopTick() {
        tick?.invalidate()
        tick = nil
    }

    private func pinTarget() {
        let live = FocusTarget.capture()
        if !live.isOwnApp {
            lastExternalTarget = live
            insertTarget = live
        } else if let lastExternalTarget {
            insertTarget = lastExternalTarget
        } else {
            insertTarget = live
        }
    }

    private func watchExternalFocus() {
        focusWatch?.invalidate()
        focusWatch = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.phase.isBusy else { return }
                let snap = FocusTarget.capture()
                if !snap.isOwnApp {
                    self.lastExternalTarget = snap
                }
            }
        }
    }
}
