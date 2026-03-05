import SwiftUI

/// Continuously animated sine waves beneath PikoChan in listening mode.
/// Uses TimelineView for guaranteed smooth 60fps redraw.
struct WaveView: View {
    private let waves: [(color: Color, amplitude: CGFloat, frequency: CGFloat, speed: CGFloat, offset: CGFloat)] = [
        (Color(red: 0.15, green: 0.35, blue: 0.95), 8, 1.5, 1.2, 0),
        (Color(red: 0.5, green: 0.28, blue: 0.88),  6, 1.9, 1.6, 0.9),
        (Color(red: 0.1, green: 0.78, blue: 0.68),  7, 1.7, 1.0, 1.8),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let midY = size.height / 2

                for wave in waves {
                    var path = Path()
                    let steps = Int(size.width)
                    let phase = elapsed * wave.speed + wave.offset

                    for x in 0...steps {
                        let nx = CGFloat(x) / size.width
                        let y = midY + sin(nx * .pi * 2 * wave.frequency + phase) * wave.amplitude
                        if x == 0 {
                            path.move(to: CGPoint(x: CGFloat(x), y: y))
                        } else {
                            path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                        }
                    }

                    context.stroke(
                        path,
                        with: .color(wave.color),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(height: 28)
        .mask {
            LinearGradient(
                colors: [.clear, .white, .white, .white, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
