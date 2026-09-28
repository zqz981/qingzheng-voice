import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TextInserter {
    static let shared = TextInserter()

    func insert(_ text: String, into target: FocusTarget) async throws {
        guard Permissions.isAccessibilityTrusted(prompt: false) else {
            throw InsertFailure.accessibility
        }
        if target.isSecureField {
            throw InsertFailure.secureField
        }
        if target.isOwnApp || target.app == nil {
            throw InsertFailure.noTargetField
        }
        if target.insertViaAccessibility(text) {
            restore(target)
            return
        }
        try await paste(text, into: target)
        restore(target)
    }

    private func paste(_ text: String, into target: FocusTarget) async throws {
        restore(target)
        try await Task.sleep(for: .milliseconds(40))
        let backup = PasteboardBackup.capture()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            backup.restore()
            throw InsertFailure.clipboard
        }
        try await Task.sleep(for: .milliseconds(80))
        try postPaste(to: target.app)
        try await Task.sleep(for: .milliseconds(280))
        backup.restore()
    }

    private func restore(_ target: FocusTarget) {
        guard let app = target.app, !app.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func postPaste(to app: NSRunningApplication?) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw InsertFailure.event
        }
        let keyV: CGKeyCode = 9
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else {
            throw InsertFailure.event
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        if let pid = app?.processIdentifier {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

enum InsertFailure: LocalizedError {
    case accessibility
    case clipboard
    case event
    case secureField
    case noTargetField

    var errorDescription: String? {
        switch self {
        case .accessibility:
            return "需要辅助功能权限才能把文字写进当前输入框"
        case .clipboard:
            return "无法写入剪贴板"
        case .event:
            return "无法发送粘贴快捷键"
        case .secureField:
            return "当前是密码框，不会插入语音文本"
        case .noTargetField:
            return "没有定位到其它应用的输入框。请把光标放在目标里，再用 Control-Option-空格"
        }
    }
}

private struct PasteboardBackup {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture() -> PasteboardBackup {
        let captured = NSPasteboard.general.pasteboardItems?.map { item in
            var bag: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    bag[type] = data
                }
            }
            return bag
        } ?? []
        return PasteboardBackup(items: captured)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let objects: [NSPasteboardItem] = items.map { bag in
            let item = NSPasteboardItem()
            for (type, data) in bag {
                item.setData(data, forType: type)
            }
            return item
        }
        if !objects.isEmpty {
            pasteboard.writeObjects(objects)
        }
    }
}
