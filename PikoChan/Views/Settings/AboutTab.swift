import SwiftUI

/// Settings tab showing app identity, reset, and quit.
struct AboutTab: View {
    @State private var showResetAlert = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("pikochan_sprite")
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PikoChan")
                            .font(.title2.bold())
                        Text("v\(appVersion) (\(buildNumber))")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Reset All Settings") {
                    showResetAlert = true
                }
                .alert("Reset All Settings?", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        PikoSettings.shared.resetAll()
                    }
                } message: {
                    Text("This will restore all settings to their defaults.")
                }
            }

            Section {
                Button("Quit PikoChan") {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
