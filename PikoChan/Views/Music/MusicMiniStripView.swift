import SwiftUI

/// Thin music strip shown at the top of the assistant view when music is playing.
/// Tap to return to the extended music view.
struct MusicMiniStripView: View {
    let nowPlaying: PikoNowPlaying
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Mini album art.
                albumArtView(size: 28)

                // Track info.
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.trackTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(nowPlaying.artistName)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                // Mini controls.
                HStack(spacing: 12) {
                    miniControlButton(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill") {
                        nowPlaying.togglePlayPause()
                    }

                    miniControlButton(systemName: "forward.fill") {
                        nowPlaying.nextTrack()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Mini Album Art

    @ViewBuilder
    private func albumArtView(size: CGFloat) -> some View {
        if let art = nowPlaying.albumArt {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.3))
                )
        }
    }

    // MARK: - Mini Control Button

    private func miniControlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
