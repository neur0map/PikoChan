import SwiftUI

/// Root SwiftUI view hosted inside the PikoPanel.
/// Lays out content relative to the notch and drives all state visuals.
struct NotchContentView: View {
    @Bindable var manager: NotchManager
    @State private var isHoveringNotch = false
    private var settings: PikoSettings { PikoSettings.shared }

    // MARK: - Computed Geometry

    private var topRadius: CGFloat {
        switch manager.state {
        case .hidden:    6
        case .hovered:   8
        case .musicCompact, .musicHover: 0
        case .musicExtended: 15
        case .expanded, .typing, .listening, .setup: 15
        }
    }

    private var bottomRadius: CGFloat {
        switch manager.state {
        case .hidden:    10
        case .hovered:   12
        case .musicCompact, .musicHover: 12
        case .musicExtended: 24
        case .expanded, .typing, .listening, .setup: 24
        }
    }

    private var contentWidth: CGFloat {
        switch manager.state {
        case .hidden:    manager.notchSize.width
        case .hovered:   manager.notchSize.width
        case .musicCompact, .musicHover:
            manager.musicCompactWidth
        case .musicExtended:
            manager.musicExtendedWidth
        case .expanded, .typing, .listening, .setup:
            manager.activeContentWidth
        }
    }

    private var contentHeight: CGFloat {
        let pad = settings.contentPadding
        return switch manager.state {
        case .hidden:    manager.notchSize.height
        case .hovered:   manager.notchSize.height + pad + 12
        case .musicCompact, .musicHover:
            manager.musicCompactHeight
        case .musicExtended:
            manager.musicExtendedHeight
        case .expanded, .typing, .listening:
            manager.activeContentHeight
        case .setup:
            manager.setupContentHeight
        }
    }

    /// Animate compact size changes when hovering album art.
    private var compactAnimation: Animation {
        .spring(response: 0.3, dampingFraction: 0.8)
    }

    private var shadowRadius: CGFloat {
        switch manager.state {
        case .hidden:   0
        case .hovered:  10
        default:        isHoveringNotch ? 24 : 16
        }
    }

    private var shadowOpacity: Double {
        switch manager.state {
        case .hidden:   0.0
        case .hovered:  0.05
        default:        isHoveringNotch ? 0.25 : 0.15
        }
    }

    private var showsResponseBubble: Bool { manager.showsResponseBubble }
    private var hasActions: Bool { !manager.actionHandler.actions.isEmpty }

    private var actionBlockHeight: CGFloat {
        let actions = manager.actionHandler.actions
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
        guard showsResponseBubble || hasActions else { return 0 }
        let base: CGFloat = showsResponseBubble ? (manager.isResponseExpanded ? 230 : 86) : 0
        return base + actionBlockHeight
    }

    private var expandedNaturalHeight: CGFloat {
        let top = manager.notchSize.height + settings.contentPadding
        let body = settings.spriteSize + 12 + 36 + 16 + responseBlockHeight
        return top + body
    }

    private var typingNaturalHeight: CGFloat {
        let top = manager.notchSize.height + settings.contentPadding
        let body = settings.spriteSize + 8 + 34 + 12 + responseBlockHeight
        return top + body
    }

    private var listeningNaturalHeight: CGFloat {
        let top = manager.notchSize.height + settings.contentPadding
        let body = settings.spriteSize + 6 + 28 + 2 + 44 + 12 + responseBlockHeight
        return top + body
    }

