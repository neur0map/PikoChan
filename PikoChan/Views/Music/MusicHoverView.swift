import SwiftUI

/// Compact + track name — shown when hovering over the compact music view.
struct MusicHoverView: View {
    let nowPlaying: PikoNowPlaying

    var body: some View {
        HStack(spacing: 6) {
            albumArt
                .padding(.leading, 12)

            Text(nowPlaying.trackTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
                .transition(.opacity.combined(with: .offset(y: 2)))

            Spacer()

            AudioBarsView(isPlaying: nowPlaying.isPlaying, barWidth: 2.5, spacing: 1.5, height: 14)
                .padding(.trailing, 12)
        }
    }

    private var albumArt: some View {
        Group {
            if let art = nowPlaying.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
            }
        }
    }
}
