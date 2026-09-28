import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            general
                .tabItem { Label("通用", systemImage: "slider.horizontal.3") }
            polish
                .tabItem { Label("整理", systemImage: "text.badge.checkmark") }
            permissions
                .tabItem { Label("权限", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 420)
        .padding(16)
    }

    private var general: some View {
        Form {
            Picker("识别语言", selection: $settings.localeIdentifier) {
                Text("简体中文").tag("zh-CN")
                Text("English (US)").tag("en-US")
                Text("跟随系统").tag("system")
            }
            LabeledContent("开始/结束录音") {
                Text("Control-Option-空格")
                    .foregroundStyle(.secondary)
            }
            Text("启动时会预热本地 ASR。请用快捷键唤醒：热键按下的瞬间钉住当前输入框，录音过程不抢焦点。系统文本框走辅助功能写字，浏览器/Electron 等走粘贴。不要用菜单栏按钮对着别人的输入框说话。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("预下载当前语言的本地模型") {
                Task { await model.installModelIfNeeded(interactive: true) }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.localeIdentifier) { _, _ in
            Task { await model.installModelIfNeeded(interactive: false) }
        }
    }

    private var polish: some View {
        Form {
            Toggle("转写后整理再插入", isOn: $settings.polishEnabled)
            Picker("整理后端", selection: $settings.polishBackend) {
                Text("自动（有 Key 走云端，否则本地）").tag(PolishBackend.auto)
                Text("本地规则").tag(PolishBackend.mock)
                Text("Apple Intelligence").tag(PolishBackend.apple)
                Text("OpenAI 兼容接口").tag(PolishBackend.openai)
            }
            TextField("Base URL", text: $settings.openaiBaseURL)
            TextField("Model", text: $settings.openaiModel)
            SecureField("API Key（存在钥匙串，可留空）", text: $settings.apiKeyDraft)
                .onSubmit { settings.saveAPIKey() }
            Button("保存 Key") { settings.saveAPIKey() }
            Text("兼容 OpenAI Chat Completions 的服务都可以，例如官方接口或 DeepSeek。没有 Key 时使用口播标点与去口头禅规则，应用仍可完整使用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { settings.loadAPIKey() }
        .onDisappear { settings.saveAPIKey() }
    }

    private var permissions: some View {
        Form {
            LabeledContent("麦克风") { status(model.permissions.microphone) }
            LabeledContent("语音识别") { status(model.permissions.speech) }
            LabeledContent("辅助功能") { status(model.permissions.accessibility) }
            Button("授予权限") {
                Task { await model.requestPermissions() }
            }
            Button("打开系统隐私设置") {
                Permissions.openPrivacyRoot()
            }
            Text("辅助功能用于：定位当前输入框、直接写字，以及在网页等控件里发送 ⌘V。请在第一次用热键之前就点「授予权限」，避免录音中弹出系统框抢走焦点。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions() }
    }

    private func status(_ ok: Bool) -> some View {
        Text(ok ? "已允许" : "未允许")
            .foregroundStyle(ok ? .green : .orange)
    }
}
