import SwiftUI

/// Settings tab for interaction behavior.
struct BehaviorTab: View {
    @Bindable private var settings = PikoSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } footer: {
                Text("PikoChan will start automatically when you log in.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open on hover", isOn: $settings.openOnHover)
                Toggle("Always expand on hover", isOn: $settings.alwaysExpandOnHover)
                    .disabled(!settings.openOnHover)
            } header: {
                Text("Hover")
            } footer: {
                Text("When \"Always expand\" is on, hovering skips the peek animation and opens directly.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Prevent close on mouse leave", isOn: $settings.preventCloseOnMouseLeave)
            } footer: {
                Text("When on, the notch only closes on click-outside or Escape. When off, moving the mouse away will auto-close.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
