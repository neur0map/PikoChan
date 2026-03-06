import SwiftUI

/// Listening state controls.
struct ListeningView: View {
    let onStopTapped: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            WaveView()
                .padding(.horizontal, 8)

            Button(action: onStopTapped) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }
}
