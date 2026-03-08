import Foundation

struct PikoAction: Identifiable {
    let id = UUID()

    enum Kind {
        case shell(command: String)
        case openURL(url: String)
    }

    enum Status {
        case pending
        case executing
        case completed(PikoTerminal.CommandResult)
        case cancelled
        case failed(String)
    }

    let kind: Kind
    let needsConfirmation: Bool
    var status: Status = .pending
}

@Observable
@MainActor
final class PikoActionHandler {
    var actions: [PikoAction] = []
    var isExecuting = false

    // MARK: - Parsing

    /// Parses action tags from LLM response text. Returns cleaned text and extracted actions.
    func parseActions(from text: String) -> (cleanText: String, actions: [PikoAction]) {
        var cleanText = text
        var parsed: [PikoAction] = []

        let config = PikoConfigStore.shared

        // Parse [shell:COMMAND] tags.
        let shellPattern = /\[shell:(.+?)\]/
        for match in text.matches(of: shellPattern) {
            var command = String(match.1).trimmingCharacters(in: .whitespaces)
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")

            guard config.skillsTerminalEnabled else { continue }

            // If the command is `open "path"` or `open path`, resolve the path on disk
            // to fix LLM mistakes (collapsed spaces, truncated filenames).
            command = Self.resolveShellOpenCommand(command)

            if PikoTerminal.isBlockedCommand(command) {
                PikoGateway.shared.logActionBlocked(command: command, reason: "blocked_pattern")
                continue
            }

            let needsConfirm = !(config.skillsAutoExecuteSafe && PikoTerminal.isSafeCommand(command))
            parsed.append(PikoAction(kind: .shell(command: command), needsConfirmation: needsConfirm))
        }

        // Parse [open:URL] tags.
        let openPattern = /\[open:(.+?)\]/
        for match in text.matches(of: openPattern) {
            let target = String(match.1).trimmingCharacters(in: .whitespaces)
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")

            // File paths → convert to shell `open` command (terminal skill).
            if target.hasPrefix("/") || target.hasPrefix("~") || target.hasPrefix("./") {
                guard config.skillsTerminalEnabled else { continue }
                let resolvedPath = Self.resolveOpenPath(target)
                let command = "open \"\(resolvedPath)\""
                let needsConfirm = !(config.skillsAutoExecuteSafe && PikoTerminal.isSafeCommand(command))
                parsed.append(PikoAction(kind: .shell(command: command), needsConfirmation: needsConfirm))
            } else {
                guard config.skillsBrowserEnabled else { continue }
                parsed.append(PikoAction(kind: .openURL(url: target), needsConfirmation: false))
            }
        }

        // Clean up whitespace artifacts.
        cleanText = cleanText
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        actions = parsed
        return (cleanText, parsed)
    }

    // MARK: - Execution

    /// Executes all auto-approved actions (no confirmation needed). Returns executed actions.
    func executeAutoApproved() async -> [PikoAction] {
        isExecuting = true
        var executed: [PikoAction] = []

        for i in actions.indices {
            guard !actions[i].needsConfirmation, case .pending = actions[i].status else { continue }

            switch actions[i].kind {
            case .shell(let command):
                actions[i].status = .executing
                PikoGateway.shared.logActionExecute(command: command, autoApproved: true)

                let result = await PikoTerminal.execute(command)
                actions[i].status = .completed(result)
                executed.append(actions[i])

                PikoGateway.shared.logActionResult(
                    command: command, exitCode: result.exitCode,
                    durationMs: result.durationMs, outputChars: result.stdout.count + result.stderr.count
                )

            case .openURL(let url):
                let success = PikoBrowser.open(url)
                if success {
                    actions[i].status = .completed(PikoTerminal.CommandResult(
                        command: "open \(url)", exitCode: 0,
                        stdout: "Opened in browser", stderr: "",
                        truncated: false, timedOut: false, durationMs: 0
                    ))
                } else {
                    actions[i].status = .failed("Invalid URL")
                }
                executed.append(actions[i])
            }
        }

        isExecuting = false
        return executed
    }

    /// Execute a single action (for user-confirmed actions).
    func execute(_ action: PikoAction) async {
        guard let idx = actions.firstIndex(where: { $0.id == action.id }) else { return }
        isExecuting = true

        switch actions[idx].kind {
        case .shell(let command):
            actions[idx].status = .executing
            PikoGateway.shared.logActionExecute(command: command, autoApproved: false)

            let result = await PikoTerminal.execute(command)
            actions[idx].status = .completed(result)

            PikoGateway.shared.logActionResult(
                command: command, exitCode: result.exitCode,
                durationMs: result.durationMs, outputChars: result.stdout.count + result.stderr.count
            )

        case .openURL(let url):
            let success = PikoBrowser.open(url)
            actions[idx].status = success
                ? .completed(PikoTerminal.CommandResult(
                    command: "open \(url)", exitCode: 0,
                    stdout: "Opened in browser", stderr: "",
                    truncated: false, timedOut: false, durationMs: 0))
                : .failed("Invalid URL")
        }

        isExecuting = false
    }

