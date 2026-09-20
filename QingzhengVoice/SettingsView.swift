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
            Text("把光标放在目标应用里，按快捷键说话，再按一次结束。清正语音不会把焦点抢到自己身上。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("预下载当前语言的本地模型") {
                Task { await model.installModelIfNeeded(interactive: true) }
            }
        }
        .formStyle(.grouped)
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
            Text("辅助功能只用于向当前应用发送 ⌘V。转写默认在本机完成；只有你选择云端整理时才会把文本（不是音频）发给对应接口。")
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
