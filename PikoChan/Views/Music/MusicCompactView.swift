import SwiftUI

/// Compact Now Playing — album art left, audio bars right.
/// Same height as idle notch — only expands horizontally.
/// Hovering anywhere on the pill reveals the track name below.
struct MusicCompactView: View {
    let nowPlaying: PikoNowPlaying
    let manager: NotchManager

    private let artSize: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                albumArt
                    .padding(.leading, 10)

                Spacer()

                AudioBarsView(
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 2.5,
                    spacing: 1.5,
                    height: 12
                )
                .padding(.trailing, 12)
            }

            if manager.isHoveringMusicArt {
                Text(nowPlaying.trackTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .offset(y: -3)))
            }
        }
    }

    private var albumArt: some View {
        Group {
            if let art = nowPlaying.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: artSize, height: artSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: artSize, height: artSize)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }
        }
    }
}
