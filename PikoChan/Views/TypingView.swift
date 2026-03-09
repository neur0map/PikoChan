import SwiftUI

/// Typing state: back + input capsule + voice circle.
/// When recording, the text field smoothly swaps to live waveform bars inside the same capsule.
struct TypingView: View {
    @Bindable var manager: NotchManager
    @State private var isHoveringVoice = false

    private var trimmedInput: String {
        manager.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Back button
            Button {
                if manager.isRecording {
                    manager.isRecording = false
                    _ = manager.voiceCapture?.stopCapture()
                }
                manager.transition(to: .expanded)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.06))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            // Input capsule — text field OR waveform bars
            HStack(spacing: 4) {
                if manager.isRecording {
                    // Live waveform bars inside the capsule
                    DictationBarsView(
                        readLevel: { [weak manager] in manager?.voiceCapture?.audioLevel ?? 0 }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .transition(.blurReplace)
                } else {
                    // Text field
                    PikoTextField(
                        text: $manager.inputText,
                        placeholder: "Ask PikoChan...",
                        onSubmit: handleSubmit
                    )
                    .frame(height: 18)
                    .transition(.blurReplace)
                }

                // Right-side action button
                actionButton
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.white.opacity(0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(manager.isRecording ? 0.12 : 0.08), lineWidth: 0.5)
                    )
            )
            .animation(.smooth(duration: 0.25), value: manager.isRecording)

            // Voice-to-voice circle
            if !manager.isResponding && !manager.isRecording {
                Button {
                    manager.transition(to: .listening)
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isHoveringVoice ? .black : .black.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(.white.opacity(isHoveringVoice ? 1.0 : 0.88))
                        )
                        .scaleEffect(isHoveringVoice ? 1.06 : 1.0)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        isHoveringVoice = h
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: manager.isRecording)
    }

    // MARK: - Action Button (right side of capsule)

    @ViewBuilder
    private var actionButton: some View {
        if manager.isResponding {
            Button(action: { manager.cancelResponse() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.6))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else if manager.isRecording {
            Button { manager.stopRecordingAndDictate() } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else if !trimmedInput.isEmpty {
            Button(action: handleSubmit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else {
            Button { manager.startRecording() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func handleSubmit() {
        manager.submitTextInput()
    }
}
