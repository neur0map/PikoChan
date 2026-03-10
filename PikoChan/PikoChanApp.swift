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
    private var heartbeat: PikoHeartbeat?
    private var cronService: PikoCronService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — PikoChan lives in the notch, not the taskbar.
        NSApp.setActivationPolicy(.accessory)

        let brain = PikoBrain()
        let manager = NotchManager(brain: brain)

        // Voice components.
        let capture = PikoAudioCapture()
        capture.warmUp()
        manager.voiceCapture = capture
        manager.stt = PikoSTT()
        manager.tts = PikoTTS()

        // Now Playing — system-wide music detection.
        let nowPlaying = PikoNowPlaying()
        manager.nowPlaying = nowPlaying

        manager.start()
        manager.startMusicObservation()
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

        // Heartbeat — environmental awareness + proactive nudges.
        let hb = PikoHeartbeat(brain: brain, notchManager: manager)
        hb.start()
        heartbeat = hb
        manager.heartbeat = hb
        server.heartbeat = hb

        // Cron scheduler — persistent recurring jobs.
        let cronStore = PikoCronStore(cronDir: PikoHome().cronDir)
        let cron = PikoCronService(store: cronStore, notchManager: manager)
        cron.start()
        cronService = cron
        manager.cronService = cron
        server.cronService = cron

        // MCP client — external tool servers.
        PikoMCPManager.shared.loadServers()
        manager.mcpManager = PikoMCPManager.shared
        server.mcpManager = PikoMCPManager.shared

        // Auto-start local TTS server if configured.
        let voiceConfig = PikoVoiceConfigStore.shared.currentConfig
        if voiceConfig.ttsProvider == .local && !voiceConfig.localModelPath.isEmpty {
            PikoVoiceServer.shared.start(modelPath: voiceConfig.localModelPath)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PikoMCPManager.shared.stopAll()
        cronService?.stop()
        PikoVoiceServer.shared.stop()
        heartbeat?.stop()
        httpServer?.stop()
        notchManager?.teardown()
    }
}
