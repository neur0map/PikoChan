import SwiftUI

/// Listening state (voice-to-voice): waveform bars + back/mic controls.
struct ListeningView: View {
    @Bindable var manager: NotchManager

    var body: some View {
        VStack(spacing: 8) {
            // Live waveform bars
            DictationBarsView(
                readLevel: { [weak manager] in manager?.voiceCapture?.audioLevel ?? 0 },
                maxBarHeight: 32
            )

            // Controls: back + mic
            HStack(spacing: 24) {
                Button {
                    if manager.isRecording {
                        manager.isRecording = false
                        _ = manager.voiceCapture?.stopCapture()
                    }
                    manager.transition(to: .expanded)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.40))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    if manager.isRecording {
                        manager.stopRecordingAndTranscribe()
                    } else {
                        manager.startRecording()
                    }
                } label: {
                    Image(systemName: manager.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(manager.isRecording ? .red.opacity(0.7) : .white.opacity(0.45))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
