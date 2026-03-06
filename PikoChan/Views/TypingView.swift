import SwiftUI

/// Typing state controls.
struct TypingView: View {
    @Bindable var manager: NotchManager

    private var trimmedInput: String {
        manager.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
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

            // Text field + action button
            HStack(spacing: 6) {
                PikoTextField(
                    text: $manager.inputText,
                    placeholder: "Ask PikoChan...",
                    onSubmit: handleSubmit
                )
                .frame(height: 18)

                if manager.isResponding {
                    // Cancel/stop button while responding.
                    Button(action: { manager.cancelResponse() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.7))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else if !trimmedInput.isEmpty {
                    // Submit button when there's input.
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

    private func handleSubmit() {
        manager.submitTextInput()
    }
}
