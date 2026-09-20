import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func attach(model: AppModel) {
        if panel != nil { return }
        let view = RecordingHUD()
            .environmentObject(model)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 128)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        self.panel = panel
        position()
    }

    func show() {
        hideWork?.cancel()
        position()
        panel?.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        if delay <= 0 {
            panel?.orderOut(nil)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct RecordingHUD: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.phase == .recording ? Color.red : Color.accentColor)
                    .frame(width: 8, height: 8)
                    .opacity(model.phase == .recording ? 1 : 0.7)
                Text(model.hudTitle)
                    .font(.headline)
                Spacer()
                Text(model.elapsedLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if model.liveText.isEmpty {
                Text(model.hudPlaceholder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(model.liveText)
                    .font(.subheadline)
                    .lineLimit(4)
            }
            if case .error(let message) = model.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.22))
        )
    }
}
