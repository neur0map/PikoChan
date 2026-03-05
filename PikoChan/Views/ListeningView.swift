import SwiftUI

/// Listening state: PikoChan sprite with animated waves underneath + stop button.
struct ListeningView: View {
    let onStopTapped: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // ── Mascot ──
            Image("pikochan_sprite")
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(height: 90)

            // ── Waves ──
            WaveView()
                .padding(.horizontal, 8)

            // ── Stop button ──
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
