import SwiftUI

/// Expanded notch: PikoChan sprite + two styled action buttons.
struct ExpandedView: View {
    let onTextTapped: () -> Void
    let onMicTapped: () -> Void
    private var settings: PikoSettings { PikoSettings.shared }

    var body: some View {
        VStack(spacing: 14) {
            // ── Mascot ──
            Image("pikochan_sprite")
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(height: settings.spriteSize)

            // ── Action Buttons ──
            HStack(spacing: 16) {
                PikoButton(
                    icon: "keyboard",
                    label: "Type",
                    accentColor: settings.typeButtonColor,
                    action: onTextTapped
                )

                PikoButton(
                    icon: "waveform",
                    label: "Talk",
                    accentColor: settings.talkButtonColor,
                    action: onMicTapped
                )
            }
        }
    }
}

// MARK: - PikoButton

/// Custom pill button with a colored accent strip and subtle glow.
private struct PikoButton: View {
    let icon: String
    let label: String
    let accentColor: Color
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                ZStack {
                    // Base fill
                    Capsule()
                        .fill(accentColor.opacity(0.2))
                    // Border with accent tint
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [accentColor.opacity(0.5), accentColor.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            }
            .scaleEffect(isPressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = pressing }
        }, perform: {})
    }
}
