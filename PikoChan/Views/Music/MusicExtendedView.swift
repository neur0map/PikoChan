import SwiftUI

/// Full mini-player — album art, track info, playback controls, and PikoChan sprite.
struct MusicExtendedView: View {
    let nowPlaying: PikoNowPlaying
    let spriteImage: Image
    let onSpriteTapped: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Album art — left.
            albumArtView(size: 64)

            // Track info + controls — center.
            VStack(alignment: .leading, spacing: 3) {
                Text(nowPlaying.trackTitle.isEmpty ? "Not Playing" : nowPlaying.trackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(nowPlaying.artistName.isEmpty ? "Unknown Artist" : nowPlaying.artistName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer().frame(height: 2)

                // Playback controls.
                HStack(spacing: 18) {
                    controlButton(systemName: "backward.fill") {
                        nowPlaying.previousTrack()
                    }

                    controlButton(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill") {
                        nowPlaying.togglePlayPause()
                    }

                    controlButton(systemName: "forward.fill") {
                        nowPlaying.nextTrack()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // PikoChan sprite — right.
            spriteButton
        }
        .padding(.horizontal, 16)
        .transition(.blurReplace(.downUp))
    }

    // MARK: - Sprite Button

    private var spriteButton: some View {
        Button(action: onSpriteTapped) {
            spriteImage
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
        }
        .buttonStyle(SpriteButtonStyle())
    }

    // MARK: - Control Button

    private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
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

    // MARK: - Album Art

    @ViewBuilder
    private func albumArtView(size: CGFloat) -> some View {
        if let art = nowPlaying.albumArt {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Sprite Button Style

/// Adds hover glow and gentle idle bounce to the PikoChan sprite.
private struct SpriteButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
            .shadow(color: isHovered ? .white.opacity(0.15) : .clear, radius: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
