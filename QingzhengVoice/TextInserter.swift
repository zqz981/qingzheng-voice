import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TextInserter {
    static let shared = TextInserter()

    func insert(_ text: String) async throws {
        guard Permissions.isAccessibilityTrusted(prompt: true) else {
            throw InsertFailure.accessibility
        }
        let backup = PasteboardBackup.capture()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            backup.restore()
            throw InsertFailure.clipboard
        }
        try await Task.sleep(for: .milliseconds(90))
        try postPaste()
        try await Task.sleep(for: .milliseconds(280))
        backup.restore()
    }

    private func postPaste() throws {
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
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

enum InsertFailure: LocalizedError {
    case accessibility
    case clipboard
    case event

    var errorDescription: String? {
        switch self {
        case .accessibility:
            return "需要辅助功能权限才能把文字贴进当前应用"
        case .clipboard:
            return "无法写入剪贴板"
        case .event:
            return "无法发送粘贴快捷键"
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
