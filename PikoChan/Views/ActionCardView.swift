import SwiftUI

struct ActionCardView: View {
    let action: PikoAction
    var onRun: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Command label.
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9))
                    .foregroundStyle(iconColor)
                Text(commandLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            switch action.status {
            case .pending:
                if action.needsConfirmation {
                    HStack(spacing: 8) {
                        Button {
                            onRun?()
                        } label: {
                            Text("Run")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(.blue.opacity(0.6))
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onCancel?()
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .executing:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running...")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }

            case .completed(let result):
                HStack(spacing: 4) {
                    Text("exit \(result.exitCode)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(result.exitCode == 0 ? .green.opacity(0.7) : .red.opacity(0.7))
                    if result.timedOut {
                        Text("(timed out)")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                    Text("\(result.durationMs)ms")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }

                if !result.stdout.isEmpty || !result.stderr.isEmpty {
                    Text(outputText(result))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.black.opacity(0.3))
                        )
                }

            case .cancelled:
                Text("Cancelled")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))

            case .failed(let reason):
                Text("Failed: \(reason)")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private var commandLabel: String {
        switch action.kind {
        case .shell(let cmd): cmd
        case .openURL(let url): url
        }
    }

    private var iconName: String {
        switch action.kind {
        case .shell: "terminal"
        case .openURL: "globe"
        }
    }

    private var iconColor: Color {
        switch action.status {
        case .completed(let r) where r.exitCode == 0: .green.opacity(0.7)
        case .completed: .red.opacity(0.7)
        case .executing: .blue.opacity(0.7)
        case .cancelled: .white.opacity(0.3)
        case .failed: .red.opacity(0.7)
        case .pending: .white.opacity(0.5)
        }
    }

    private func outputText(_ result: PikoTerminal.CommandResult) -> String {
        var lines: [String] = []
        if !result.stdout.isEmpty { lines.append(result.stdout) }
        if !result.stderr.isEmpty { lines.append("stderr: \(result.stderr)") }
        return lines.joined(separator: "\n")
    }
}
