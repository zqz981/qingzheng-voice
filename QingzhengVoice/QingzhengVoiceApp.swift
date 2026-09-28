import SwiftUI

@main
struct QingzhengVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(AppModel.shared)
                .environmentObject(AppModel.shared.settings)
        } label: {
            MenuBarLabel()
                .environmentObject(AppModel.shared)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(AppModel.shared)
                .environmentObject(AppModel.shared.settings)
        }
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Image(systemName: model.menuBarSymbol)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel("清正语音")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
}
