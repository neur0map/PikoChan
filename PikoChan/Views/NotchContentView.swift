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

    /// Response text with any leftover tags stripped for display.
    private var cleanedResponseText: String {
        StreamingFeedRow.stripTagsForDisplay(
            manager.lastResponseText.replacingOccurrences(of: "**", with: "")
        )
    }

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
        // sprite + gap(10) + inputBar(46) + pad(10) + response
        let body = settings.spriteSize + 10 + 46 + 10 + responseBlockHeight
        return top + body
    }

    private var typingNaturalHeight: CGFloat {
        let top = manager.notchSize.height + settings.contentPadding
        // sprite + gap(8) + typingBar(50) + pad(12) + response
        let body = settings.spriteSize + 8 + 50 + 12 + responseBlockHeight
        return top + body
    }

    private var listeningNaturalHeight: CGFloat {
        let top = manager.notchSize.height + settings.contentPadding
        // sprite + gap(6) + wave(28) + controls(50) + pad(12) + response
        let body = settings.spriteSize + 6 + 28 + 50 + 12 + responseBlockHeight
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
                if manager.hasFeedContent {
                    // Feed layout: sprite-left + feed + controls below.
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

                        // Activity feed with sprite on the left + mini controls.
                        ActivityFeedView(
                            manager: manager,
                            isExpanded: manager.isFeedExpanded,
                            onTextTapped: { manager.transition(to: .typing) },
                            onMicTapped: { manager.transition(to: .listening) },
                            onNewChat: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    manager.clearFeed()
                                    manager.actionHandler.reset()
                                    manager.lastResponseText = ""
                                    manager.lastResponseError = nil
                                    manager.transition(to: .typing)
                                }
                            }
                        )
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                manager.isFeedExpanded.toggle()
                                manager.updateVisibleContentRect()
                            }
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
                    }
                    .padding(.top, manager.notchSize.height + settings.contentPadding)
                } else {
                    // Classic layout: sprite-left + content-right.
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

                        // Sprite — always centered
                        manager.spriteImage
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: settings.spriteSize)

                        // Controls below sprite
                        if manager.state == .expanded {
                            ExpandedView(
                                manager: manager,
                                onTextTapped: { manager.transition(to: .typing) },
                                onVoiceTapped: { manager.transition(to: .listening) }
                            )
                            .padding(.top, 10)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
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

                        // Response text
                        if showsResponseBubble {
                            floatingResponse
                                .padding(.top, 4)
                                .padding(.bottom, hasActions ? 2 : 6)
                        }

                        actionCards
                    }
                    .padding(.top, manager.notchSize.height + settings.contentPadding + activeVerticalOffset(for: manager.state))
                }
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

    // MARK: - Floating Response

    private var floatingResponse: some View {
        VStack(alignment: .leading, spacing: 4) {
            if manager.isResponding {
                ThinkingDotsView()
            } else if manager.showsChatHistory {
                ChatHistoryView(turns: manager.recentHistory)
            } else if let err = manager.lastResponseError {
                Text(err)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(2)

                if let suggestion = manager.lastResponseSuggestion {
                    if manager.lastErrorOpensSettings {
                        Button {
                            manager.openSettingsToAIModel()
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                                .underline()
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(suggestion)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            } else if manager.isResponseExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(cleanedResponseText)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: 180)
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                        Color.white
                        LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                    }
                )
            } else {
                Text(cleanedResponseText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineSpacing(3)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: (manager.isResponseExpanded || manager.showsChatHistory) ? 200 : 62)
        .clipped()
        .padding(.horizontal, 16)
        // Model label
        .overlay(alignment: .bottomTrailing) {
            if !manager.isResponding && !manager.lastResponseText.isEmpty {
                Text(manager.activeProviderLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.trailing, 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !manager.showsChatHistory && manager.lastResponseError == nil && !manager.lastResponseText.isEmpty && !manager.isResponding {
                manager.isResponseExpanded.toggle()
                manager.updateVisibleContentRect()
            }
        }
        // Long-press to copy
        .onLongPressGesture(minimumDuration: 0.5) {
            if !manager.lastResponseText.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(manager.lastResponseText, forType: .string)
                manager.showCopyFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    manager.showCopyFlash = false
                }
            }
        }
        .overlay {
            if manager.showCopyFlash {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .transition(.opacity)
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
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
                    .opacity(animating ? dotOpacity(for: i) : 0.15)
            }
        }
        .onAppear { animating = true }
        .animation(
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double.random(in: 0...0.3)),
            value: animating
        )
    }

    private func dotOpacity(for index: Int) -> Double {
        [0.5, 0.3, 0.15][index % 3]
    }
}

