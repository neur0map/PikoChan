import Foundation

/// The visual states of the PikoChan notch.
enum NotchState: Equatable {
    /// Invisible — sits behind the hardware notch.
    case hidden
    /// Peek — slight expansion below the notch on hover.
    case hovered
    /// Full panel — sprite, action buttons, material background.
    case expanded
    /// Text input — capsule text field inside the expanded panel.
    case typing
    /// Voice listening — sprite with animated waves underneath.
    case listening
    /// First-time setup wizard — step state lives in SetupManager.
    case setup

    // MARK: - Music States

    /// Now Playing compact — pill stretches L+R with album art and audio bars.
    case musicCompact
    /// Now Playing hover — compact + track name fades in.
    case musicHover
    /// Now Playing extended — full mini-player with controls and piko sprite.
    case musicExtended

    /// Whether this is one of the music states.
    var isMusic: Bool {
        switch self {
        case .musicCompact, .musicHover, .musicExtended: true
        default: false
        }
    }

    /// Whether this is an active assistant state (expanded/typing/listening).
    var isAssistant: Bool {
        switch self {
        case .expanded, .typing, .listening: true
        default: false
        }
    }
}
