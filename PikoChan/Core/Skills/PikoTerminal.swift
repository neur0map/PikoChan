import Foundation

struct PikoTerminal {

    struct CommandResult {
        let command: String
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let truncated: Bool
        let timedOut: Bool
        let durationMs: Int
    }

    /// Maximum output characters before truncation.
    private static let maxOutputChars = 4000
    /// Command timeout in seconds.
    private static let timeoutSeconds: Double = 30

    // MARK: - Execution

    static func execute(_ command: String) async -> CommandResult {
        let startTime = DispatchTime.now()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        // Use the user's login-shell PATH so tools like brew, git, etc. are found.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = userShellPATH
        proc.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            return CommandResult(
                command: command, exitCode: -1,
                stdout: "", stderr: "Failed to launch: \(error.localizedDescription)",
                truncated: false, timedOut: false,
                durationMs: elapsed(since: startTime)
            )
        }

        // Timeout watchdog.
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeoutSeconds))
            if proc.isRunning {
                proc.terminate()
            }
        }

        proc.waitUntilExit()
        timeoutTask.cancel()

        let timedOut = proc.terminationReason == .uncaughtSignal && proc.terminationStatus == 15

        var stdout = readPipe(stdoutPipe)
        var stderr = readPipe(stderrPipe)
        var truncated = false

        if stdout.count > maxOutputChars {
            stdout = String(stdout.prefix(maxOutputChars)) + "\n... (truncated)"
            truncated = true
        }
        if stderr.count > maxOutputChars {
            stderr = String(stderr.prefix(maxOutputChars)) + "\n... (truncated)"
            truncated = true
        }

        return CommandResult(
            command: command,
            exitCode: proc.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            truncated: truncated,
            timedOut: timedOut,
            durationMs: elapsed(since: startTime)
        )
    }

    // MARK: - Safety

    /// Commands that auto-execute without user confirmation.
    private static let safeCommands: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "pwd", "echo", "date",
        "whoami", "which", "file", "stat", "df", "du", "uname", "sw_vers",
        "open", "brew list", "pip list", "pip3 list",
        "git status", "git log", "git diff", "git branch",
    ]

    /// Patterns that are always blocked.
    private static let blockedPatterns: [String] = [
        "sudo ", "su ", " su\n", "rm -rf /", "chmod 777", "mkfs",
        "dd if=", ":(){ :|:& };:", "|sh", "|bash", "|zsh", "|eval",
        "curl|", "wget|",
    ]

    static func isSafeCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.components(separatedBy: " ").first ?? trimmed

        // Check exact match first.
        if safeCommands.contains(trimmed) { return true }
        // Check if the base command is safe (e.g., "ls -la" matches "ls").
        if safeCommands.contains(base) { return true }
        // Check multi-word safe commands.
        for safe in safeCommands where trimmed.hasPrefix(safe) {
            return true
        }

        return false
    }

    static func isBlockedCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        for pattern in blockedPatterns {
            if lower.contains(pattern) { return true }
        }
        // Block commands that start with sudo.
        if lower.trimmingCharacters(in: .whitespaces).hasPrefix("sudo") { return true }
        return false
    }

    // MARK: - Private

    private static func readPipe(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func elapsed(since start: DispatchTime) -> Int {
        let end = DispatchTime.now()
        let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
        return Int(nanos / 1_000_000)
    }

    /// Resolve the user's full login-shell PATH.
    private static let userShellPATH: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-ilc", "echo $PATH"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {}
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }()
}
