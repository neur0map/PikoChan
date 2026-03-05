import AppKit
import SwiftUI
import Observation

/// Owns the floating panel, tracks mouse proximity, and drives state transitions.
@Observable
final class NotchManager {

    // MARK: - State

    var state: NotchState = .hidden
    var notchSize: CGSize = .zero
    var menubarHeight: CGFloat = 0
    var inputText: String = ""

    /// Remembers what the user was doing before hiding, so reopening resumes.
    private var lastActiveState: NotchState = .expanded

    // MARK: - Window

    private(set) var panel: PikoPanel?
    private var panelSize: CGSize = .zero

    // MARK: - Monitors

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalRightClickMonitor: Any?
    private var localRightClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var hoverDebounceTask: Task<Void, Never>?
    private let menuTarget = ContextMenuTarget()

    // MARK: - Geometry

    private var hoverZone: NSRect = .zero

    // MARK: - Setup

    func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        setupPanel(on: screen)
        installMonitors()
        observeScreenChanges()
        observeSettingsWindow()
        observeGeometrySettings()
    }

    func teardown() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Panel Setup

    private func setupPanel(on screen: NSScreen) {
        panel?.orderOut(nil)

        let settings = PikoSettings.shared
        let notchRect = screen.notchFrameOrMenubar
        notchSize = CGSize(
            width: notchRect.size.width + settings.notchWidthOffset,
            height: notchRect.size.height + settings.notchHeightOffset
        )
        menubarHeight = screen.menubarHeight

        let pw: CGFloat = max(380, notchSize.width + 200)
        let ph: CGFloat = 380
        panelSize = CGSize(width: pw, height: ph)

        let origin = NSPoint(
            x: screen.frame.midX - pw / 2,
            y: screen.frame.maxY - ph
        )

        let p = PikoPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: pw, height: ph)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostView = NSHostingView(rootView: NotchContentView(manager: self))
        hostView.frame = NSRect(origin: .zero, size: NSSize(width: pw, height: ph))
        p.contentView = hostView
        p.ignoresMouseEvents = true
        p.orderFrontRegardless()

        panel = p
        updateVisibleContentRect()

        let hzPad = settings.hoverZonePadding
        hoverZone = NSRect(
            x: notchRect.origin.x - 10,
            y: notchRect.origin.y - hzPad,
            width: notchRect.width + 20,
            height: notchRect.height + hzPad
        )
    }

    // MARK: - Visible Content Rect

    func updateVisibleContentRect() {
        guard let panel else { return }
        let cw = contentWidth
        let ch = contentHeight
        let screenRect = NSRect(
            x: panel.frame.midX - cw / 2,
            y: panel.frame.maxY - ch,
            width: cw,
            height: ch
        )
        panel.visibleContentScreenRect = screenRect
    }

    private var contentWidth: CGFloat {
        switch state {
        case .hidden:    notchSize.width
        case .hovered:   notchSize.width
        case .expanded:  280
        case .typing:    290
        case .listening: 280
        }
    }

    private var contentHeight: CGFloat {
        let pad = PikoSettings.shared.contentPadding
        let sprite = PikoSettings.shared.spriteSize
        return switch state {
        case .hidden:    notchSize.height
        case .hovered:   notchSize.height + pad
        case .expanded:  notchSize.height + pad + sprite + 12 + 36 + 16
        case .typing:    notchSize.height + pad + 90 + 8 + 34 + 16
        case .listening: notchSize.height + pad + 90 + 6 + 28 + 6 + 28 + 12
        }
    }

    // MARK: - State Transitions

    func transition(to newState: NotchState) {
        guard newState != state else { return }

        // Remember what the user was doing before hiding.
        if newState == .hidden && state != .hovered {
            lastActiveState = state
        }

        let animation: Animation = switch newState {
        case .hidden:
            .smooth(duration: 0.25)
        case .hovered:
            .spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.15)
        case .expanded:
            .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.2)
        case .typing:
            .spring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.15)
        case .listening:
            .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0.2)
        }

        withAnimation(animation) {
            state = newState
        }

        if newState == .hidden || newState == .hovered {
            panel?.ignoresMouseEvents = true
            panel?.styleMask.insert(.nonactivatingPanel)
            panel?.syncActivationState()
        } else {
            panel?.ignoresMouseEvents = false

            if newState == .typing {
                // Remove .nonactivatingPanel so macOS connects the text input
                // service chain, then sync the WindowServer tag (FB16484811).
                panel?.styleMask.remove(.nonactivatingPanel)
                panel?.syncActivationState()
                NSApp.activate()
            } else {
                panel?.styleMask.insert(.nonactivatingPanel)
                panel?.syncActivationState()
            }

            panel?.makeKey()
        }

        updateVisibleContentRect()
    }

    /// Reopen to whatever the user was last doing.
    func reopen() {
        transition(to: lastActiveState)
    }

    // MARK: - Mouse Monitors

    private func installMonitors() {
        // ── Mouse movement (hover detection only for hidden/hovered states) ──
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }

        // ── Click ──
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            switch self.state {
            case .hidden, .hovered:
                // Click in hover zone → reopen to last active state.
                if NSMouseInRect(mouse, self.hoverZone, false) {
                    self.reopen()
                }
            case .expanded, .typing, .listening:
                // Click outside visible content → hide (but preserve state).
                if let panel = self.panel, !panel.isMouseOverContent(mouse) {
                    self.transition(to: .hidden)
                }
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            if self.state == .hovered {
                self.reopen()
            }
            return event
        }

        // ── Right-click (context menu) ──
        globalRightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            if self.shouldShowContextMenu(at: mouse) {
                self.showContextMenu()
            }
        }
        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let mouse = NSEvent.mouseLocation
            if self.shouldShowContextMenu(at: mouse) {
                self.showContextMenu()
                return nil
            }
            return event
        }

        // ── Escape key ──
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            switch self.state {
            case .typing, .listening:
                self.transition(to: .expanded)
                return nil
            case .expanded, .hovered:
                self.transition(to: .hidden)
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitors() {
        [globalMouseMonitor, localMouseMonitor, globalClickMonitor, localClickMonitor,
         globalRightClickMonitor, localRightClickMonitor, localKeyMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
        globalRightClickMonitor = nil
        localRightClickMonitor = nil
        localKeyMonitor = nil
    }

    private func handleMouseMoved() {
        let mouse = NSEvent.mouseLocation
        let settings = PikoSettings.shared

        switch state {
        case .hidden:
            guard settings.openOnHover else { return }
            if NSMouseInRect(mouse, hoverZone, false) {
                if hoverDebounceTask == nil {
                    hoverDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        guard !Task.isCancelled else { return }
                        let current = NSEvent.mouseLocation
                        if NSMouseInRect(current, self.hoverZone, false) {
                            if settings.alwaysExpandOnHover {
                                self.transition(to: .expanded)
                            } else {
                                self.transition(to: .hovered)
                            }
                        }
                        self.hoverDebounceTask = nil
                    }
                }
            } else {
                hoverDebounceTask?.cancel()
                hoverDebounceTask = nil
            }

        case .hovered:
            // Hovered is uncommitted — mouse leaving dismisses it.
            let expandedZone = hoverZone.insetBy(dx: -20, dy: -20)
            if !NSMouseInRect(mouse, expandedZone, false) {
                transition(to: .hidden)
            }

        case .expanded, .typing, .listening:
            // Dynamically toggle mouse passthrough so areas outside the content
            // don't block other windows.
            if let panel {
                let overContent = panel.isMouseOverContent(mouse)
                if panel.ignoresMouseEvents == overContent {
                    panel.ignoresMouseEvents = !overContent
                }
            }
        }
    }

    // MARK: - Context Menu

    private func shouldShowContextMenu(at screenPoint: NSPoint) -> Bool {
        if NSMouseInRect(screenPoint, hoverZone, false) { return true }
        if state != .hidden, let panel, panel.isMouseOverContent(screenPoint) { return true }
        return false
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Open Settings", action: #selector(ContextMenuTarget.openSettings), keyEquivalent: ",")
        settingsItem.target = menuTarget

        let quitItem = NSMenuItem(title: "Quit PikoChan", action: #selector(ContextMenuTarget.quitApp), keyEquivalent: "q")
        quitItem.target = menuTarget

        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        guard let panel, let contentView = panel.contentView else { return }

        // Temporarily allow mouse events so the popup menu can interact.
        let wasIgnoring = panel.ignoresMouseEvents
        panel.ignoresMouseEvents = false
        panel.makeKey()

        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = contentView.convert(windowPoint, from: nil)

        // popUp is synchronous — blocks until the menu is dismissed.
        menu.popUp(positioning: nil, at: viewPoint, in: contentView)

        // Restore original state after menu closes.
        panel.ignoresMouseEvents = wasIgnoring
    }

    // MARK: - Screen Change Observation

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let screen = NSScreen.main else { return }
            self.setupPanel(on: screen)
        }
    }

    private func observeSettingsWindow() {
        NotificationCenter.default.addObserver(
            forName: SettingsWindowController.willShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.transition(to: .hidden)
        }
    }

    private func observeGeometrySettings() {
        NotificationCenter.default.addObserver(
            forName: PikoSettings.geometryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let screen = NSScreen.main else { return }
            self.setupPanel(on: screen)
        }
    }
}

// MARK: - Context Menu Target

/// Tiny @objc helper — NSMenu actions require a selector target.
@objc private final class ContextMenuTarget: NSObject {
    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
