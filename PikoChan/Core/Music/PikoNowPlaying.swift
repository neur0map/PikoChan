import AppKit
import CoreAudio
import Observation

/// Observes system-wide Now Playing state via a hybrid approach:
/// 1. MediaRemote (private framework) — for apps that register (Spotify, Music, Chrome)
/// 2. CoreAudio + window title parsing — fallback for browsers that don't register
/// 3. iTunes Search API — fetches album art when MediaRemote has none
@Observable
final class PikoNowPlaying {

    // MARK: - Published State

    var isPlaying: Bool = false
    var trackTitle: String = ""
    var artistName: String = ""
    var albumArt: NSImage? = nil
    var sourceName: String = ""

    /// True when we have a valid track (even if paused).
    var hasTrack: Bool { !trackTitle.isEmpty }

    /// True when MediaRemote has an active session (native app).
    var hasMediaRemoteSession: Bool = false

    // MARK: - Private

    private let bridge = MediaRemoteBridge.shared
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var lastWindowTitle: String = ""

    /// Track the last query sent to iTunes to avoid duplicate fetches.
    private var lastArtFetchQuery: String = ""
    private var artFetchTask: Task<Void, Never>?

    /// Counts consecutive empty MR responses to stop polling it.
    private var mrEmptyStreak: Int = 0
    private static let mrGiveUpAfter = 3

    /// When the user taps play/pause, suppress poll overrides briefly.
    private var userControlUntil: ContinuousClock.Instant = .now

    /// Known browser bundle IDs for window title fallback.
    private static let browserBundleIDs: Set<String> = [
        "ai.perplexity.comet",
        "com.apple.Safari",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",  // Arc
        "app.zen-browser.zen",
        "com.nickvision.application",  // Parabolic etc.
    ]

    /// YouTube title pattern: "Track - Artist - YouTube"
    /// Some browsers append " - Audio playing - BrowserName"
    private static let youtubePattern = try! NSRegularExpression(
        pattern: #"^(.+?)\s*[-–—]\s*(.+?)\s*[-–—]\s*YouTube"#
    )

    init() {}

    deinit {
        stopListening()
    }

    // MARK: - Lifecycle

    func startListening() {
        // Register MediaRemote (primary — for native apps).
        if bridge.isAvailable {
            bridge.registerForNotifications()

            if let name = bridge.nowPlayingInfoDidChange {
                let obs = NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    self?.fetchMediaRemote()
                }
                observers.append(obs)
            }

            if let name = bridge.nowPlayingAppDidChange {
                let obs = NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    // New app registered — reset streak so we re-probe MR.
                    self?.mrEmptyStreak = 0
                    self?.fetchMediaRemote()
                }
                observers.append(obs)
            }

