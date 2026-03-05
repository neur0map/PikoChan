import AppKit

extension NSScreen {

    // MARK: - Notch Detection

    /// Whether this screen has a hardware notch (MacBook Pro 2021+).
    var hasNotch: Bool {
        auxiliaryTopLeftArea?.width != nil && auxiliaryTopRightArea?.width != nil
    }

    /// The hardware notch size, or nil on notch-less displays.
    var notchSize: NSSize? {
        guard
            let leftWidth = auxiliaryTopLeftArea?.width,
            let rightWidth = auxiliaryTopRightArea?.width
        else { return nil }

        let notchHeight = safeAreaInsets.top
        let notchWidth = frame.width - leftWidth - rightWidth
        return NSSize(width: notchWidth, height: notchHeight)
    }

    /// The hardware notch frame in screen coordinates, or nil.
    var notchFrame: NSRect? {
        guard let size = notchSize else { return nil }
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Fallbacks

    /// Menu bar height (distance from screen top to visible area top).
    var menubarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }

    /// Returns the notch frame if available, otherwise synthesizes one from the menu bar.
    /// The fallback uses 220pt width centered at screen top — a reasonable default
    /// that looks good on non-notch displays.
    var notchFrameOrMenubar: NSRect {
        if let notchFrame { return notchFrame }
        let w: CGFloat = 220
        let h: CGFloat = menubarHeight
        return NSRect(
            x: frame.midX - w / 2,
            y: frame.maxY - h,
            width: w,
            height: h
        )
    }

    // MARK: - Helpers

    /// The screen that currently contains the mouse cursor.
    static var screenWithMouse: NSScreen? {
        let loc = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(loc, $0.frame, false) }
    }
}
