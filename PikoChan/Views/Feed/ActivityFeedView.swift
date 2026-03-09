import SwiftUI

/// Scrollable activity feed with sprite-left layout.
struct ActivityFeedView: View {
    @Bindable var manager: NotchManager
    let isExpanded: Bool
    var onTextTapped: (() -> Void)?
    var onMicTapped: (() -> Void)?
    var onNewChat: (() -> Void)?

    @State private var isAutoscrollPaused = false
    @State private var newMessageCount = 0
    @State private var previousItemCount = 0

    private var feedHeight: CGFloat {
        isExpanded ? 300 : 120
    }

    /// Items to display: all in expanded, last 3 in compact.
    private var visibleItems: [PikoFeedItem] {
        if isExpanded {
            return manager.feedItems
        }
        return Array(manager.feedItems.suffix(3))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Sprite + mini control buttons
            VStack(spacing: 6) {
                Button {
                    onNewChat?()
                } label: {
                    manager.spriteImage
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("New chat")

                // Mini mode buttons (only in idle/expanded state)
                if manager.state == .expanded {
                    VStack(spacing: 4) {
                        miniButton(icon: "keyboard", action: { onTextTapped?() })
                        miniButton(icon: "waveform", action: { onMicTapped?() })
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, 4)

            // Feed area
            feedContent
        }
        .onChange(of: manager.feedItems.count) { old, new in
            if new > old {
                if isAutoscrollPaused {
                    newMessageCount += (new - old)
                }
                previousItemCount = new
            }
        }
    }

    // MARK: - Mini Button

    private func miniButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(.white.opacity(0.07))
                        .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(visibleItems) { item in
                            FeedItemView(
                                item: item,
                                actionHandler: manager.actionHandler,
                                onApprove: { action in
                                    Task { await manager.executeAndRequery(action) }
                                },
                                onDeny: { action in
                                    manager.actionHandler.cancel(action)
                                },
                                onAllowSession: { action in
                                    manager.actionHandler.sessionAutoApprove = true
                                    Task { await manager.executeAndRequery(action) }
                                }
                            )
                            .id(item.id)
                        }

                        // Streaming row (ephemeral)
                        if manager.isResponding {
                            StreamingFeedRow(text: manager.lastResponseText)
                                .id("streaming")
                        }

                        // Invisible anchor
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: manager.feedItems.count) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: manager.isResponding) { old, new in
                    if new {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // Top fade gradient
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.8), .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 16)
                .allowsHitTesting(false)

                Spacer()
            }

            // Bottom fade gradient
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 16)
                .allowsHitTesting(false)
            }

            // New messages indicator
            if isAutoscrollPaused && newMessageCount > 0 {
                NewMessagesPill(count: newMessageCount) {
                    isAutoscrollPaused = false
                    newMessageCount = 0
                }
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }
        }
        .frame(height: feedHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - New Messages Pill

private struct NewMessagesPill: View {
    let count: Int
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                Text(count == 1 ? "1 new" : "\(count) new")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(red: 0.85, green: 0.47, blue: 0.34))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}
