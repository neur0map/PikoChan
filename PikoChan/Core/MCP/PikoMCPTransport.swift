import Foundation

/// JSON-RPC 2.0 stdio transport for a single MCP server process.
/// Follows PikoTerminal (Process+Pipe, user PATH) and PikoVoiceServer
/// (generation counter, crash recovery, SIGTERM->SIGKILL) patterns.
@MainActor
final class PikoMCPTransport {

    let config: PikoMCPServerConfig
    var status: PikoMCPServerStatus = .stopped
    var tools: [PikoMCPTool] = []

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var requestID = 0
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], any Error>] = [:]
    private var readBuffer = Data()
    private var generation = 0
    private var retryCount = 0
    private var stderrLines: [String] = []

    private static let maxRetries = 3
    private static let toolCallTimeout: Duration = .seconds(30)
    private static let maxStderrLines = 50

    init(config: PikoMCPServerConfig) {
        self.config = config
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard status != .ready && status != .starting else { return }
        status = .starting
        generation += 1
        let currentGen = generation

        PikoGateway.shared.logMCPServerStart(name: config.name, command: config.command)

        let proc = Process()
        let resolvedCommand = resolveCommand(config.command)
        proc.executableURL = URL(fileURLWithPath: resolvedCommand)
        proc.arguments = config.args
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        // Merge user PATH + server-specific env.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.userShellPATH
        for (k, v) in config.env {
            env[k] = v
        }
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.process = proc
        self.readBuffer = Data()
        self.stderrLines = []

        // Stderr collection.
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGen else { return }
                self.stderrLines.append(contentsOf: line.components(separatedBy: "\n").filter { !$0.isEmpty })
                if self.stderrLines.count > Self.maxStderrLines {
                    self.stderrLines = Array(self.stderrLines.suffix(Self.maxStderrLines))
                }
            }
        }

        // Stdout — buffer and split JSON-RPC messages on newlines.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGen else { return }
                self.readBuffer.append(data)
                self.processReadBuffer()
            }
        }

        // Crash detection.
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGen else { return }
                let reason = self.stderrLines.suffix(3).joined(separator: "\n")
                self.status = .errored(reason.isEmpty ? "Process exited unexpectedly" : reason)
                self.failAllPending(error: MCPError.serverCrashed(reason))
                PikoGateway.shared.logMCPServerError(name: self.config.name, error: reason)
            }
        }

        do {
            try proc.run()
        } catch {
            status = .errored("Failed to launch: \(error.localizedDescription)")
            throw MCPError.launchFailed(error.localizedDescription)
        }

        // MCP handshake: initialize -> initialized notification -> tools/list
        do {
            let initResult = try await sendRequest(
                method: "initialize",
                params: [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [String: Any](),
                    "clientInfo": [
                        "name": "PikoChan",
                        "version": "0.5.6-alpha",
                    ],
                ]
            )
            _ = initResult // Server capabilities — we don't use them yet.

            // Send initialized notification (no response expected).
            sendNotification(method: "notifications/initialized", params: [:])

            // Discover tools.
            let toolsResult = try await sendRequest(method: "tools/list", params: [:])
            if let toolsList = toolsResult["tools"] as? [[String: Any]] {
                self.tools = toolsList.compactMap { parseTool($0) }
            }

            status = .ready
            retryCount = 0
            PikoGateway.shared.logMCPServerReady(name: config.name, toolCount: tools.count)
        } catch {
            stop()
            status = .errored("Handshake failed: \(error.localizedDescription)")
            throw error
        }
    }

    func stop() {
        generation += 1
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            // SIGKILL after 3 seconds if still alive.
            let capturedProc = proc
            Task {
                try? await Task.sleep(for: .seconds(3))
                if capturedProc.isRunning {
                    capturedProc.interrupt() // SIGINT
                    try? await Task.sleep(for: .seconds(1))
                    if capturedProc.isRunning {
                        kill(capturedProc.processIdentifier, SIGKILL)
                    }
                }
            }
        }

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        tools = []
        failAllPending(error: MCPError.serverStopped)
        status = .stopped
        PikoGateway.shared.logMCPServerStop(name: config.name)
    }

    // MARK: - Tool Calls

    func callTool(name: String, arguments: [String: Any]) async throws -> PikoMCPToolResult {
        if status != .ready {
            // Lazy restart.
            try await start()
        }

        let startTime = DispatchTime.now()
        PikoGateway.shared.logMCPToolCall(server: config.name, tool: name)

        let result: [String: Any]
        do {
            result = try await callToolWithTimeout(name: name, arguments: arguments)
        } catch {
            let durationMs = Self.elapsed(since: startTime)
            PikoGateway.shared.logMCPToolResult(
                server: config.name, tool: name,
                durationMs: durationMs, isError: true
            )
            throw error
        }

        let durationMs = Self.elapsed(since: startTime)
        let content = extractContent(from: result)
        let isError = result["isError"] as? Bool ?? false

        PikoGateway.shared.logMCPToolResult(
            server: config.name, tool: name,
            durationMs: durationMs, isError: isError
        )

        return PikoMCPToolResult(content: content, isError: isError)
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        requestID += 1
        let id = requestID

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let line = String(data: data, encoding: .utf8) else {
            throw MCPError.serializationFailed
        }

        let fullLine = line + "\n"
        guard let lineData = fullLine.data(using: .utf8) else {
            throw MCPError.serializationFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            stdinPipe?.fileHandleForWriting.write(lineData)
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }
        stdinPipe?.fileHandleForWriting.write(lineData)
    }

    // MARK: - Buffer Processing

    private func processReadBuffer() {
        // Split on newlines — each line is a JSON-RPC message.
        while let newlineIdx = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer[readBuffer.startIndex..<newlineIdx]
            readBuffer = Data(readBuffer[(newlineIdx + 1)...])

            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            handleMessage(json)
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        // Response to a request (has "id" and "result" or "error").
        if let id = json["id"] as? Int {
            if let continuation = pendingRequests.removeValue(forKey: id) {
                if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    let code = error["code"] as? Int ?? -1
                    continuation.resume(throwing: MCPError.rpcError(code: code, message: message))
                } else if let result = json["result"] as? [String: Any] {
                    continuation.resume(returning: result)
                } else {
                    // Some servers return empty result for success.
                    continuation.resume(returning: [:])
                }
            }
            return
        }

        // Notification from server (no "id") — ignore for now.
        // Could handle things like resource updates, log messages, etc.
    }

    // MARK: - Helpers

    private func parseTool(_ json: [String: Any]) -> PikoMCPTool? {
        guard let name = json["name"] as? String else { return nil }
        let description = json["description"] as? String ?? ""
        let inputSchema = json["inputSchema"] as? [String: Any] ?? [:]
        return PikoMCPTool(
            serverName: config.name,
            name: name,
            description: description,
            inputSchema: inputSchema
        )
    }

    private func extractContent(from result: [String: Any]) -> String {
        // MCP tool results have "content" array of {type, text} objects.
        guard let contentArray = result["content"] as? [[String: Any]] else {
            // Fallback: try to serialize the entire result.
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return ""
        }

        return contentArray.compactMap { item -> String? in
            if let text = item["text"] as? String { return text }
            if let data = try? JSONSerialization.data(withJSONObject: item, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { return str }
            return nil
        }.joined(separator: "\n")
    }

    private func failAllPending(error: any Error) {
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }

    private func resolveCommand(_ command: String) -> String {
        // If it's an absolute path, use as-is.
        if command.hasPrefix("/") { return command }

        // Common commands — resolve via PATH.
        let searchPaths = Self.userShellPATH.split(separator: ":").map(String.init)
        for dir in searchPaths {
            let fullPath = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        // Fallback: try /usr/bin/env to resolve.
        return "/usr/bin/env"
    }

    private func callToolWithTimeout(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let result = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments,
        ])
        return result
    }

    private static func elapsed(since start: DispatchTime) -> Int {
        let end = DispatchTime.now()
        return Int((end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    /// Resolve the user's full login-shell PATH.
    static let userShellPATH: String = {
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

// MARK: - Errors

enum MCPError: Error, LocalizedError {
    case launchFailed(String)
    case serializationFailed
    case rpcError(code: Int, message: String)
    case timeout
    case serverCrashed(String)
    case serverStopped
    case serverNotReady
    case toolNotFound(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let msg): "MCP server launch failed: \(msg)"
        case .serializationFailed: "Failed to serialize JSON-RPC message"
        case .rpcError(_, let msg): "MCP error: \(msg)"
        case .timeout: "MCP tool call timed out (30s)"
        case .serverCrashed(let msg): "MCP server crashed: \(msg)"
        case .serverStopped: "MCP server was stopped"
        case .serverNotReady: "MCP server is not ready"
        case .toolNotFound(let name): "MCP tool not found: \(name)"
        }
    }
}
