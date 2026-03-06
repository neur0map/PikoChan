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
    private var httpServer: PikoHTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — PikoChan lives in the notch, not the taskbar.
        NSApp.setActivationPolicy(.accessory)

        let brain = PikoBrain()
        let manager = NotchManager(brain: brain)
        manager.start()
        notchManager = manager

        // HTTP gateway — shares the same brain as the notch UI.
        let server = PikoHTTPServer(
            brain: brain,
            port: brain.config.gatewayPort,
            moodSetter: { [weak manager] mood in manager?.currentMood = mood }
        )
        do {
            try server.start()
        } catch {
            PikoGateway.shared.logError(
                message: "Failed to start HTTP server: \(error.localizedDescription)",
                subsystem: .http
            )
        }
        httpServer = server
    }

    func applicationWillTerminate(_ notification: Notification) {
        httpServer?.stop()
        notchManager?.teardown()
    }
}
