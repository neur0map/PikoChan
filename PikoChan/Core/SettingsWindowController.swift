import AppKit
import SwiftUI

/// Manages a standalone settings window with native toolbar tabs.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    static let willShowNotification = Notification.Name("PikoSettingsWillShow")

    private var windowController: NSWindowController?

    func show(tab: String? = nil) {
        NotificationCenter.default.post(name: Self.willShowNotification, object: nil)

        if let wc = windowController {
            if let tab, let tabVC = wc.contentViewController as? NSTabViewController {
                if let idx = tabVC.tabViewItems.firstIndex(where: { ($0.identifier as? String) == tab }) {
                    tabVC.selectedTabViewItemIndex = idx
                }
            }
            activateAndShow(wc.window)
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar
        tabVC.title = "PikoChan Settings"

        let tabs: [(String, String, NSView)] = [
            ("Appearance", "paintbrush",                       NSHostingView(rootView: AppearanceTab())),
            ("Soul",       "brain.head.profile",               NSHostingView(rootView: SoulTab())),
            ("AI Model",   "cpu",                              NSHostingView(rootView: AIModelTab())),
            ("Voice",      "waveform.circle",                   NSHostingView(rootView: VoiceTab())),
            ("Skills",     "hammer",                            NSHostingView(rootView: SkillsTab())),
            ("Awareness", "heart.text.square",                 NSHostingView(rootView: AwarenessTab())),
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

        if let tab, let idx = tabVC.tabViewItems.firstIndex(where: { ($0.identifier as? String) == tab }) {
            tabVC.selectedTabViewItemIndex = idx
        }

        let w = NSWindow(contentViewController: tabVC)
        w.title = "PikoChan Settings"
        w.styleMask = [.titled, .closable, .resizable]
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 500, height: 900))
        w.minSize = NSSize(width: 440, height: 600)
        // Float above the notch panel (.screenSaver = 1000).
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        w.center()

        let wc = NSWindowController(window: w)
        wc.showWindow(nil)
        activateAndShow(w)
        windowController = wc
    }

    private func activateAndShow(_ window: NSWindow?) {
        guard let window else { return }
        // Temporarily become a regular app so we can receive key events.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Go back to accessory (no dock icon) when all windows close.
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            _ = self
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
