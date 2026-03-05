import AppKit
import SwiftUI

/// Manages a standalone settings window with native toolbar tabs.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    static let willShowNotification = Notification.Name("PikoSettingsWillShow")

    private var windowController: NSWindowController?

    func show() {
        NotificationCenter.default.post(name: Self.willShowNotification, object: nil)
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)

        if let wc = windowController {
            wc.window?.makeKeyAndOrderFront(nil)
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar  // Toolbar icons across the top — standard macOS prefs look.

        let tabs: [(String, String, NSView)] = [
            ("Appearance", "paintbrush",                       NSHostingView(rootView: AppearanceTab())),
            ("Behavior",   "gearshape",                        NSHostingView(rootView: BehaviorTab())),
            ("Notch",      "rectangle.topthird.inset.filled",  NSHostingView(rootView: NotchTuneTab())),
            ("About",      "info.circle",                      NSHostingView(rootView: AboutTab())),
        ]

        for (title, icon, view) in tabs {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)

            let vc = NSViewController()
            vc.view = view
            item.viewController = vc

            tabVC.addTabViewItem(item)
        }

        let w = NSWindow(contentViewController: tabVC)
        w.title = "PikoChan Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()

        let wc = NSWindowController(window: w)
        wc.showWindow(nil)
        windowController = wc
    }
}
