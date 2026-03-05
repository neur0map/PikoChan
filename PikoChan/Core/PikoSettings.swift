import SwiftUI
import ServiceManagement

/// Central settings store. Backed by UserDefaults, observed by all views.
@Observable
final class PikoSettings {
    static let shared = PikoSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Appearance

    var backgroundStyle: BackgroundStyle {
        didSet { defaults.set(backgroundStyle.rawValue, forKey: "backgroundStyle") }
    }

    var typeButtonColor: Color {
        didSet { saveColor(typeButtonColor, forKey: "typeButtonColor") }
    }

    var talkButtonColor: Color {
        didSet { saveColor(talkButtonColor, forKey: "talkButtonColor") }
    }

    var spriteSize: Double {
        didSet { defaults.set(spriteSize, forKey: "spriteSize") }
    }

    // MARK: - Behavior

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    var openOnHover: Bool {
        didSet { defaults.set(openOnHover, forKey: "openOnHover") }
    }

    var alwaysExpandOnHover: Bool {
        didSet { defaults.set(alwaysExpandOnHover, forKey: "alwaysExpandOnHover") }
    }

    var preventCloseOnMouseLeave: Bool {
        didSet { defaults.set(preventCloseOnMouseLeave, forKey: "preventCloseOnMouseLeave") }
    }

    // MARK: - Notch Fine-Tune

    static let geometryDidChange = Notification.Name("PikoSettingsGeometryDidChange")

    var notchWidthOffset: Double {
        didSet { defaults.set(notchWidthOffset, forKey: "notchWidthOffset"); postGeometryChange() }
    }

    var notchHeightOffset: Double {
        didSet { defaults.set(notchHeightOffset, forKey: "notchHeightOffset"); postGeometryChange() }
    }

    var hoverZonePadding: Double {
        didSet { defaults.set(hoverZonePadding, forKey: "hoverZonePadding"); postGeometryChange() }
    }

    var contentPadding: Double {
        didSet { defaults.set(contentPadding, forKey: "contentPadding"); postGeometryChange() }
    }

    private func postGeometryChange() {
        NotificationCenter.default.post(name: Self.geometryDidChange, object: nil)
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard

        backgroundStyle = BackgroundStyle(rawValue: d.string(forKey: "backgroundStyle") ?? "") ?? .pitchBlack
        typeButtonColor = Self.loadColor(from: d, forKey: "typeButtonColor")
            ?? Color(red: 0.15, green: 0.7, blue: 0.85)
        talkButtonColor = Self.loadColor(from: d, forKey: "talkButtonColor")
            ?? Color(red: 0.85, green: 0.35, blue: 0.55)
        spriteSize = d.object(forKey: "spriteSize") != nil ? d.double(forKey: "spriteSize") : 100

        launchAtLogin = d.bool(forKey: "launchAtLogin")
        openOnHover = d.object(forKey: "openOnHover") != nil ? d.bool(forKey: "openOnHover") : true
        alwaysExpandOnHover = d.bool(forKey: "alwaysExpandOnHover")
        preventCloseOnMouseLeave = d.object(forKey: "preventCloseOnMouseLeave") != nil
            ? d.bool(forKey: "preventCloseOnMouseLeave") : true

        notchWidthOffset = d.double(forKey: "notchWidthOffset")
        notchHeightOffset = d.double(forKey: "notchHeightOffset")
        hoverZonePadding = d.object(forKey: "hoverZonePadding") != nil
            ? d.double(forKey: "hoverZonePadding") : 14
        contentPadding = d.object(forKey: "contentPadding") != nil
            ? d.double(forKey: "contentPadding") : 8
    }

    // MARK: - Color Helpers

    private func saveColor(_ color: Color, forKey key: String) {
        let nsColor = NSColor(color)
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        defaults.set(
            [converted.redComponent, converted.greenComponent, converted.blueComponent],
            forKey: key
        )
    }

    private static func loadColor(from defaults: UserDefaults, forKey key: String) -> Color? {
        guard let c = defaults.array(forKey: key) as? [Double], c.count == 3 else { return nil }
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    // MARK: - Login Item

    private func updateLoginItem() {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    // MARK: - Reset

    func resetAll() {
        let domain = Bundle.main.bundleIdentifier ?? "com.pikochan"
        defaults.removePersistentDomain(forName: domain)

        backgroundStyle = .pitchBlack
        typeButtonColor = Color(red: 0.15, green: 0.7, blue: 0.85)
        talkButtonColor = Color(red: 0.85, green: 0.35, blue: 0.55)
        spriteSize = 100
        launchAtLogin = false
        openOnHover = true
        alwaysExpandOnHover = false
        preventCloseOnMouseLeave = true
        notchWidthOffset = 0
        notchHeightOffset = 0
        hoverZonePadding = 14
        contentPadding = 8
    }

    // MARK: - Types

    enum BackgroundStyle: String, CaseIterable {
        case pitchBlack
        case translucent

        var displayName: String {
            switch self {
            case .pitchBlack: "Pitch Black"
            case .translucent: "Translucent"
            }
        }
    }
}
