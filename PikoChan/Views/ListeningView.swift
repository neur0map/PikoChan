import SwiftUI

/// Listening state controls with tap-to-toggle mic button.
struct ListeningView: View {
    @Bindable var manager: NotchManager

    var body: some View {
        VStack(spacing: 6) {
            WaveView(audioLevel: manager.voiceCapture?.audioLevel ?? 0)
                .padding(.horizontal, 8)

            HStack(spacing: 20) {
                // Back button → return to expanded.
                Button {
                    if manager.isRecording {
                        manager.isRecording = false
                        _ = manager.voiceCapture?.stopCapture()
                    }
                    manager.transition(to: .expanded)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Tap-to-toggle mic button.
                Button {
                    if manager.isRecording {
                        manager.stopRecordingAndTranscribe()
                    } else {
                        manager.startRecording()
                    }
                } label: {
                    Image(systemName: manager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(manager.isRecording ? .red : .white.opacity(0.7))
                        .symbolEffect(.pulse, isActive: manager.isRecording)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }
}
