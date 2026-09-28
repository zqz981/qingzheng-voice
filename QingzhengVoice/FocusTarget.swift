import AppKit
import ApplicationServices
import Carbon
import Foundation

struct FocusTarget {
    let app: NSRunningApplication?
    let element: AXUIElement?
    let role: String
    let isSecureField: Bool
    let isOwnApp: Bool

    var canUseAccessibilityTyping: Bool {
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField"
        ]
        return element != nil && textRoles.contains(role) && !isSecureField && !isOwnApp
    }

    static func capture() -> FocusTarget {
        let front = NSWorkspace.shared.frontmostApplication
        let own = front?.bundleIdentifier == Bundle.main.bundleIdentifier
        var role = ""
        var secure = false
        var element: AXUIElement?

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused {
            let ax = unsafeBitCast(focused, to: AXUIElement.self)
            element = ax
            role = stringAttribute(ax, kAXRoleAttribute as String) ?? ""
            let subrole = stringAttribute(ax, kAXSubroleAttribute as String) ?? ""
            secure = role == (kAXSecureTextFieldRole as String) || subrole.contains("Secure")
        }

        return FocusTarget(
            app: front,
            element: element,
            role: role,
            isSecureField: secure || IsSecureEventInputEnabled(),
            isOwnApp: own
        )
    }

    func insertViaAccessibility(_ text: String) -> Bool {
        guard canUseAccessibilityTyping, let element else { return false }
        if setAttribute(element, kAXSelectedTextAttribute as String, text as CFTypeRef) {
            return true
        }
        return spliceValue(element, text)
    }

    private func spliceValue(_ element: AXUIElement, _ text: String) -> Bool {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let current = valueRef as? String
        else { return false }

        var range = CFRange(location: (current as NSString).length, length: 0)
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let axRange = rangeRef {
            let axValue = unsafeBitCast(axRange, to: AXValue.self)
            _ = AXValueGetValue(axValue, .cfRange, &range)
        }

        let ns = current as NSString
        let location = max(0, min(range.location, ns.length))
        let length = max(0, min(range.length, ns.length - location))
        let inserted = ns.substring(to: location) + text + ns.substring(from: location + length)
        guard setAttribute(element, kAXValueAttribute as String, inserted as CFTypeRef) else { return false }

        var caret = CFRange(location: location + (text as NSString).length, length: 0)
        if let caretValue = AXValueCreate(.cfRange, &caret) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, caretValue)
        }
        return true
    }

    private func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        guard settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
