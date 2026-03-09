import AppKit
import AVFoundation
import SwiftUI
import Observation

/// Owns the floating panel, tracks mouse proximity, and drives state transitions.
@Observable
final class NotchManager {

    enum Mood: String, CaseIterable {
        case neutral = "Neutral"
        case playful = "Playful"
        case irritated = "Irritated"
        case proud = "Proud"
        case concerned = "Concerned"
        case snarky = "Snarky"
        case encouraging = "Encouraging"
    }

    // MARK: - State

    var state: NotchState = .hidden
    var notchSize: CGSize = .zero
    var menubarHeight: CGFloat = 0
    var inputText: String = ""
    var currentMood: Mood = .neutral
    var isResponding: Bool = false
    var lastResponseText: String = ""
    var lastResponseError: String?
    var lastResponseSuggestion: String?
    var lastErrorOpensSettings: Bool = false
    var isResponseExpanded: Bool = false
    var showsChatHistory: Bool = false

    var recentHistory: [ChatTurn] {
        brain.history.suffix(3).map { turn in
            let (_, clean) = MoodParser.parse(from: turn.assistant)
            return ChatTurn(user: turn.user, assistant: clean, at: turn.at, mood: turn.mood)
        }
    }

    var activeProviderLabel: String {
        switch brain.config.provider {
        case .local:              brain.config.localModel
        case .openai:             brain.config.openAIModel
        case .anthropic:          brain.config.anthropicModel
        case .apple:              "Apple Intelligence"
        case .openrouter:         brain.config.openRouterModel
        case .groq:               brain.config.groqModel
        case .huggingface:        brain.config.huggingFaceModel
        case .dockerModelRunner:  brain.config.dockerModelRunnerModel
        case .vllm:               brain.config.vllmModel
        }
    }

    /// Remembers what the user was doing before hiding, so reopening resumes.
    private var lastActiveState: NotchState = .expanded

    // MARK: - Setup Wizard

    private(set) var setupManager: SetupManager?

    // MARK: - Window

    private(set) var panel: PikoPanel?
    private var panelSize: CGSize = .zero
    private var moodImages: [Mood: NSImage] = [:]
    let brain: PikoBrain
    /// Set by AppDelegate after heartbeat is created, so config commands can schedule nudges.
    var heartbeat: PikoHeartbeat?

    // MARK: - Voice

    var voiceCapture: PikoAudioCapture?
    var stt: PikoSTT?
    var tts: PikoTTS?
    var isRecording: Bool = false
    var isSpeaking: Bool = false
    private var lastInputWasVoice: Bool = false
    private var audioPlayer: AVAudioPlayer?
    private var currentAudioTmpFile: URL?

    let actionHandler = PikoActionHandler()

    // MARK: - Activity Feed

    var feedItems: [PikoFeedItem] = []
    var isFeedExpanded: Bool = false

    /// Whether the feed has content worth showing.
    var hasFeedContent: Bool {
        !feedItems.isEmpty || isResponding
    }

    func addFeedItem(_ kind: PikoFeedKind) {
        feedItems.append(PikoFeedItem(kind: kind))
    }

    func clearFeed() {
        feedItems.removeAll()
        isFeedExpanded = false
        actionHandler.sessionAutoApprove = false
    }

    // MARK: - Music

    var nowPlaying: PikoNowPlaying?
    private var musicObservationTask: Task<Void, Never>?

    init(brain: PikoBrain) {
        self.brain = brain
    }

    // MARK: - Monitors

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalRightClickMonitor: Any?
    private var localRightClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var hoverDebounceTask: Task<Void, Never>?
    private var currentResponseTask: Task<Void, Never>?
    private var moodDecayTask: Task<Void, Never>?
    private var hoverPollTimer: Timer?
    private let menuTarget = ContextMenuTarget()
    private var suppressNextGlobalClick = false

    // MARK: - Geometry

    private var hoverZone: NSRect = .zero

    // MARK: - Setup

    func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        do {
            try brain.bootstrap()
        } catch {
            lastResponseError = "Couldn't set up config folder"
            lastResponseSuggestion = "Check permissions on ~/.pikochan/"
        }
        loadMoodImages()
        PikoSkillLoader.shared.reload()
        setupPanel(on: screen)
        installMonitors()
        observeScreenChanges()
        observeSettingsWindow()
        observeGeometrySettings()
        observeRerunSetup()
        observeConfigSave()

