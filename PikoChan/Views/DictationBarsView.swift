import SwiftUI

/// Live audio waveform bars that react to mic input level.
/// Takes a closure to read current audio level each frame (avoids stale captures).
struct DictationBarsView: View {
    var readLevel: () -> Float
    var barCount: Int = 24
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 1.5
    var maxBarHeight: CGFloat = 24
    var minBarHeight: CGFloat = 2.5

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // Boost sensitivity — small mic levels still produce visible bars
            let raw = CGFloat(readLevel())
            let level = max(0.08, min(1.0, raw * 3.5))

            Canvas { context, size in
                let totalBarWidth = barWidth + spacing
                let totalWidth = CGFloat(barCount) * totalBarWidth - spacing
                let startX = (size.width - totalWidth) / 2
                let midY = size.height / 2

                for i in 0..<barCount {
                    let x = startX + CGFloat(i) * totalBarWidth

                    // Three layered sine waves for organic movement
                    let p1 = sin(time * 3.8 + Double(i) * 0.45) * 0.5 + 0.5
                    let p2 = sin(time * 2.3 + Double(i) * 0.72 + 1.3) * 0.5 + 0.5
                    let p3 = sin(time * 5.1 + Double(i) * 0.28 + 2.7) * 0.5 + 0.5

                    // Gaussian envelope — center bars taller
                    let center = CGFloat(barCount) / 2
                    let dist = abs(CGFloat(i) - center) / center
                    let envelope = 1.0 - (dist * dist * 0.7)

                    // Combine with audio level
                    let combined = p1 * 0.45 + p2 * 0.35 + p3 * 0.2
                    let heightFactor = combined * level * envelope
                    let barH = max(minBarHeight, heightFactor * maxBarHeight)
                    let halfH = barH / 2

                    let rect = CGRect(x: x, y: midY - halfH, width: barWidth, height: barH)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    context.fill(path, with: .color(.white.opacity(0.9)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
