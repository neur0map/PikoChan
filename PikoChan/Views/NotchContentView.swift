import SwiftUI

/// Root SwiftUI view hosted inside the PikoPanel.
/// Lays out content relative to the notch and drives all state visuals.
struct NotchContentView: View {
    @Bindable var manager: NotchManager
    private var settings: PikoSettings { PikoSettings.shared }

    // MARK: - Computed Geometry

    private var topRadius: CGFloat {
        switch manager.state {
        case .hidden:    6
        case .hovered:   8
        case .expanded:  15
        case .typing:    15
        case .listening: 15
        }
    }

    private var bottomRadius: CGFloat {
        switch manager.state {
        case .hidden:    10
        case .hovered:   12
        case .expanded:  24
        case .typing:    24
        case .listening: 24
        }
    }

    private var contentWidth: CGFloat {
        switch manager.state {
        case .hidden:    manager.notchSize.width
        case .hovered:   manager.notchSize.width
        case .expanded:  280
        case .typing:    290
        case .listening: 280
        }
    }

    private var contentHeight: CGFloat {
        let pad = settings.contentPadding
        let sprite = settings.spriteSize
        return switch manager.state {
        case .hidden:    manager.notchSize.height
        case .hovered:   manager.notchSize.height + pad
        case .expanded:  manager.notchSize.height + pad + sprite + 12 + 36 + 16
        case .typing:    manager.notchSize.height + pad + 90 + 8 + 34 + 16
        case .listening: manager.notchSize.height + pad + 90 + 6 + 28 + 6 + 28 + 12
        }
    }

    private var shadowOpacity: Double {
        switch manager.state {
        case .hidden:   0.0
        case .hovered:  0.05
        default:        0.15
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            notchBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Notch Body

    private var notchBody: some View {
        ZStack(alignment: .top) {
            // ── Background ──
            if settings.backgroundStyle == .translucent {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            } else {
                Color.black
            }

            // ── Foreground Content ──
            if manager.state == .expanded {
                ExpandedView(
                    onTextTapped: { manager.transition(to: .typing) },
                    onMicTapped: { manager.transition(to: .listening) }
                )
                .padding(.top, manager.notchSize.height + settings.contentPadding)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                    )
                )
            }

            if manager.state == .typing {
                TypingView(manager: manager)
                    .padding(.top, manager.notchSize.height + settings.contentPadding)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: 4))
                        )
                    )
            }

            if manager.state == .listening {
                ListeningView(
                    onStopTapped: { manager.transition(to: .expanded) }
                )
                .padding(.top, manager.notchSize.height + settings.contentPadding)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                    )
                )
            }

            // ── Hover peek indicator ──
            if manager.state == .hovered {
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white.opacity(0.25))
                        .frame(width: 36, height: 3)
                        .padding(.bottom, 2)
                }
                .transition(.opacity.combined(with: .offset(y: -3)))
            }
        }
        .frame(width: contentWidth, height: contentHeight)
        .clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        .shadow(color: .black.opacity(shadowOpacity), radius: 20, y: 10)
    }
}
