import SwiftUI

/// Settings tab for notch geometry fine-tuning.
struct NotchTuneTab: View {
    @Bindable private var settings = PikoSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Width:")
                    Slider(value: $settings.notchWidthOffset, in: -20...20, step: 1)
                    Text("\(Int(settings.notchWidthOffset))")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                HStack {
                    Text("Height:")
                    Slider(value: $settings.notchHeightOffset, in: -10...10, step: 1)
                    Text("\(Int(settings.notchHeightOffset))")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            } header: {
                Text("Notch Size Offset")
            } footer: {
                Text("Adjust if PikoChan doesn't align perfectly with your hardware notch.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Hover zone padding:")
                    Slider(value: $settings.hoverZonePadding, in: 5...30, step: 1)
                    Text("\(Int(settings.hoverZonePadding))")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            } footer: {
                Text("How far below the notch the invisible hover detection extends. Larger = easier to trigger.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Content padding:")
                    Slider(value: $settings.contentPadding, in: 0...12, step: 1)
                    Text("\(Int(settings.contentPadding))")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            } footer: {
                Text("Gap between the notch edge and where PikoChan's content begins.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Defaults") {
                    settings.notchWidthOffset = 0
                    settings.notchHeightOffset = 0
                    settings.hoverZonePadding = 14
                    settings.contentPadding = 8
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
