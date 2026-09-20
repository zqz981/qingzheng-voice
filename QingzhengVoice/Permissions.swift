import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Speech

struct PermissionSnapshot: Equatable {
    var microphone = false
    var speech = false
    var accessibility = false

    var allGranted: Bool { microphone && speech && accessibility }
}

enum Permissions {
    static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphoneGranted,
            speech: SFSpeechRecognizer.authorizationStatus() == .authorized,
            accessibility: isAccessibilityTrusted(prompt: false)
        )
    }

    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    nonisolated static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings(for title: String) {
        switch title {
        case "麦克风":
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case "语音识别":
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        default:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    static func openPrivacyRoot() {
        open("x-apple.systempreferences:com.apple.preference.security")
    }

    private static func open(_ url: String) {
        if let value = URL(string: url) {
            NSWorkspace.shared.open(value)
        }
    }
}
