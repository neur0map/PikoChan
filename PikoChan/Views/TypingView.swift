import SwiftUI

/// Typing state: PikoChan sprite (small) + back button + capsule text field.
struct TypingView: View {
    @Bindable var manager: NotchManager

    var body: some View {
        VStack(spacing: 8) {
            // ── Mascot (compact) ──
            Image("pikochan_sprite")
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(height: 90)

            // ── Input row with back button ──
            HStack(spacing: 8) {
                // Back button
                Button {
                    manager.transition(to: .expanded)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                // Text field — uses NSTextField wrapper to avoid ViewBridge errors
                HStack(spacing: 6) {
                    PikoTextField(
                        text: $manager.inputText,
                        placeholder: "Ask PikoChan...",
                        onSubmit: handleSubmit
                    )
                    .frame(height: 18)

                    if !manager.inputText.isEmpty {
                        Button(action: handleSubmit) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    private func handleSubmit() {
        guard !manager.inputText.isEmpty else { return }
        manager.inputText = ""
        manager.transition(to: .expanded)
    }
}
