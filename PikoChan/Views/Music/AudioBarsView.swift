import SwiftUI

/// Animated 3-bar audio visualizer that pulses when music is playing.
/// Bars freeze at mid-height when paused.
struct AudioBarsView: View {
    var isPlaying: Bool
    var barColor: Color = .white.opacity(0.5)
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2
    var height: CGFloat = 20

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let t = isPlaying ? timeline.date.timeIntervalSinceReferenceDate : 0
                let barCount = 3
                let totalBarWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
                let startX = (size.width - totalBarWidth) / 2

                for i in 0..<barCount {
                    let phase = Double(i) * 0.8
                    let freq = 2.5 + Double(i) * 0.7
                    let normalizedHeight: CGFloat
                    if isPlaying {
                        let sine = sin(t * freq + phase)
                        normalizedHeight = CGFloat(0.4 + 0.6 * (sine + 1) / 2)
                    } else {
                        normalizedHeight = 0.5
                    }

                    let barHeight = height * normalizedHeight
                    let x = startX + CGFloat(i) * (barWidth + spacing)
                    let y = size.height - barHeight

                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let path = RoundedRectangle(cornerRadius: barWidth / 2)
                        .path(in: rect)
                    context.fill(path, with: .color(barColor))
                }
            }
        }
        .frame(width: barWidth * 3 + spacing * 2 + 4, height: height)
    }
}
