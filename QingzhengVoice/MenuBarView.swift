import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            permissionBlock
            statusBlock
            if !model.lastResult.isEmpty {
                resultBlock
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            controls
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { model.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.menuBarSymbol)
                .font(.title2)
                .foregroundStyle(model.phase == .recording ? Color.red : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("清正语音")
                    .font(.headline)
                Text("系统级中英语音输入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.modelReady ? "模型就绪" : "预热中")
                .font(.caption2)
                .foregroundStyle(model.modelReady ? Color.green : Color.secondary)
        }
    }

    @ViewBuilder
    private var permissionBlock: some View {
        if !model.permissions.allGranted {
            VStack(alignment: .leading, spacing: 6) {
                Text("需要这三项权限才能系统级插入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                permissionRow("麦克风", ok: model.permissions.microphone)
                permissionRow("语音识别", ok: model.permissions.speech)
                permissionRow("辅助功能", ok: model.permissions.accessibility)
                Button("授予权限") {
                    Task { await model.requestPermissions() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func permissionRow(_ title: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(title)
            Spacer()
            if !ok {
                Button("系统设置") { Permissions.openSettings(for: title) }
                    .controlSize(.mini)
            }
        }
        .font(.caption)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.statusLine)
                    .font(.subheadline)
                Spacer()
                if model.phase == .recording {
                    Text(model.elapsedLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if model.phase == .recording && !model.liveText.isEmpty {
                Text(model.liveText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("上次结果")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.lastResult)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("再插入一次") { model.retryLastInsert() }
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.lastResult, forType: .string)
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Text(model.phase == .recording ? "结束并插入" : (model.phase == .arming ? "取消" : "开始说话"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.phase.isBusy && model.phase != .recording && model.phase != .arming)
            .keyboardShortcut(.space, modifiers: [.control, .option])

            Toggle("整理文本", isOn: $settings.polishEnabled)
            HStack {
                Button("设置…") { openSettings() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}