    private func activeVerticalOffset(for state: NotchState) -> CGFloat {
        let natural: CGFloat = switch state {
        case .expanded: expandedNaturalHeight
        case .typing: typingNaturalHeight
        case .listening: listeningNaturalHeight
        default: manager.activeContentHeight
        }
        return max(0, (manager.activeContentHeight - natural) / 2)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            notchBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - Notch Body

    private var notchBody: some View {
        ZStack(alignment: .top) {
            // ── Background ──
            // Music states MUST be pitch black to blend with the hardware notch.
            if settings.backgroundStyle == .translucent && !manager.state.isMusic {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            } else {
                Color.black
            }

            // ── Music Compact (with hover for track name) ──
            if (manager.state == .musicCompact || manager.state == .musicHover), let np = manager.nowPlaying {
                MusicCompactView(nowPlaying: np, manager: manager)
                    .padding(.top, manager.notchSize.height - 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            manager.isHoveringMusicArt = hovering
                        }
                    }
                    .transition(.opacity)
            }

            // ── Music Extended ──
            if manager.state == .musicExtended, let np = manager.nowPlaying {
                MusicExtendedView(
                    nowPlaying: np,
                    spriteImage: manager.spriteImage,
                    onSpriteTapped: { manager.switchToAssistant() }
                )
                .padding(.top, manager.notchSize.height + settings.contentPadding)
                .transition(.blurReplace(.downUp))
            }

            // ── Foreground Content ──
            if manager.state == .expanded || manager.state == .typing || manager.state == .listening {
                VStack(spacing: 0) {
                    // Mini music strip when music is playing during assistant mode.
                    if let np = manager.nowPlaying, np.isPlaying, np.hasTrack {
                        MusicMiniStripView(nowPlaying: np) {
                            manager.switchToMusicExtended()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .transition(.blurReplace(.downUp))
                    }

                    manager.spriteImage
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: settings.spriteSize)

                    if manager.state == .expanded {
                        ExpandedView(
                            onTextTapped: { manager.transition(to: .typing) },
                            onMicTapped: { manager.transition(to: .listening) }
                        )
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.blurReplace(.downUp))
                    }

                    if manager.state == .typing {
                        TypingView(manager: manager)
                            .padding(.top, 8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .transition(.blurReplace(.downUp))
                    }

                    if manager.state == .listening {
                        ListeningView(manager: manager)
                        .padding(.top, 6)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.blurReplace(.downUp))
                    }

                    if showsResponseBubble {
                        responseBubble
                            .padding(.top, 8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, hasActions ? 2 : 6)
                    }

                    actionCards
                }
                .padding(.top, manager.notchSize.height + settings.contentPadding + activeVerticalOffset(for: manager.state))
            }

            // ── Setup Wizard ──
            if manager.state == .setup, let setupManager = manager.setupManager {
                SetupView(manager: manager, setup: setupManager)
                    .padding(.top, manager.notchSize.height + settings.contentPadding)
                    .transition(.blurReplace(.downUp))
            }

            // ── Hover peek indicator ──
            if manager.state == .hovered {
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(.white.opacity(0.4))
                        .frame(width: 40, height: 4)
                        .padding(.bottom, 4)
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        // Fixed frame — never animated on content changes to avoid
        // constraint loops in NSHostingView (FB16484811-adjacent).
        // Exception: compact music hover animates size smoothly.
        .frame(width: contentWidth, height: contentHeight)
        .clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: 10)
        .animation(.smooth(duration: 0.3), value: isHoveringNotch)
        .animation(
            (manager.state == .musicCompact || manager.state == .musicHover) ? compactAnimation : nil,
            value: manager.isHoveringMusicArt
        )
        .onHover { hovering in
            isHoveringNotch = hovering
            if hovering && manager.state == .hidden {
                manager.transition(to: .hovered)
            } else if !hovering && manager.state == .hovered {
                manager.transition(to: .hidden)
            }
        }
    }

    // MARK: - Response Bubble

    private var responseBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if manager.isResponding {
                ThinkingDotsView()
            } else if manager.showsChatHistory {
                ChatHistoryView(turns: manager.recentHistory)
            } else if let err = manager.lastResponseError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)

                if let suggestion = manager.lastResponseSuggestion {
                    if manager.lastErrorOpensSettings {
                        Button {
                            manager.openSettingsToAIModel()
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .underline()
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(suggestion)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            } else if manager.isResponseExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(manager.lastResponseText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: 180)
            } else {
                Text(manager.lastResponseText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)

                if manager.lastResponseText.count > 200 {
                    Text("Tap to expand")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fixed height prevents content-driven relayout loops.
        .frame(height: (manager.isResponseExpanded || manager.showsChatHistory) ? 200 : 62)
        .clipped()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .overlay(alignment: .topLeading) {
            if !manager.isResponding && (!manager.lastResponseText.isEmpty || !manager.recentHistory.isEmpty) {
                Button {
                    manager.showsChatHistory.toggle()
                    if manager.showsChatHistory {
                        manager.isResponseExpanded = true
                    }
                    manager.updateVisibleContentRect()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(manager.showsChatHistory ? 0.7 : 0.3))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !manager.isResponding && !manager.showsChatHistory && manager.lastResponseError == nil && !manager.lastResponseText.isEmpty {
                CopyButton(text: manager.lastResponseText)
                    .padding(6)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(manager.activeProviderLabel)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !manager.showsChatHistory && manager.lastResponseError == nil && !manager.lastResponseText.isEmpty && !manager.isResponding {
                manager.isResponseExpanded.toggle()
                manager.updateVisibleContentRect()
            }
        }
    }

    // MARK: - Action Cards

    @ViewBuilder
    private var actionCards: some View {
        if !manager.actionHandler.actions.isEmpty {
            VStack(spacing: 4) {
                ForEach(manager.actionHandler.actions) { action in
                    ActionCardView(action: action, onRun: {
                        Task {
                            await manager.executeAndRequery(action)
                        }
                    }, onCancel: {
                        manager.actionHandler.cancel(action)
                    })
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Chat History View

private struct ChatHistoryView: View {
    let turns: [ChatTurn]

    var body: some View {
        if turns.isEmpty {
            Text("No messages yet")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                            // User bubble — right-aligned
                            Text(turn.user)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(3)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.cyan.opacity(0.2))
                                )
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            // Assistant bubble — left-aligned
                            Text(turn.assistant)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.white.opacity(0.1))
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(height: 180)
                .onAppear {
                    if !turns.isEmpty {
                        proxy.scrollTo(turns.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Thinking Dots Animation

/// Uses a phase-based animation instead of a Timer to avoid layout-loop
/// issues in NSHostingView. The phaseAnimator drives opacity changes
/// without triggering constraint recalculations.
private struct ThinkingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? dotOpacity(for: i) : 0.3)
            }
        }
        .onAppear { animating = true }
        .animation(
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double.random(in: 0...0.3)),
            value: animating
        )
    }

    private func dotOpacity(for index: Int) -> Double {
        [0.9, 0.5, 0.2][index % 3]
    }
}

// MARK: - Copy Button

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(copied ? 0.7 : 0.3))
        }
        .buttonStyle(.plain)
    }
}
