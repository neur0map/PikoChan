import SwiftUI

/// Renders a single feed item based on its kind.
struct FeedItemView: View {
    let item: PikoFeedItem
    let actionHandler: PikoActionHandler
    var onApprove: ((PikoAction) -> Void)?
    var onDeny: ((PikoAction) -> Void)?
    var onAllowSession: ((PikoAction) -> Void)?

    var body: some View {
        switch item.kind {
        case .userMessage(let text):
            UserFeedRow(text: text)

        case .assistantMessage(let text):
            AssistantFeedRow(text: text)

        case .actionRef(let actionId):
            if let action = actionHandler.actions.first(where: { $0.id == actionId }) {
                ActionFeedRow(
                    action: action,
                    onApprove: { onApprove?(action) },
                    onDeny: { onDeny?(action) },
                    onAllowSession: { onAllowSession?(action) }
                )
            }
        }
    }
}

// MARK: - User Message Row

private struct UserFeedRow: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.10))
                )
        }
    }
}

// MARK: - Assistant Message Row (iMessage-style blue bubble)

private struct AssistantFeedRow: View {
    let text: String

    /// Strip markdown bold markers and leftover tag fragments from LLM output.
    private var cleanText: String {
        var result = text.replacingOccurrences(of: "**", with: "")
        // Strip any leftover action/MCP tags that slipped through.
        result = StreamingFeedRow.stripTagsForDisplay(result)
        return result
    }

    var body: some View {
        HStack {
            Text(cleanText)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(12)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.35))
                )
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Action Row

struct ActionFeedRow: View {
    let action: PikoAction
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?
    var onAllowSession: (() -> Void)?

    @State private var isOutputExpanded = false
    @State private var isCommandExpanded = false

    private var commandLabel: String {
        switch action.kind {
        case .shell(let cmd): cmd
        case .openURL(let url): url
        case .mcpInstall(let serverName): serverName
        case .mcpToolCall(let serverName, let toolName): "\(serverName).\(toolName)"
        }
    }

