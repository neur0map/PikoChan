import Combine
import SwiftUI

/// Animated status indicator for feed rows.
/// Spinning symbols for active states, solid dots for settled states.
struct FeedStatusDot: View {
    let status: PikoAction.Status
    let needsApproval: Bool

    private static let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)

    @State private var spinnerPhase = 0
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch status {
            case .pending where needsApproval:
                // Waiting for approval — amber spin
                Text(Self.spinnerSymbols[spinnerPhase % Self.spinnerSymbols.count])
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Self.amber)
                    .onReceive(spinnerTimer) { _ in
                        spinnerPhase = (spinnerPhase + 1) % Self.spinnerSymbols.count
                    }

            case .executing:
                // Running — orange spin
                Text(Self.spinnerSymbols[spinnerPhase % Self.spinnerSymbols.count])
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Self.claudeOrange)
                    .onReceive(spinnerTimer) { _ in
                        spinnerPhase = (spinnerPhase + 1) % Self.spinnerSymbols.count
                    }

            case .completed(let result):
                Circle()
                    .fill(result.exitCode == 0 ? Color.green.opacity(0.6) : Color.red.opacity(0.6))
                    .frame(width: 6, height: 6)

            case .failed:
                Circle()
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 6, height: 6)

            case .cancelled:
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)

            default:
                // Pending (auto-execute) — dim
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 14, alignment: .center)
    }
}

/// Simple status dot for streaming/messages.
struct StreamingStatusDot: View {
    private static let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    @State private var spinnerPhase = 0
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(Self.spinnerSymbols[spinnerPhase % Self.spinnerSymbols.count])
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Self.claudeOrange)
            .frame(width: 14, alignment: .center)
            .onReceive(spinnerTimer) { _ in
                spinnerPhase = (spinnerPhase + 1) % Self.spinnerSymbols.count
            }
    }
}
