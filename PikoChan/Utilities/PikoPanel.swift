import AppKit

/// Custom NSPanel for the notch overlay.
/// Borderless, transparent, floats above other windows, joins all Spaces.
final class PikoPanel: NSPanel {

    /// The rect (in screen coordinates) where visible content lives.
    /// NotchManager updates this on every state change.
    /// Used by the manager to decide if mouse is over content.
    var visibleContentScreenRect: NSRect = .zero

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Activation State Sync

    /// After toggling `.nonactivatingPanel` in the style mask, AppKit and
    /// WindowServer can become desynchronized (FB16484811). This forces
    /// the WindowServer tag to match the current style mask.
    func syncActivationState() {
        let shouldPrevent = styleMask.contains(.nonactivatingPanel)
        let sel = NSSelectorFromString("_setPreventsActivation:")
        if responds(to: sel) {
            perform(sel, with: NSNumber(value: shouldPrevent))
        }
    }

    // MARK: - Custom Field Editor

    /// Pre-configured field editor with all text services disabled.
    /// Providing this upfront prevents macOS from opening ViewBridge
    /// connections to remote input services when editing begins.
    private lazy var minimalFieldEditor: NSTextView = {
        let tv = NSTextView()
        tv.isFieldEditor = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        return tv
    }()

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        minimalFieldEditor
    }

    /// Check if a screen-coordinate point is inside the visible content.
    func isMouseOverContent(_ screenPoint: NSPoint) -> Bool {
        visibleContentScreenRect.insetBy(dx: -8, dy: -8).contains(screenPoint)
    }
}