    private var iconName: String {
        switch action.kind {
        case .shell: "terminal"
        case .openURL: "globe"
        case .mcpInstall: "puzzlepiece.extension"
        case .mcpToolCall: "puzzlepiece"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row: tap anywhere to expand/collapse command
            HStack(spacing: 6) {
                FeedStatusDot(
                    status: action.status,
                    needsApproval: action.needsConfirmation && action.isPending
                )

                Image(systemName: iconName)
                    .font(.system(size: 9))
                    .foregroundStyle(toolColor)

                Text(toolLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(toolColor)
                    .fixedSize()

                Text(commandLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)

                Spacer(minLength: 0)

                // Right cluster: chevron + exit code (never clips)
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(isCommandExpanded ? 90 : 0))

                    if case .completed(let result) = action.status {
                        Text("exit \(result.exitCode)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(result.exitCode == 0 ? .green.opacity(0.7) : .red.opacity(0.7))
                    }

                    if case .completedMCP(_, let isError) = action.status {
                        Text(isError ? "error" : "done")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(isError ? .red.opacity(0.7) : .green.opacity(0.7))
                    }

                    if case .executing = action.status {
                        Text("Running…")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isCommandExpanded.toggle()
                }
            }

            // Expanded full command (auto-expanded for pending approval)
            if isCommandExpanded || (action.needsConfirmation && action.isPending) {
                Text(commandLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Approval buttons — Deny / Allow / Always
            if action.needsConfirmation, action.isPending {
                InlineApprovalView(
                    onApprove: { onApprove?() },
                    onDeny: { onDeny?() },
                    onAllowSession: { onAllowSession?() }
                )
            }

            // Result content (collapsed by default)
            if case .completed(let result) = action.status {
                completedResultView(result)
            }

            if case .completedMCP(let content, let isError) = action.status {
                mcpResultView(content: content, isError: isError)
            }

            if case .failed(let reason) = action.status {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
    }

    // MARK: - Result View (collapsed by default)

    @ViewBuilder
    private func completedResultView(_ result: PikoTerminal.CommandResult) -> some View {
        let output = combinedOutput(result)
        if !output.isEmpty {
            let lines = output.components(separatedBy: "\n")

            // Toggle header — full-width tap target
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isOutputExpanded ? 90 : 0))
                Text("Output (\(lines.count) lines)")
                    .font(.system(size: 9))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.35))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isOutputExpanded.toggle()
                }
            }

            // Expanded output content
            if isOutputExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(result.exitCode == 0 ? .white.opacity(0.5) : .red.opacity(0.6))
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.3))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - MCP Result View

    @ViewBuilder
    private func mcpResultView(content: String, isError: Bool) -> some View {
        if !content.isEmpty {
            let lines = content.components(separatedBy: "\n")

            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isOutputExpanded ? 90 : 0))
                Text("Result (\(lines.count) lines)")
                    .font(.system(size: 9))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.35))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isOutputExpanded.toggle()
                }
            }

            if isOutputExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(isError ? .red.opacity(0.6) : .white.opacity(0.5))
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.3))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Helpers

    private var toolLabel: String {
        switch action.kind {
        case .shell: "Bash"
        case .openURL: "Open"
        case .mcpInstall: "MCP"
        case .mcpToolCall(let serverName, _): serverName
        }
    }

    private var toolColor: Color {
        switch action.status {
        case .pending where action.needsConfirmation:
            Color(red: 1.0, green: 0.75, blue: 0.0) // amber
        case .executing:
            Color(red: 0.85, green: 0.47, blue: 0.34) // claude orange
        case .completed(let r) where r.exitCode == 0:
            .white.opacity(0.6)
        case .completed:
            .red.opacity(0.7)
        case .completedMCP(_, let isError):
            isError ? .red.opacity(0.7) : .white.opacity(0.6)
        case .failed:
            .red.opacity(0.7)
        default:
            .white.opacity(0.5)
        }
    }

    private func combinedOutput(_ result: PikoTerminal.CommandResult) -> String {
        var parts: [String] = []
        if !result.stdout.isEmpty { parts.append(result.stdout) }
        if !result.stderr.isEmpty { parts.append("stderr: \(result.stderr)") }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Streaming Row (blue bubble with thinking dots)

/// Shows the in-progress streaming response in an iMessage-style blue bubble.
struct StreamingFeedRow: View {
    let text: String

    /// Strips known action/MCP/config/cron tags from streaming text so the user
    /// never sees raw `[mcp:install:{...}]` or `[shell:...]` during generation.
    private var displayText: String {
        Self.stripTagsForDisplay(text.replacingOccurrences(of: "**", with: ""))
    }

    /// Hides everything from the first recognized tag prefix onward.
    /// During streaming, tags appear at the tail — truncating is safe.
    /// The final clean text is shown in AssistantFeedRow after streaming completes.
    static func stripTagsForDisplay(_ text: String) -> String {
        let tagPrefixes = ["[mcp:", "[shell:", "[open:", "[config:", "[cron:", "[nudge_after:"]
        var earliestIdx: String.Index?
        for prefix in tagPrefixes {
            if let range = text.range(of: prefix) {
                if earliestIdx == nil || range.lowerBound < earliestIdx! {
                    earliestIdx = range.lowerBound
                }
            }
        }
        let result = earliestIdx.map { String(text[..<$0]) } ?? text
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack {
            Group {
                if displayText.isEmpty {
                    StreamingDots()
                } else {
                    Text(displayText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.35))
            )
            Spacer(minLength: 0)
        }
    }
}

/// Animated dots shown while PikoChan is thinking.
private struct StreamingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .opacity(animating ? 0.9 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.2),
                        value: animating
                    )
            }
        }
        .frame(height: 14)
        .onAppear { animating = true }
    }
}
