import SwiftUI

@main
struct PikoChanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows — the notch panel is managed by AppDelegate,
        // and settings are opened via SettingsWindowController.
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchManager: NotchManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — PikoChan lives in the notch, not the taskbar.
        NSApp.setActivationPolicy(.accessory)

        let manager = NotchManager()
        manager.start()
        notchManager = manager
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchManager?.teardown()
    }
}
