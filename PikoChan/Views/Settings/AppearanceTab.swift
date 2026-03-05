import SwiftUI

/// Settings tab for visual customization.
struct AppearanceTab: View {
    @Bindable private var settings = PikoSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Background style:", selection: $settings.backgroundStyle) {
                    ForEach(PikoSettings.BackgroundStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Pitch Black matches the hardware notch. Translucent lets your desktop show through.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ColorPicker("Type button:", selection: $settings.typeButtonColor, supportsOpacity: false)
                ColorPicker("Talk button:", selection: $settings.talkButtonColor, supportsOpacity: false)
            } header: {
                Text("Button Accent Colors")
            }

            Section {
                HStack {
                    Text("Sprite size:")
                    Slider(value: $settings.spriteSize, in: 80...120, step: 5)
                    Text("\(Int(settings.spriteSize))px")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            } footer: {
                Text("Controls the PikoChan mascot size in expanded mode.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
