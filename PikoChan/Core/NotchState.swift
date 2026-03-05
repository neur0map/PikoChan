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
}
