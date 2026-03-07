import SwiftUI

struct AwarenessTab: View {
    @Bindable private var config = PikoConfigStore.shared

    var body: some View {
        Form {
            Section("Heartbeat") {
                Toggle("Enable heartbeat", isOn: $config.heartbeatEnabled)
                Stepper(
                    "Interval: \(config.heartbeatInterval)s",
                    value: $config.heartbeatInterval,
                    in: 15...300,
                    step: 15
                )
                .disabled(!config.heartbeatEnabled)
            }

            Section("Proactive Nudges") {
                Toggle("Enable nudges", isOn: $config.heartbeatNudgesEnabled)
                    .disabled(!config.heartbeatEnabled)

                Toggle("Long idle (2hr+)", isOn: $config.nudgeLongIdle)
                    .disabled(!config.heartbeatEnabled || !config.heartbeatNudgesEnabled)
                Toggle("Late night (1–4am)", isOn: $config.nudgeLateNight)
                    .disabled(!config.heartbeatEnabled || !config.heartbeatNudgesEnabled)
                Toggle("Marathon session (4hr+)", isOn: $config.nudgeMarathon)
                    .disabled(!config.heartbeatEnabled || !config.heartbeatNudgesEnabled)
            }

            Section("Quiet Hours") {
                Stepper(
                    "Start: \(config.quietHoursStart):00",
                    value: $config.quietHoursStart,
                    in: 0...23
                )
                .disabled(!config.heartbeatEnabled)
                Stepper(
                    "End: \(config.quietHoursEnd):00",
                    value: $config.quietHoursEnd,
                    in: 0...23
                )
                .disabled(!config.heartbeatEnabled)
            }

            Section {
                Button("Save") {
                    try? config.save()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { config.reload() }
    }
}