            if let name = bridge.nowPlayingAppIsPlayingDidChange {
                let obs = NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    self?.fetchMediaRemote()
                }
                observers.append(obs)
            }
        }

        // Fallback poll: CoreAudio + window title (for browsers that don't register).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollFallback()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)

        // Initial fetch.
        fetchMediaRemote()
        pollFallback()
    }

    func stopListening() {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
        bridge.unregisterForNotifications()
        pollTimer?.invalidate()
        pollTimer = nil
        artFetchTask?.cancel()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if hasMediaRemoteSession {
            bridge.sendCommand(.togglePlayPause)
        } else {
            Self.sendMediaKey(keyCode: 16) // Play/Pause
        }
        isPlaying.toggle()
        // Suppress poll overrides for 4 seconds so the UI stays correct.
        userControlUntil = .now + .seconds(4)
    }

    func nextTrack() {
        if hasMediaRemoteSession {
            bridge.sendCommand(.nextTrack)
        } else {
            Self.sendMediaKey(keyCode: 17) // Next
        }
    }

    func previousTrack() {
        if hasMediaRemoteSession {
            bridge.sendCommand(.previousTrack)
        } else {
            Self.sendMediaKey(keyCode: 20) // Previous
        }
    }

    /// Simulate a hardware media key press via CGEvent.
    /// Key codes: 16 = play/pause, 17 = next, 20 = previous.
    private static func sendMediaKey(keyCode: UInt32) {
        // Media keys use NX_SYSDEFINED events with subtype 8.
        // data1 format: (keyCode << 16) | flags
        // flags: 0x0A00 = key down, 0x0B00 = key up
        func post(down: Bool) {
            let data1 = Int(keyCode << 16) | (down ? 0x0A_00 : 0x0B_00)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    // MARK: - MediaRemote Fetch (Primary)

    private func fetchMediaRemote() {
        // Stop querying MR after repeated failures to avoid log spam.
        guard mrEmptyStreak < Self.mrGiveUpAfter else { return }

        bridge.getNowPlayingInfo { [weak self] info in
            guard let self else { return }

            let title = (info[MediaRemoteBridge.titleKey] as? String) ?? ""

            if !title.isEmpty {
                self.mrEmptyStreak = 0
                self.hasMediaRemoteSession = true
                self.trackTitle = title
                self.artistName = (info[MediaRemoteBridge.artistKey] as? String) ?? ""

                if let artworkData = info[MediaRemoteBridge.artworkDataKey] as? Data,
                   let image = NSImage(data: artworkData) {
                    self.albumArt = image
                }

                if let rate = info[MediaRemoteBridge.playbackRateKey] as? Double {
                    self.isPlaying = rate > 0
                }
            } else {
                self.mrEmptyStreak += 1
                self.hasMediaRemoteSession = false
            }
        }
    }

    // MARK: - Fallback Poll (CoreAudio + Window Title)

    private func pollFallback() {
        let audioRunning = Self.isAudioDeviceRunning()

        if audioRunning {
            if hasMediaRemoteSession {
                // MR was working last time — check if it still has data.
                bridge.getNowPlayingInfo { [weak self] info in
                    guard let self else { return }
                    let mrTitle = info[MediaRemoteBridge.titleKey] as? String ?? ""
                    if mrTitle.isEmpty {
                        self.hasMediaRemoteSession = false
                        self.detectFromBrowserWindows()
                    }
                }
            } else {
                // No MR session — go straight to browser detection (no MR calls).
                detectFromBrowserWindows()
            }
        } else {
            // No audio — mark stopped (respect user cooldown).
            if isPlaying && !hasMediaRemoteSession && ContinuousClock.now > userControlUntil {
                isPlaying = false
            }
        }
    }

    /// Reads browser window titles to find YouTube / music service playing.
    private func detectFromBrowserWindows() {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            guard let bundleID = app.bundleIdentifier,
                  Self.browserBundleIDs.contains(bundleID),
                  !app.isTerminated else { continue }

            guard let appName = app.localizedName else { continue }

            // Read the front window title via Accessibility API.
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            for window in windows {
                var titleRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                      let title = titleRef as? String else { continue }

                // Look for "Audio playing" or "YouTube" in title.
                if title.contains("YouTube") || title.contains("Audio playing") || title.contains("Spotify") {
                    if title != lastWindowTitle {
                        lastWindowTitle = title
                        parseWindowTitle(title, browser: appName)
                    }
                    // Confirm playing — but respect user's recent play/pause tap.
                    if ContinuousClock.now > userControlUntil && !isPlaying {
                        isPlaying = true
                    }
                    return
                }
            }
        }
    }

    /// Parse "Track - Artist - YouTube - Audio playing - Browser" pattern.
    private func parseWindowTitle(_ title: String, browser: String) {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)

        if let match = Self.youtubePattern.firstMatch(in: title, range: range) {
            let trackRange = Range(match.range(at: 1), in: title)!
            let artistRange = Range(match.range(at: 2), in: title)!
            trackTitle = String(title[trackRange]).trimmingCharacters(in: .whitespaces)
            artistName = String(title[artistRange]).trimmingCharacters(in: .whitespaces)
            sourceName = browser
            albumArt = nil
        } else {
            // Fallback: use the whole title before " - YouTube" or " - Audio playing".
            let cleaned = title
                .replacingOccurrences(of: " - Audio playing", with: "")
                .replacingOccurrences(of: " - \(browser)", with: "")
            trackTitle = cleaned.trimmingCharacters(in: .whitespaces)
            artistName = ""
            sourceName = browser
            albumArt = nil
        }

        // Fetch album art from iTunes Search API.
        fetchAlbumArtFromWeb()
    }

    // MARK: - iTunes Album Art Fetch

    private func fetchAlbumArtFromWeb() {
        let query = [trackTitle, artistName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty, query != lastArtFetchQuery else { return }
        lastArtFetchQuery = query

        artFetchTask?.cancel()
        artFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
                guard let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else { return }

                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let first = results.first,
                      let artURL = first["artworkUrl100"] as? String else { return }

                // Upgrade to 600x600 for crisp art.
                let hiRes = artURL.replacingOccurrences(of: "100x100", with: "600x600")
                guard let imageURL = URL(string: hiRes) else { return }

                let (imageData, _) = try await URLSession.shared.data(from: imageURL)
                guard !Task.isCancelled else { return }

                if let image = NSImage(data: imageData) {
                    await MainActor.run {
                        // Only set if we're still on the same track.
                        if self.lastArtFetchQuery == query {
                            self.albumArt = image
                        }
                    }
                }
            } catch {
                // Silently fail — album art is non-critical.
            }
        }
    }

    // MARK: - CoreAudio Helpers

    /// Checks if the default output audio device has active audio streams.
    private static func isAudioDeviceRunning() -> Bool {
        var deviceID = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return false }

        var isRunning: UInt32 = 0
        var runAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var runSize = UInt32(MemoryLayout<UInt32>.size)
        let runStatus = AudioObjectGetPropertyData(deviceID, &runAddr, 0, nil, &runSize, &isRunning)
        guard runStatus == noErr else { return false }

        return isRunning != 0
    }
}
