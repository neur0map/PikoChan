import AppKit
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
        setupPanel(on: screen)
        installMonitors()
        observeScreenChanges()
        observeSettingsWindow()
        observeGeometrySettings()
        observeRerunSetup()

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
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
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
        case .expanded, .typing, .listening, .setup:
            activeContentWidth
        }
    }

    private var contentHeight: CGFloat {
        let pad = PikoSettings.shared.contentPadding
        return switch state {
        case .hidden:    notchSize.height
        case .hovered:   notchSize.height + pad + 12
        case .expanded, .typing, .listening:
            activeContentHeight
        case .setup:
            setupContentHeight
        }
    }

    var setupContentHeight: CGFloat {
        let pad = PikoSettings.shared.contentPadding
        return notchSize.height + pad + 320
    }

    var activeContentWidth: CGFloat { 290 }

    var showsResponseBubble: Bool {
        isResponding || !lastResponseText.isEmpty || lastResponseError != nil || showsChatHistory
    }

    private var responseBlockHeight: CGFloat {
        guard showsResponseBubble else { return 0 }
        return isResponseExpanded ? 230 : 86
    }

    var activeContentHeight: CGFloat {
        let pad = PikoSettings.shared.contentPadding
        let sprite = PikoSettings.shared.spriteSize
        let expandedHeight = notchSize.height + pad + sprite + 12 + 36 + 16 + responseBlockHeight
        let typingHeight = notchSize.height + pad + sprite + 8 + 34 + 12 + responseBlockHeight
        let listeningHeight = notchSize.height + pad + sprite + 6 + 28 + 6 + 28 + 12 + responseBlockHeight
        return max(expandedHeight, max(typingHeight, listeningHeight))
    }

    // MARK: - State Transitions

    func transition(to newState: NotchState) {
        guard newState != state else { return }

        // Clean up setup wizard when leaving .setup state.
        if state == .setup && newState != .setup {
            setupManager = nil
        }

        // Remember what the user was doing before hiding (but not .setup).
        if newState == .hidden && state != .hovered && state != .setup {
            lastActiveState = state
        }

        let animation: Animation = switch newState {
        case .hidden:
            .smooth(duration: 0.25)
        case .hovered:
            .spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.15)
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

        case .expanded, .listening:
            panel?.ignoresMouseEvents = false
            panel?.styleMask.insert(.nonactivatingPanel)
            panel?.syncActivationState()
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

    func cancelResponse() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
        isResponding = false
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
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            switch self.state {
            case .hidden, .hovered:
                // Click in hover zone → reopen to last active state.
                if NSMouseInRect(mouse, self.hoverZone, false) {
                    self.reopen()
                }
            case .setup:
                // Don't dismiss setup on outside click.
                break
            case .expanded, .typing, .listening:
                // Click outside visible content → hide (but preserve state).
                if let panel = self.panel, !panel.isMouseOverContent(mouse) {
                    self.transition(to: .hidden)
                }
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            if self.state == .hovered {
                self.reopen()
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
            case .typing, .listening:
                self.transition(to: .expanded)
                return nil
            case .expanded, .hovered:
                self.transition(to: .hidden)
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

        case .typing, .setup:
            // Never toggle ignoresMouseEvents during typing/setup — it steals
            // focus from the text field.
            break

        case .expanded, .listening:
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
        let shouldIgnore = (state == .hidden || state == .hovered)
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
}