    /// Cancel a pending action.
    func cancel(_ action: PikoAction) {
        guard let idx = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[idx].status = .cancelled
    }

    // MARK: - Re-query

    /// Builds a message for LLM re-query with command results.
    func formatResultsForRequery() -> String {
        var parts: [String] = ["Here are the results of the commands I ran:"]

        for action in actions {
            guard case .completed(let result) = action.status else { continue }

            parts.append("$ \(result.command)")
            if result.exitCode == 0 {
                if !result.stdout.isEmpty {
                    parts.append(result.stdout)
                }
            } else {
                parts.append("Exit code: \(result.exitCode)")
                if !result.stderr.isEmpty {
                    parts.append("Error: \(result.stderr)")
                }
            }
            if result.timedOut {
                parts.append("(Command timed out after 30s)")
            }
        }

        parts.append("\nSummarize these results for the user in a helpful way. Do NOT use [shell:], [open:], or any action tags in your response.")
        return parts.joined(separator: "\n")
    }

    /// Whether any completed shell actions have output worth re-querying about.
    var hasCompletedShellActions: Bool {
        actions.contains { action in
            if case .shell = action.kind, case .completed = action.status { return true }
            return false
        }
    }

    func reset() {
        actions = []
        isExecuting = false
    }

    // MARK: - Path Resolution

    /// If the command is `open "path"` or `open path`, resolve the path on disk.
    private static func resolveShellOpenCommand(_ command: String) -> String {
        // Match: open "quoted/path" or open ~/unquoted/path
        let quoted = #/^open\s+"(.+)"$/#
        let unquoted = #/^open\s+(~?\/.+)$/#

        let path: String
        if let m = command.firstMatch(of: quoted) {
            path = String(m.1)
        } else if let m = command.firstMatch(of: unquoted) {
            path = String(m.1)
        } else {
            return command
        }

        let resolved = resolveOpenPath(path)
        return "open \"\(resolved)\""
    }

    /// Given a path the LLM produced, resolve it to an actual file on disk.
    /// Handles common LLM mistakes: collapsed double-spaces, truncated filenames,
    /// backslash escapes, etc.
    private static func resolveOpenPath(_ raw: String) -> String {
        // Clean backslash escapes and expand tilde.
        let cleaned = raw.replacingOccurrences(of: "\\ ", with: " ")
        let expanded = (cleaned as NSString).expandingTildeInPath

        let fm = FileManager.default

        // If exact path exists, use it.
        if fm.fileExists(atPath: expanded) { return expanded }

        // Try fuzzy match in the parent directory.
        let dir = (expanded as NSString).deletingLastPathComponent
        let target = (expanded as NSString).lastPathComponent.lowercased()
        guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { return expanded }

        // Normalize: collapse whitespace for comparison.
        let normalizedTarget = target.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }.joined(separator: " ")

        var bestMatch: String?
        var bestScore = 0

        for filename in contents {
            let normalizedFile = filename.lowercased()
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }.joined(separator: " ")

            // Exact match after normalization.
            if normalizedFile == normalizedTarget {
                return (dir as NSString).appendingPathComponent(filename)
            }

            // Prefix match (LLM truncated the filename).
            if normalizedFile.hasPrefix(normalizedTarget) || normalizedTarget.hasPrefix(normalizedFile) {
                let score = min(normalizedFile.count, normalizedTarget.count)
                if score > bestScore {
                    bestScore = score
                    bestMatch = filename
                }
                continue
            }

            // Contains match — the LLM-produced name is a substantial substring.
            if normalizedTarget.count >= 10 && normalizedFile.contains(normalizedTarget) {
                return (dir as NSString).appendingPathComponent(filename)
            }
            if normalizedFile.count >= 10 && normalizedTarget.contains(normalizedFile) {
                let score = normalizedFile.count
                if score > bestScore {
                    bestScore = score
                    bestMatch = filename
                }
            }
        }

        // Accept fuzzy match only if it covers enough of the target.
        if let match = bestMatch, bestScore >= normalizedTarget.count / 2 {
            return (dir as NSString).appendingPathComponent(match)
        }

        return expanded  // Couldn't resolve — return cleaned path.
    }
}
