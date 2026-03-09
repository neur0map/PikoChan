import SwiftUI

/// Expanded notch: unified input bar with STT mic + voice-to-voice circle.
struct ExpandedView: View {
    @Bindable var manager: NotchManager
    let onTextTapped: () -> Void
    let onVoiceTapped: () -> Void

    @State private var isHoveringBar = false
    @State private var isHoveringMic = false
    @State private var isHoveringVoice = false

    var body: some View {
        HStack(spacing: 10) {
            // Input bar: [text area] [mic]
            HStack(spacing: 0) {
                // Text area — tap to start typing
                Button(action: onTextTapped) {
                    Text("Ask PikoChan...")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.30))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Mic — tap to start STT dictation into text field
                Button {
                    manager.startRecording()
                    onTextTapped()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(isHoveringMic ? 0.8 : 0.40))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(.white.opacity(isHoveringMic ? 0.08 : 0))
                        )
                        .scaleEffect(isHoveringMic ? 1.05 : 1.0)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        isHoveringMic = h
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.white.opacity(isHoveringBar ? 0.08 : 0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .onHover { h in
                withAnimation(.easeOut(duration: 0.15)) { isHoveringBar = h }
            }

            // Voice-to-voice circle
            Button(action: onVoiceTapped) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isHoveringVoice ? .black : .black.opacity(0.85))
                    .frame(width: 38, height: 38)
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
        }
    }
}

// MARK: - GhostIconButton

/// Invisible at rest, reveals a subtle circle on hover, bounces on press.
struct GhostIconButton: View {
    let icon: String
    let action: () -> Void
    var iconSize: CGFloat = 16
    var hitSize: CGFloat = 36

    @State private var isHovering = false
    @State private var isPressed = false

    private var iconOpacity: Double {
        if isPressed { return 0.95 }
        if isHovering { return 0.90 }
        return 0.40
    }

    private var bgOpacity: Double {
        if isPressed { return 0.12 }
        if isHovering { return 0.08 }
        return 0
    }

    private var scale: CGFloat {
        if isPressed { return 0.92 }
        if isHovering { return 1.08 }
        return 1.0
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(iconOpacity))
                .frame(width: hitSize, height: hitSize)
                .background(
                    Circle()
                        .fill(.white.opacity(bgOpacity))
                )
                .scaleEffect(scale)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