        // Launch setup wizard if not completed.
        if !brain.config.setupComplete {
            startSetupWizard()
        }
    }

    func startSetupWizard() {
        setupManager = SetupManager()
        transition(to: .setup)
    }

    func teardown() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
        moodDecayTask?.cancel()
        moodDecayTask = nil
        musicObservationTask?.cancel()
        musicObservationTask = nil
        nowPlaying?.stopListening()
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Music Observation

    func startMusicObservation() {
        guard let np = nowPlaying else { return }
        np.startListening()

        // Poll for changes since @Observable withObservationTracking
        // can't drive state transitions from a non-view context easily.
        musicObservationTask = Task { [weak self] in
            var wasPlaying = false
            var stoppedAt: ContinuousClock.Instant?
            let gracePeriod: Duration = .seconds(5)

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { break }
                let playing = np.isPlaying && np.hasTrack

                if playing && !wasPlaying {
                    stoppedAt = nil
                    // Music started — show compact if idle.
                    if self.state == .hidden || self.state == .hovered {
                        self.transition(to: .musicCompact)
                    }
                } else if !playing && wasPlaying {
                    // Music stopped — start grace period.
                    stoppedAt = .now
                } else if !playing, let stopped = stoppedAt {
                    // Still stopped — collapse after grace period.
                    if ContinuousClock.now - stopped > gracePeriod, self.state.isMusic {
                        self.transition(to: .hidden)
                        stoppedAt = nil
                    }
                }
                wasPlaying = playing
            }
        }
    }

    /// Switch from music extended to assistant mode.
    func switchToAssistant() {
        transition(to: .expanded)
    }

    /// Switch from assistant back to music extended.
    func switchToMusicExtended() {
        transition(to: .musicExtended)
    }

    // MARK: - Panel Setup

    private func setupPanel(on screen: NSScreen) {
        panel?.orderOut(nil)

        let settings = PikoSettings.shared
        let notchRect = screen.notchFrameOrMenubar
        notchSize = CGSize(
            width: notchRect.size.width + settings.notchWidthOffset,
            height: notchRect.size.height + settings.notchHeightOffset
        )
        menubarHeight = screen.menubarHeight

        let pw: CGFloat = max(380, notchSize.width + 200)
        let ph: CGFloat = 480
        panelSize = CGSize(width: pw, height: ph)

        let origin = NSPoint(
            x: screen.frame.midX - pw / 2,
            y: screen.frame.maxY - ph
        )

        let p = PikoPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: pw, height: ph)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostView = NSHostingView(rootView: NotchContentView(manager: self))
        hostView.frame = NSRect(origin: .zero, size: NSSize(width: pw, height: ph))
        p.contentView = hostView
        p.ignoresMouseEvents = true
        p.orderFrontRegardless()

        panel = p
        updateVisibleContentRect()

        let hzPad = settings.hoverZonePadding
        hoverZone = NSRect(
            x: notchRect.origin.x - 10,
            y: notchRect.origin.y - hzPad,
            width: notchRect.width + 20,
            height: notchRect.height + hzPad
        )
    }

    // MARK: - Visible Content Rect

    func updateVisibleContentRect() {
        guard let panel else { return }
        let cw = contentWidth
        let ch = contentHeight
        let screenRect = NSRect(
            x: panel.frame.midX - cw / 2,
            y: panel.frame.maxY - ch,
            width: cw,
            height: ch
        )
        panel.visibleContentScreenRect = screenRect
    }

    private var contentWidth: CGFloat {
        switch state {
        case .hidden:    notchSize.width
        case .hovered:   notchSize.width
        case .musicCompact, .musicHover:
            musicCompactWidth
        case .musicExtended:
            musicExtendedWidth
        case .expanded, .typing, .listening, .setup:
            activeContentWidth
        }
    }

    private var contentHeight: CGFloat {
        let pad = PikoSettings.shared.contentPadding
        return switch state {
        case .hidden:    notchSize.height
        case .hovered:   notchSize.height + pad + 12
        case .musicCompact, .musicHover:
            musicCompactHeight
        case .musicExtended:
            musicExtendedHeight
        case .expanded, .typing, .listening:
            activeContentHeight
        case .setup:
            setupContentHeight
        }
    }

    // MARK: - Music Geometry

    /// Whether the user is hovering over the compact music pill.
    var isHoveringMusicArt: Bool = false {
        didSet { updateVisibleContentRect() }
    }

    /// Compact pill stretches beyond notch to fit art + bars.
    var musicCompactWidth: CGFloat {
        isHoveringMusicArt ? notchSize.width + 140 : notchSize.width + 100
    }
    var musicCompactHeight: CGFloat {
        isHoveringMusicArt ? notchSize.height + 34 : notchSize.height
    }

    /// Extended mini-player.
    var musicExtendedWidth: CGFloat { 340 }
    var musicExtendedHeight: CGFloat { notchSize.height + PikoSettings.shared.contentPadding + 100 }

    var setupContentHeight: CGFloat {
        let pad = PikoSettings.shared.contentPadding
        return notchSize.height + pad + 320
    }

    var activeContentWidth: CGFloat {
        hasFeedContent ? 360 : 290
    }

    var showsResponseBubble: Bool {
        isResponding || !lastResponseText.isEmpty || lastResponseError != nil || showsChatHistory
    }

    private var actionBlockHeight: CGFloat {
        let actions = actionHandler.actions
        guard !actions.isEmpty else { return 0 }
        var total: CGFloat = 0
        for action in actions {
            var h: CGFloat = 44
            if case .completed(let r) = action.status, !r.stdout.isEmpty || !r.stderr.isEmpty {
                h += 60
            }
            total += h
        }
        total += CGFloat(max(0, actions.count - 1)) * 4
        return total
    }

    private var responseBlockHeight: CGFloat {
        guard showsResponseBubble || !actionHandler.actions.isEmpty else { return 0 }
        let base: CGFloat = showsResponseBubble ? (isResponseExpanded ? 230 : 86) : 0
        return base + actionBlockHeight
    }

    /// Height of the feed block when feed is active.
    private var feedBlockHeight: CGFloat {
        guard hasFeedContent else { return 0 }
        return isFeedExpanded ? 320 : 140
    }

    var activeContentHeight: CGFloat {
        let pad = PikoSettings.shared.contentPadding
        let sprite = PikoSettings.shared.spriteSize

        // When feed has content, use feed-based layout (sprite is beside feed, not above).
        // Mini buttons are inside the feed area, so .expanded needs no extra control height.
        if hasFeedContent {
            let base = notchSize.height + pad + feedBlockHeight
            switch state {
            case .typing:
                return base + 8 + 34 + 12    // gap + text field + bottom
            case .listening:
                return base + 6 + 80 + 12    // gap + wave/mic controls + bottom
            default:
                return base + 16              // just bottom breathing room
            }
        }

        // Legacy layout: sprite above controls above response bubble.
        let expandedHeight = notchSize.height + pad + sprite + 12 + 36 + 16 + responseBlockHeight
        let typingHeight = notchSize.height + pad + sprite + 8 + 34 + 12 + responseBlockHeight
        let listeningHeight = notchSize.height + pad + sprite + 6 + 28 + 2 + 44 + 12 + responseBlockHeight
        return max(expandedHeight, max(typingHeight, listeningHeight))
    }

    // MARK: - State Transitions

    func transition(to newState: NotchState) {
        guard newState != state else { return }

        // Clean up setup wizard when leaving .setup state.
        if state == .setup && newState != .setup {
            setupManager = nil
        }

        // Reset music art hover when leaving compact.
        if state.isMusic && !newState.isMusic {
            isHoveringMusicArt = false
        }

        // Remember what the user was doing before hiding (but not .setup or music states).
        if newState == .hidden && state != .hovered && state != .setup && !state.isMusic {
            lastActiveState = state
        }

        let animation: Animation = switch newState {
        case .hidden:
            .smooth(duration: 0.25)
        case .hovered:
            .spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.15)
        case .musicCompact:
            .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2)
        case .musicHover:
            .spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)
        case .musicExtended:
            .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.2)
        case .expanded:
            .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.2)
        case .typing:
            .spring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.15)
        case .listening:
            .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.2)
        case .setup:
            .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.2)
        }

        withAnimation(animation) {
            state = newState
        }

        switch newState {
        case .hidden:
            // Cancel in-flight response when hiding.
            if isResponding {
                cancelResponse()
            }
            // Only hidden truly ignores all mouse events.
            panel?.ignoresMouseEvents = true
            panel?.styleMask.insert(.nonactivatingPanel)
            panel?.syncActivationState()

        case .hovered:
            // Hovered must receive events so SwiftUI .onHover and click work.
            panel?.ignoresMouseEvents = false
            panel?.styleMask.insert(.nonactivatingPanel)
            panel?.syncActivationState()

        case .musicCompact, .musicHover:
            // Music compact/hover: receive events but don't activate.
            panel?.ignoresMouseEvents = false
            panel?.styleMask.insert(.nonactivatingPanel)
            panel?.syncActivationState()

        case .musicExtended:
            // Extended music needs interaction for playback controls.
            panel?.ignoresMouseEvents = false
            panel?.styleMask.insert(.nonactivatingPanel)
            panel?.syncActivationState()
            panel?.makeKey()

        case .expanded:
            panel?.ignoresMouseEvents = false
            panel?.styleMask.insert(.nonactivatingPanel)
            panel?.syncActivationState()
            panel?.makeKey()

        case .listening:
            // Mic capture needs activation (same as .typing).
            panel?.ignoresMouseEvents = false
            panel?.styleMask.remove(.nonactivatingPanel)
            panel?.syncActivationState()
            NSApp.activate()
            panel?.makeKey()

        case .typing, .setup:
            // Typing and setup remove .nonactivatingPanel so macOS connects
            // the text input service chain (FB16484811).
            panel?.ignoresMouseEvents = false
            panel?.styleMask.remove(.nonactivatingPanel)
            panel?.syncActivationState()
            NSApp.activate()
            panel?.makeKey()
        }

        updateVisibleContentRect()
    }

    /// Reopen to whatever the user was last doing.
    func reopen() {
        transition(to: lastActiveState)
    }

    var spriteImage: Image {
        if let moodImage = moodImages[currentMood] {
            Image(nsImage: moodImage)
        } else {
            Image("pikochan_sprite")
        }
    }

    @discardableResult
    func applyMoodCommand(from rawText: String) -> Bool {
        guard let mood = Self.parseMood(from: rawText) else { return false }
        currentMood = mood
        lastResponseError = nil
        lastResponseText = "Mood set to \(mood.rawValue)."
        return true
    }

    func submitTextInput() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard !isResponding else { return }

        if applyMoodCommand(from: prompt) {
            inputText = ""
            transition(to: .expanded)
            return
        }

        // Cancel any previous in-flight request.
        currentResponseTask?.cancel()

        inputText = ""
        isResponding = true
        lastResponseError = nil
        lastResponseSuggestion = nil
        lastErrorOpensSettings = false
        lastResponseText = ""
        isResponseExpanded = false
        showsChatHistory = false
        addFeedItem(.userMessage(prompt))
        transition(to: .expanded)

        currentResponseTask = Task { [weak self] in
            guard let self else { return }
            self.brain.reloadConfig()
            self.resetMoodDecay()
            PikoGateway.shared.logUserMessage(prompt, mood: self.currentMood.rawValue)

            var hasContent = false
            var moodParsed = false
            var rawAccumulated = ""
            for await chunk in self.brain.respondStreaming(to: prompt, mood: self.currentMood) {
                guard !Task.isCancelled else { break }
                // Detect embedded error markers from the stream.
                if chunk.hasPrefix("\n\n[Error: ") {
                    let errorText = chunk
                        .replacingOccurrences(of: "\n\n[Error: ", with: "")
                        .replacingOccurrences(of: "]", with: "")
                    self.setError(fromLocalizedDescription: errorText)
                } else {
                    rawAccumulated += chunk

                    // Parse mood tag from accumulated text once we see `]`.
                    if !moodParsed && rawAccumulated.contains("]") {
                        let (parsedMood, cleanText) = MoodParser.parse(from: rawAccumulated)
                        if let parsedMood {
                            let oldMood = self.currentMood
                            self.currentMood = parsedMood
                            if oldMood != parsedMood {
                                PikoGateway.shared.logMoodChange(
                                    from: oldMood.rawValue,
                                    to: parsedMood.rawValue,
                                    trigger: "llm_response"
                                )
                            }
                        }
                        moodParsed = true
                        self.lastResponseText = cleanText
                    } else if moodParsed {
                        self.lastResponseText += chunk
                    }
                    // While mood not yet parsed, don't display raw tag to user.

                    hasContent = true
                }
            }

            // If mood was never parsed (no `]` found), display full text.
            if !moodParsed && !rawAccumulated.isEmpty {
                self.lastResponseText = rawAccumulated
            }

            // Parse action tags + execute actions.
            if !self.lastResponseText.isEmpty {
                self.actionHandler.reset()
                let (cleanText, actions) = self.actionHandler.parseActions(from: self.lastResponseText)
                self.lastResponseText = cleanText

                // Add assistant message to feed (with action tags stripped).
                if !cleanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.addFeedItem(.assistantMessage(cleanText))
                }

                // Add action references to feed.
                for action in actions {
                    self.addFeedItem(.actionRef(action.id))
                }

                if !actions.isEmpty {
                    // Lower panel so macOS permission dialogs (TCC) are clickable.
                    self.panel?.level = .floating
                    let _ = await self.actionHandler.executeAutoApproved()
                    self.panel?.level = .screenSaver

                    // Re-query LLM for summary if any shell commands completed.
                    if self.actionHandler.hasCompletedShellActions {
                        self.isResponding = true
                        self.isResponseExpanded = false
                        let requeryMsg = self.actionHandler.formatResultsForRequery()
                        if let summary = try? await self.brain.respond(
                            to: requeryMsg,
                            mood: self.currentMood,
                            skipMemoryExtraction: true,
                            skipHistory: true
                        ) {
                            let (parsedMood, summaryClean) = MoodParser.parse(from: summary)
                            if let parsedMood { self.currentMood = parsedMood }
                            self.lastResponseText = summaryClean
                            self.addFeedItem(.assistantMessage(summaryClean))
                        }
                        self.isResponding = false
                        self.updateVisibleContentRect()
                    }
                } else if cleanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasContent {
                    // No actions and no clean text but had content — add raw response.
                    self.addFeedItem(.assistantMessage(self.lastResponseText))
                }
            } else if hasContent {
                // Response had content but lastResponseText ended up empty after mood parse.
                // This shouldn't normally happen, but handle gracefully.
            }

            // Parse config commands + scheduled nudges from response.
            if !self.lastResponseText.isEmpty {
                let parsed = PikoConfigCommand.parse(from: self.lastResponseText)
                self.lastResponseText = parsed.cleanText
                PikoConfigCommand.applyConfigChanges(parsed.configChanges)
                if let nudge = parsed.scheduledNudge {
                    self.heartbeat?.scheduleNudge(
                        afterSeconds: nudge.delaySeconds,
                        message: nudge.message
                    )
                }

                // Auto-speak response if voice TTS is enabled.
                self.speakIfEnabled(self.lastResponseText)
            }

            if !Task.isCancelled {
                if !hasContent && self.lastResponseError == nil {
                    self.setError(message: "Model returned nothing", suggestion: "Try a different prompt or model")
                }
                self.isResponding = false
            } else {
                self.isResponding = false
            }
            self.currentResponseTask = nil
        }
    }

    /// PikoChan introduces herself after setup. No user message saved — just her greeting.
    func sendFirstMessage() {
        currentResponseTask?.cancel()
        isResponding = true
        lastResponseError = nil
        lastResponseSuggestion = nil
        lastErrorOpensSettings = false
        lastResponseText = ""
        isResponseExpanded = false
        transition(to: .expanded)

        currentResponseTask = Task { [weak self] in
            guard let self else { return }
            self.brain.reloadConfig()
            self.currentMood = .playful

            let introPrompt = "This is our first time meeting — I just set you up! Say hi to me."
            var hasContent = false
            var moodParsed = false
            var rawAccumulated = ""

            for await chunk in self.brain.respondStreaming(to: introPrompt, mood: .playful, skipHistory: true) {
                guard !Task.isCancelled else { break }
                if chunk.hasPrefix("\n\n[Error: ") {
                    let errorText = chunk
                        .replacingOccurrences(of: "\n\n[Error: ", with: "")
                        .replacingOccurrences(of: "]", with: "")
                    self.setError(fromLocalizedDescription: errorText)
                } else {
                    rawAccumulated += chunk
                    if !moodParsed && rawAccumulated.contains("]") {
                        let (parsedMood, cleanText) = MoodParser.parse(from: rawAccumulated)
                        if let parsedMood { self.currentMood = parsedMood }
                        moodParsed = true
                        self.lastResponseText = cleanText
                    } else if moodParsed {
                        self.lastResponseText += chunk
                    }
                    hasContent = true
                }
            }

            if !moodParsed && !rawAccumulated.isEmpty {
                self.lastResponseText = rawAccumulated
            }
            if !hasContent && self.lastResponseError == nil {
                // Fallback if LLM fails — hardcoded intro so user isn't left hanging.
                self.lastResponseText = "Hey! I'm \(self.brain.soul.name) — I live right here in your notch. What's your name?"
                self.currentMood = .playful
            }
            self.isResponding = false
            self.currentResponseTask = nil
        }
    }

    /// Execute a single user-confirmed action and re-query LLM for a personalized response.
    func executeAndRequery(_ action: PikoAction) async {
        // Lower panel so macOS permission dialogs (TCC) are clickable.
        panel?.level = .floating
        await actionHandler.execute(action)
        panel?.level = .screenSaver

        // Re-query LLM with command results so PikoChan responds with personality.
        if actionHandler.hasCompletedShellActions {
            isResponding = true
            lastResponseText = ""
            let requeryMsg = actionHandler.formatResultsForRequery()
            if let summary = try? await brain.respond(
                to: requeryMsg,
                mood: currentMood,
                skipMemoryExtraction: true,
                skipHistory: true
            ) {
                let (parsedMood, summaryClean) = MoodParser.parse(from: summary)
                if let parsedMood { currentMood = parsedMood }
                lastResponseText = summaryClean
                addFeedItem(.assistantMessage(summaryClean))
            }
            isResponding = false
        }
        updateVisibleContentRect()
    }

    func cancelResponse() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
        isResponding = false
    }

    // MARK: - Voice

    func startRecording() {
        guard !isRecording else { return }

        // Stop any ongoing TTS playback.
        stopSpeaking()

        Task {
            guard let capture = voiceCapture else { return }

            // Check + request permission.
            if !capture.hasPermission {
                let status = capture.currentPermissionStatus
                if status == .denied {
                    // Already denied — open System Settings directly.
                    openMicrophoneSettings()
                    return
                }
                // Lower panel so macOS permission dialog is clickable.
                let panel = self.panel
                panel?.level = .floating
                // Not determined — triggers the native permission dialog.
                let granted = await capture.requestPermission()
                panel?.level = .screenSaver
                guard granted else {
                    PikoGateway.shared.logError(message: "Microphone permission denied", subsystem: .voice)
                    openMicrophoneSettings()
                    return
                }
            }

            do {
                try capture.startCapture()
                isRecording = true
            } catch {
                PikoGateway.shared.logError(
                    message: "Failed to start audio capture: \(error.localizedDescription)",
                    subsystem: .voice
                )
                setError(message: "Can't access microphone", suggestion: error.localizedDescription)
            }
        }
    }

    private func openMicrophoneSettings() {
        // Collapse so the user can interact with System Settings.
        transition(to: .expanded)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false

        guard let audioData = voiceCapture?.stopCapture(), !audioData.isEmpty else {
            return
        }

        let voiceConfig = PikoVoiceConfigStore.shared.currentConfig
        guard voiceConfig.sttProvider != .none else {
            setError(message: "No STT provider configured", suggestion: "Set one in Settings → Voice")
            return
        }

        // Show transcribing state.
        isResponding = true
        lastResponseText = ""
        lastResponseError = nil
        transition(to: .expanded)

        Task {
            do {
                guard let stt else { return }
                let transcript = try await stt.transcribe(audioData: audioData, config: voiceConfig)
                guard !transcript.isEmpty else {
                    self.isResponding = false
                    return
                }
                self.isResponding = false
                self.lastInputWasVoice = true
                inputText = transcript
                submitTextInput()
            } catch {
                self.isResponding = false
                setError(message: "STT failed", suggestion: error.localizedDescription)
                PikoGateway.shared.logError(
                    message: "STT failed: \(error.localizedDescription)",
                    subsystem: .voice
                )
            }
        }
    }

    func speakIfEnabled(_ text: String) {
        let voiceConfig = PikoVoiceConfigStore.shared.currentConfig
        guard voiceConfig.ttsProvider != .none else { return }
        // Always speak when input was voice; otherwise respect autoSpeak toggle.
        let shouldSpeak = lastInputWasVoice || voiceConfig.autoSpeak
        lastInputWasVoice = false
        guard shouldSpeak else { return }
        speak(text, config: voiceConfig)
    }

    func speak(_ text: String, config: PikoVoiceConfig? = nil) {
        let voiceConfig = config ?? PikoVoiceConfigStore.shared.currentConfig
        guard voiceConfig.ttsProvider != .none else { return }

        Task {
            do {
                guard let tts else { return }
                isSpeaking = true
                // Pass current mood so TTS models with emotion support can use it.
                tts.moodHint = Self.moodToEmotionPrompt(currentMood)
                tts.currentMood = currentMood
                let audioData = try await tts.synthesize(text: text, config: voiceConfig)

                // Write to temp file with correct extension — AVAudioPlayer
                // is more reliable reading from a file than raw Data on macOS.
                let ext = Self.audioFileExtension(for: audioData)
                let tmpFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".\(ext)")
                try audioData.write(to: tmpFile)

                let player = try AVAudioPlayer(contentsOf: tmpFile)
                player.volume = 1.0
                player.prepareToPlay()
                self.audioPlayer = player
                self.currentAudioTmpFile = tmpFile

                guard player.play() else {
                    throw PikoVoiceError.ttsFailed(detail: "AVAudioPlayer.play() returned false")
                }

                while player.isPlaying {
                    try await Task.sleep(for: .milliseconds(100))
                }
                isSpeaking = false
                cleanupAudioPlayer()
            } catch {
                isSpeaking = false
                cleanupAudioPlayer()
                PikoGateway.shared.logError(
                    message: "TTS playback failed: \(error.localizedDescription)",
                    subsystem: .voice
                )
            }
        }
    }

    private func stopSpeaking() {
        audioPlayer?.stop()
        cleanupAudioPlayer()
        isSpeaking = false
    }

    private func cleanupAudioPlayer() {
        audioPlayer = nil
        if let file = currentAudioTmpFile {
            try? FileManager.default.removeItem(at: file)
            currentAudioTmpFile = nil
        }
    }

    /// Detect audio format from magic bytes for correct temp file extension.
    private static func audioFileExtension(for data: Data) -> String {
        guard data.count >= 4 else { return "mp3" }
        let header = [UInt8](data.prefix(4))
        if header[0] == 0x52, header[1] == 0x49, header[2] == 0x46, header[3] == 0x46 { return "wav" }  // RIFF
        if header[0] == 0x4F, header[1] == 0x67, header[2] == 0x67, header[3] == 0x53 { return "ogg" }  // OggS
        if header[0] == 0x66, header[1] == 0x4C, header[2] == 0x61, header[3] == 0x43 { return "flac" } // fLaC
        return "mp3"
    }

    /// Convert PikoChan's mood enum to a natural emotion prompt for TTS models.
    private static func moodToEmotionPrompt(_ mood: Mood) -> String {
        switch mood {
        case .neutral:     "Calm and conversational."
        case .playful:     "Playful and energetic."
        case .irritated:   "Slightly annoyed and impatient."
        case .proud:       "Proud and confident."
        case .concerned:   "Concerned and worried."
        case .snarky:      "Sarcastic and witty."
        case .encouraging: "Warm, encouraging, and supportive."
        }
    }

    private func resetMoodDecay() {
        moodDecayTask?.cancel()
        moodDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300)) // 5 minutes
            guard !Task.isCancelled, let self else { return }
            self.currentMood = .neutral
        }
    }

    func openSettingsToAIModel() {
        SettingsWindowController.shared.show(tab: "AI Model")
    }

    private func setError(message: String, suggestion: String? = nil, opensSettings: Bool = false) {
        lastResponseError = message
        lastResponseSuggestion = suggestion
        lastErrorOpensSettings = opensSettings

        // Flash concerned mood on error, revert after 2 seconds.
        let previousMood = currentMood
        currentMood = .concerned
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.currentMood == .concerned {
                self.currentMood = previousMood
            }
        }
    }

    private func setError(fromLocalizedDescription desc: String) {
        // Try to match against known PikoBrainError patterns.
        let suggestion: String?
        let opensSettings: Bool
        switch desc {
        case let s where s.contains("Can't reach local model"):
            suggestion = "Start Ollama or switch to cloud in Settings"
            opensSettings = true
        case let s where s.contains("API key was rejected"):
            suggestion = "Check your key in Settings → AI Model"
            opensSettings = true
        case let s where s.contains("No API key configured"):
            suggestion = "Add your key in Settings → AI Model"
            opensSettings = true
        case let s where s.contains("Too many requests"):
            suggestion = "Wait a moment and try again"
            opensSettings = false
        case let s where s.contains("Model returned nothing"):
            suggestion = "Try a different prompt or model"
            opensSettings = false
        case let s where s.contains("Apple Intelligence is not available"):
            suggestion = "Requires macOS 26+ with Apple Intelligence enabled"
            opensSettings = true
        default:
            suggestion = "Check your connection and try again"
            opensSettings = false
        }
        setError(message: desc, suggestion: suggestion, opensSettings: opensSettings)
    }

    // MARK: - Mouse Monitors

    private func installMonitors() {
        // ── Mouse movement (hover detection only for hidden/hovered states) ──
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }

        // ── Click ──
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, !self.suppressNextGlobalClick else { return }
            let mouse = NSEvent.mouseLocation
            switch self.state {
            case .hidden, .hovered:
                // Click in hover zone → reopen to last active state.
                if NSMouseInRect(mouse, self.hoverZone, false) {
                    self.reopen()
                }
            case .musicCompact, .musicHover:
                // Click on compact music → extend.
                if let panel = self.panel, panel.isMouseOverContent(mouse) {
                    self.transition(to: .musicExtended)
                }
            case .musicExtended:
                // Click outside → collapse to compact. Clicks on content are handled by buttons.
                if let panel = self.panel, !panel.isMouseOverContent(mouse) {
                    if self.nowPlaying?.isPlaying == true {
                        self.transition(to: .musicCompact)
                    } else {
                        self.transition(to: .hidden)
                    }
                }
            case .setup:
                // Don't dismiss setup on outside click.
                break
            case .expanded, .typing, .listening:
                // Click outside visible content → hide (but preserve state).
                if let panel = self.panel, !panel.isMouseOverContent(mouse) {
                    if self.nowPlaying?.isPlaying == true {
                        self.transition(to: .musicCompact)
                    } else {
                        self.transition(to: .hidden)
                    }
                }
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            if self.state == .hovered {
                self.reopen()
            } else if self.state == .musicCompact || self.state == .musicHover {
                self.transition(to: .musicExtended)
            } else if self.state == .musicExtended {
                // Mark that a local click is in-flight so the global handler ignores it.
                self.suppressNextGlobalClick = true
                DispatchQueue.main.async { self.suppressNextGlobalClick = false }
            }
            return event
        }

        // ── Right-click (context menu) ──
        globalRightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            if self.shouldShowContextMenu(at: mouse) {
                self.showContextMenu()
            }
        }
        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let mouse = NSEvent.mouseLocation
            if self.shouldShowContextMenu(at: mouse) {
                self.showContextMenu()
                return nil
            }
            return event
        }

        // ── Escape key ──
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            switch self.state {
            case .setup:
                // Don't dismiss setup on escape.
                return nil
            case .musicExtended:
                if self.nowPlaying?.isPlaying == true {
                    self.transition(to: .musicCompact)
                } else {
                    self.transition(to: .hidden)
                }
                return nil
            case .musicCompact, .musicHover:
                self.transition(to: .hidden)
                return nil
            case .typing:
                self.transition(to: .expanded)
                return nil
            case .listening:
                // Stop recording without transcribing on escape.
                if self.isRecording {
                    self.isRecording = false
                    _ = self.voiceCapture?.stopCapture()
                }
                self.transition(to: .expanded)
                return nil
            case .expanded, .hovered:
                if self.nowPlaying?.isPlaying == true {
                    self.transition(to: .musicCompact)
                } else {
                    self.transition(to: .hidden)
                }
                return nil
            default:
                return event
            }
        }

        // Poll timer fallback — mouseMoved global monitors are unreliable
        // for panels with ignoresMouseEvents, so we poll at 50ms as backup.
        startHoverPollingFallback()
    }

    private func removeMonitors() {
        [globalMouseMonitor, localMouseMonitor, globalClickMonitor, localClickMonitor,
         globalRightClickMonitor, localRightClickMonitor, localKeyMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
        globalRightClickMonitor = nil
        localRightClickMonitor = nil
        localKeyMonitor = nil
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
    }

    private func startHoverPollingFallback() {
        hoverPollTimer?.invalidate()
        hoverPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.handleMouseMoved()
        }
        RunLoop.main.add(hoverPollTimer!, forMode: .common)
    }

    private func handleMouseMoved() {
        let mouse = NSEvent.mouseLocation
        let settings = PikoSettings.shared

        switch state {
        case .hidden:
            guard settings.openOnHover else { return }
            if NSMouseInRect(mouse, hoverZone, false) {
                if hoverDebounceTask == nil {
                    hoverDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        guard !Task.isCancelled else { return }
                        let current = NSEvent.mouseLocation
                        if NSMouseInRect(current, self.hoverZone, false) {
                            if settings.alwaysExpandOnHover {
                                self.transition(to: .expanded)
                            } else {
                                self.transition(to: .hovered)
                            }
                        }
                        self.hoverDebounceTask = nil
                    }
                }
            } else {
                hoverDebounceTask?.cancel()
                hoverDebounceTask = nil
            }

        case .hovered:
            // Hovered is uncommitted — mouse leaving dismisses it.
            let expandedZone = hoverZone.insetBy(dx: -20, dy: -20)
            if !NSMouseInRect(mouse, expandedZone, false) {
                transition(to: .hidden)
            }
            // Pass through clicks outside the visible notch content.
            if let panel {
                let overContent = panel.isMouseOverContent(mouse)
                if panel.ignoresMouseEvents == overContent {
                    panel.ignoresMouseEvents = !overContent
                }
            }

        case .musicCompact, .musicHover:
            // Generous hit zone prevents hover flicker at edges.
            if let panel {
                let rect = panel.visibleContentScreenRect.insetBy(dx: -20, dy: -20)
                let over = rect.contains(mouse)
                if panel.ignoresMouseEvents == over {
                    panel.ignoresMouseEvents = !over
                }
            }

        case .musicExtended:
            // Dynamically toggle mouse passthrough.
            if let panel {
                let overContent = panel.isMouseOverContent(mouse)
                if panel.ignoresMouseEvents == overContent {
                    panel.ignoresMouseEvents = !overContent
                }
            }

        case .typing, .listening, .setup:
            // Never toggle ignoresMouseEvents during typing/listening/setup — it steals
            // focus from the text field or mic.
            break

        case .expanded:
            // Dynamically toggle mouse passthrough so areas outside the content
            // don't block other windows.
            if let panel {
                let overContent = panel.isMouseOverContent(mouse)
                if panel.ignoresMouseEvents == overContent {
                    panel.ignoresMouseEvents = !overContent
                }
            }
        }
    }

    // MARK: - Mood Assets

    private func loadMoodImages() {
        let fm = FileManager.default
        let exts = Set(["png", "jpg", "jpeg", "webp"])
        moodImages.removeAll()

        guard let baseURL = Bundle.main.resourceURL else { return }

        for mood in Mood.allCases {
            let moodFolder = baseURL.appendingPathComponent("Moods").appendingPathComponent(mood.rawValue)
            let folderEntries = (try? fm.contentsOfDirectory(at: moodFolder, includingPropertiesForKeys: nil)) ?? []
            let folderImage = folderEntries
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                .first { exts.contains($0.pathExtension.lowercased()) }

            if let folderImage, let image = NSImage(contentsOf: folderImage) {
                moodImages[mood] = image
                continue
            }

            // Fallback when resources are flattened in app bundle.
            let rootEntries = (try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)) ?? []
            let keywords = Self.moodResourceKeywords(for: mood)
            if let flattened = rootEntries.first(where: { url in
                let ext = url.pathExtension.lowercased()
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                return exts.contains(ext) && keywords.contains(where: { stem.contains($0) })
            }),
               let image = NSImage(contentsOf: flattened) {
                moodImages[mood] = image
            }
        }
    }

    private static func moodResourceKeywords(for mood: Mood) -> [String] {
        switch mood {
        case .neutral: return ["neutral"]
        case .playful: return ["playful"]
        case .irritated: return ["irritated", "irritate"]
        case .proud: return ["proud"]
        case .concerned: return ["concerned", "concern"]
        case .snarky: return ["snarky"]
        case .encouraging: return ["encouraging", "encourage"]
        }
    }

    private static func parseMood(from rawText: String) -> Mood? {
        let normalized = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch normalized {
        case "neutral": return .neutral
        case "playful": return .playful
        case "irritated": return .irritated
        case "proud": return .proud
        case "concerned": return .concerned
        case "snarky": return .snarky
        case "encouraging": return .encouraging
        default: return nil
        }
    }

    // MARK: - Context Menu

    private func shouldShowContextMenu(at screenPoint: NSPoint) -> Bool {
        if NSMouseInRect(screenPoint, hoverZone, false) { return true }
        if state != .hidden, let panel, panel.isMouseOverContent(screenPoint) { return true }
        return false
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Open Settings", action: #selector(ContextMenuTarget.openSettings), keyEquivalent: ",")
        settingsItem.target = menuTarget

        let quitItem = NSMenuItem(title: "Quit PikoChan", action: #selector(ContextMenuTarget.quitApp), keyEquivalent: "q")
        quitItem.target = menuTarget

        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        guard let panel, let contentView = panel.contentView else { return }

        // Temporarily allow mouse events so the popup menu can interact.
        panel.ignoresMouseEvents = false
        panel.makeKey()

        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = contentView.convert(windowPoint, from: nil)

        // popUp is synchronous — blocks until the menu is dismissed.
        menu.popUp(positioning: nil, at: viewPoint, in: contentView)

        // Restore to match current state (menu actions like "Open Settings"
        // may have triggered a state transition while the menu was open).
        let shouldIgnore = (state == .hidden)
        panel.ignoresMouseEvents = shouldIgnore
    }

    // MARK: - Screen Change Observation

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let screen = NSScreen.main else { return }
            self.handleScreenChange(screen: screen)
        }
    }

    private func handleScreenChange(screen: NSScreen) {
        let wasSetup = state == .setup
        transition(to: .hidden)
        setupPanel(on: screen)
        if wasSetup { transition(to: .setup) }
    }

    private func observeSettingsWindow() {
        NotificationCenter.default.addObserver(
            forName: SettingsWindowController.willShowNotification,
            object: nil,
            queue: nil  // Synchronous — must fire before the window is created.
        ) { [weak self] _ in
            self?.hideUnlessSetup()
        }
    }

    private func hideUnlessSetup() {
        guard state != .setup else { return }
        transition(to: .hidden)
    }

    private func observeRerunSetup() {
        NotificationCenter.default.addObserver(
            forName: .pikoRerunSetup,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startSetupWizard()
        }
    }

    private func observeConfigSave() {
        NotificationCenter.default.addObserver(
            forName: .pikoConfigDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.brain.reloadConfig()
        }
    }

    private func observeGeometrySettings() {
        NotificationCenter.default.addObserver(
            forName: PikoSettings.geometryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let screen = NSScreen.main else { return }
            self.setupPanel(on: screen)
        }
    }
}

// MARK: - Context Menu Target

/// Tiny @objc helper — NSMenu actions require a selector target.
@objc private final class ContextMenuTarget: NSObject {
    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pikoRerunSetup = Notification.Name("pikoRerunSetup")
    static let pikoConfigDidSave = Notification.Name("pikoConfigDidSave")
}
