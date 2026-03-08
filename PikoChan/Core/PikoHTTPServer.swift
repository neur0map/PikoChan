import Foundation
import Network

/// Lightweight HTTP server using Network.framework (NWListener).
/// Shares PikoBrain with the notch UI — both clients see the same
/// history, memories, and config.
@MainActor
final class PikoHTTPServer {

    private let brain: PikoBrain
    private let port: UInt16
    private var listener: NWListener?
    private let gateway = PikoGateway.shared
    private let bootTime = Date.now
    private var requestCount = 0

    /// Callback to set the notch UI mood from HTTP (optional).
    var moodSetter: ((NotchManager.Mood) -> Void)?
    /// Set by AppDelegate so config commands can schedule nudges via HTTP too.
    var heartbeat: PikoHeartbeat?

    init(brain: PikoBrain, port: UInt16, moodSetter: ((NotchManager.Mood) -> Void)? = nil) {
        self.brain = brain
        self.port = port
        self.moodSetter = moodSetter
    }

    // MARK: - Lifecycle

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.gateway.logHTTPServerStart(port: self?.port ?? 0)
                    print("[PikoHTTPServer] Listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    self?.gateway.logError(
                        message: "HTTP server failed: \(error)",
                        subsystem: .http
                    )
                default:
                    break
                }
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveHTTP(on: connection, accumulated: Data())
    }

    private func receiveHTTP(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }

                // Bail immediately on error — prevents infinite loop on dead connections.
                if let error {
                    print("[PikoHTTPServer] Connection error: \(error)")
                    connection.cancel()
                    return
                }

                var buffer = accumulated
                if let content { buffer.append(content) }

                // Connection closed with no new data and nothing buffered — done.
                if content == nil && isComplete {
                    if !buffer.isEmpty, let headerEnd = self.findHeaderEnd(in: buffer) {
                        // Try to process whatever we have.
                        let headerData = buffer[..<headerEnd]
                        let bodyStart = buffer[headerEnd...]
                        if let headerString = String(data: headerData, encoding: .utf8) {
                            let request = self.parseRequest(headerString)
                            let contentLength = request.headers["content-length"].flatMap(Int.init) ?? 0
                            let body = contentLength > 0 ? Data(bodyStart.prefix(contentLength)) : nil
                            await self.route(request: request, body: body, connection: connection)
                            return
                        }
                    }
                    connection.cancel()
                    return
                }

                // Check if we have the full headers (double CRLF).
                if let headerEnd = self.findHeaderEnd(in: buffer) {
                    let headerData = buffer[..<headerEnd]
                    let bodyStart = buffer[headerEnd...]

                    guard let headerString = String(data: headerData, encoding: .utf8) else {
                        self.sendResponse(connection: connection, status: 400, body: "{\"error\":\"Bad request\"}")
                        return
                    }

                    let request = self.parseRequest(headerString)

                    // Check Content-Length for body.
                    let contentLength = request.headers["content-length"].flatMap(Int.init) ?? 0
                    if bodyStart.count >= contentLength {
                        let body = contentLength > 0 ? Data(bodyStart.prefix(contentLength)) : nil
                        await self.route(request: request, body: body, connection: connection)
                    } else if isComplete {
                        // Connection closed before full body — process what we have.
                        let body = bodyStart.isEmpty ? nil : Data(bodyStart)
                        await self.route(request: request, body: body, connection: connection)
                    } else {
                        // Need more body data.
                        self.receiveHTTP(on: connection, accumulated: buffer)
                    }
                } else if buffer.count > 1_000_000 {
                    // Header too large.
                    self.sendResponse(connection: connection, status: 413, body: "{\"error\":\"Request too large\"}")
                } else if isComplete {
                    // Connection closed before full headers.
                    connection.cancel()
                } else {
                    // Need more header data.
                    self.receiveHTTP(on: connection, accumulated: buffer)
                }
            }
        }
    }

    private func findHeaderEnd(in data: Data) -> Data.Index? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        guard data.count >= 4 else { return nil }
        for i in data.startIndex...(data.endIndex - 4) {
            if data[i] == separator[0] &&
               data[i+1] == separator[1] &&
               data[i+2] == separator[2] &&
               data[i+3] == separator[3] {
                return i + 4
            }
        }
        return nil
    }

    // MARK: - Request Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let queryParams: [String: String]
        let headers: [String: String]
    }

    private func parseRequest(_ raw: String) -> HTTPRequest {
        let lines = raw.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ", maxSplits: 2)

        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let rawPath = parts.count > 1 ? String(parts[1]) : "/"

        // Split path and query string.
        let (path, queryParams): (String, [String: String]) = {
            guard let qIdx = rawPath.firstIndex(of: "?") else {
                return (rawPath, [:])
            }
            let p = String(rawPath[..<qIdx])
            let qString = String(rawPath[rawPath.index(after: qIdx)...])
            var params: [String: String] = [:]
            for pair in qString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    params[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
            return (p, params)
        }()

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return HTTPRequest(method: method, path: path, queryParams: queryParams, headers: headers)
    }

    // MARK: - Routing

    private func route(request: HTTPRequest, body: Data?, connection: NWConnection) async {
        let start = Date.now
        requestCount += 1
        gateway.logHTTPRequest(method: request.method, path: request.path, remoteAddress: nil)

        // CORS preflight.
        if request.method == "OPTIONS" {
            sendResponse(connection: connection, status: 204, body: "", extraHeaders: corsHeaders())
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            handleHealth(connection: connection)
        case ("POST", "/chat"):
            await handleChat(body: body, connection: connection)
        case ("GET", "/history"):
            handleHistory(request: request, connection: connection)
        case ("GET", "/logs"):
            handleLogs(request: request, connection: connection)
        case ("GET", "/memories"):
            handleMemories(request: request, connection: connection)
        case ("GET", "/config"):
            handleConfig(connection: connection)
        case ("POST", "/mood"):
            handleSetMood(body: body, connection: connection)
        default:
            sendJSON(connection: connection, status: 404, json: ["error": "Not found"])
        }

        let durationMs = Int(Date.now.timeIntervalSince(start) * 1000)
        gateway.logHTTPResponse(method: request.method, path: request.path, status: 200, durationMs: durationMs)
    }

    // MARK: - Handlers

    private func handleHealth(connection: NWConnection) {
        let uptimeSeconds = Int(Date.now.timeIntervalSince(bootTime))
        let json: [String: Any] = [
            "status": "ok",
            "provider": brain.config.provider.rawValue,
            "model": activeModelName,
            "uptime_seconds": uptimeSeconds,
            "history_count": brain.history.count,
            "memory_count": brain.store?.memoryCount() ?? 0,
            "request_count": requestCount,
        ]
        sendJSON(connection: connection, status: 200, json: json)
    }

    private func handleChat(body: Data?, connection: NWConnection) async {
        guard let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let prompt = json["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            sendJSON(connection: connection, status: 400, json: ["error": "Missing 'prompt' in request body"])
            return
        }

        let moodString = json["mood"] as? String ?? "neutral"
        let mood = NotchManager.Mood.allCases.first { $0.rawValue.lowercased() == moodString.lowercased() } ?? .neutral
        let stream = json["stream"] as? Bool ?? false

        gateway.logHTTPChatRequest(prompt: prompt, stream: stream)

        if stream {
            await handleStreamingChat(prompt: prompt, mood: mood, connection: connection)
        } else {
            await handleNonStreamingChat(prompt: prompt, mood: mood, connection: connection)
        }
    }

    private func handleNonStreamingChat(prompt: String, mood: NotchManager.Mood, connection: NWConnection) async {
        brain.reloadConfig()

        var fullResponse = ""
        var moodParsed: NotchManager.Mood?

        for await chunk in brain.respondStreaming(to: prompt, mood: mood) {
            fullResponse += chunk
        }

        if !fullResponse.isEmpty {
            let (parsed, clean) = MoodParser.parse(from: fullResponse)
            moodParsed = parsed
            fullResponse = clean
        }

        // Parse config commands + scheduled nudges from response.
        if !fullResponse.isEmpty {
            let cmdResult = PikoConfigCommand.parse(from: fullResponse)
            fullResponse = cmdResult.cleanText
            PikoConfigCommand.applyConfigChanges(cmdResult.configChanges)
            if let nudge = cmdResult.scheduledNudge {
                self.heartbeat?.scheduleNudge(
                    afterSeconds: nudge.delaySeconds,
                    message: nudge.message
                )
            }
        }

        let json: [String: Any] = [
            "response": fullResponse,
            "mood": (moodParsed ?? mood).rawValue.lowercased(),
            "provider": brain.config.provider.rawValue,
            "model": activeModelName,
        ]
        sendJSON(connection: connection, status: 200, json: json)
    }

    private func handleStreamingChat(prompt: String, mood: NotchManager.Mood, connection: NWConnection) async {
        brain.reloadConfig()

        // Send SSE headers.
        let headers = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/event-stream\r\n" +
            "Cache-Control: no-cache\r\n" +
            "Connection: close\r\n" +
            corsHeaderString() +
            "\r\n"

        let headerData = Data(headers.utf8)
        connection.send(content: headerData, completion: .contentProcessed { _ in })

        var fullResponse = ""
        var moodParsed = false
        var rawAccumulated = ""
        var detectedMood: NotchManager.Mood?

        for await chunk in brain.respondStreaming(to: prompt, mood: mood) {
            rawAccumulated += chunk

            // Parse mood tag once.
            if !moodParsed && rawAccumulated.contains("]") {
                let (parsed, cleanText) = MoodParser.parse(from: rawAccumulated)
                detectedMood = parsed
                moodParsed = true
                fullResponse = cleanText
                sendSSEChunk(connection: connection, chunk: cleanText, done: false)
            } else if moodParsed {
                fullResponse += chunk
                sendSSEChunk(connection: connection, chunk: chunk, done: false)
            }
            // While mood tag not yet parsed, buffer without sending.
        }

        // If mood was never parsed, send everything.
        if !moodParsed && !rawAccumulated.isEmpty {
            fullResponse = rawAccumulated
            sendSSEChunk(connection: connection, chunk: rawAccumulated, done: false)
        }

        // Parse config commands + scheduled nudges from response.
        if !fullResponse.isEmpty {
            let cmdResult = PikoConfigCommand.parse(from: fullResponse)
            fullResponse = cmdResult.cleanText
            PikoConfigCommand.applyConfigChanges(cmdResult.configChanges)
            if let nudge = cmdResult.scheduledNudge {
                self.heartbeat?.scheduleNudge(
                    afterSeconds: nudge.delaySeconds,
                    message: nudge.message
                )
            }
        }

        // Final done event.
        let finalMood = (detectedMood ?? mood).rawValue.lowercased()
        let doneJSON: [String: Any] = [
            "chunk": "",
            "done": true,
            "mood": finalMood,
            "full_response": fullResponse,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: doneJSON),
           let str = String(data: data, encoding: .utf8) {
            let event = "data: \(str)\n\n"
            connection.send(content: Data(event.utf8), completion: .contentProcessed { _ in })
        }

        // Close connection after final SSE event.
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendSSEChunk(connection: NWConnection, chunk: String, done: Bool) {
        let json: [String: Any] = ["chunk": chunk, "done": done]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let str = String(data: data, encoding: .utf8) else { return }
        let event = "data: \(str)\n\n"
        connection.send(content: Data(event.utf8), completion: .contentProcessed { _ in })
    }

    private func handleHistory(request: HTTPRequest, connection: NWConnection) {
        let limit = request.queryParams["limit"].flatMap(Int.init) ?? 20
        let turns = brain.history.suffix(limit).map { turn -> [String: Any] in
            let (_, clean) = MoodParser.parse(from: turn.assistant)
            return [
                "user": turn.user,
                "assistant": clean,
                "mood": turn.mood ?? "neutral",
                "at": ISO8601DateFormatter().string(from: turn.at),
            ]
        }
        sendJSON(connection: connection, status: 200, json: ["turns": turns, "count": turns.count])
    }

    private func handleLogs(request: HTTPRequest, connection: NWConnection) {
        let limit = request.queryParams["limit"].flatMap(Int.init) ?? 50
        let lines = gateway.tailLog(lines: limit)
        // Parse each JSONL line back into objects for clean JSON output.
        let entries: [Any] = lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        sendJSON(connection: connection, status: 200, json: [
            "entries": entries,
            "count": entries.count,
            "log_file": gateway.todayLogFile?.lastPathComponent ?? "none",
        ])
    }

    private func handleMemories(request: HTTPRequest, connection: NWConnection) {
        let limit = request.queryParams["limit"].flatMap(Int.init) ?? 50
        let memories = brain.store?.recentMemories(limit: limit) ?? []
        sendJSON(connection: connection, status: 200, json: [
            "memories": memories,
            "count": memories.count,
        ])
    }

    private func handleConfig(connection: NWConnection) {
        let json: [String: Any] = [
            "provider": brain.config.provider.rawValue,
            "model": activeModelName,
            "local_endpoint": brain.config.localEndpoint.absoluteString,
            "cloud_fallback": brain.config.cloudFallback.rawValue,
            "gateway_port": port,
            "soul_name": brain.soul.name,
        ]
        sendJSON(connection: connection, status: 200, json: json)
    }

    private func handleSetMood(body: Data?, connection: NWConnection) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let moodString = json["mood"] as? String
        else {
            sendJSON(connection: connection, status: 400, json: ["error": "Missing 'mood' in request body"])
            return
        }

        guard let mood = NotchManager.Mood.allCases.first(where: { $0.rawValue.lowercased() == moodString.lowercased() }) else {
            let validMoods = NotchManager.Mood.allCases.map { $0.rawValue.lowercased() }
            sendJSON(connection: connection, status: 400, json: [
                "error": "Invalid mood",
                "valid_moods": validMoods,
            ])
            return
        }

        moodSetter?(mood)
        sendJSON(connection: connection, status: 200, json: [
            "mood": mood.rawValue.lowercased(),
            "message": "Mood set to \(mood.rawValue)",
        ])
    }

    // MARK: - Response Helpers

    private func sendJSON(connection: NWConnection, status: Int, json: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            sendResponse(connection: connection, status: 500, body: "{\"error\":\"Serialization failed\"}")
            return
        }
        sendResponse(connection: connection, status: status, body: jsonString,
                     extraHeaders: ["Content-Type: application/json"] + corsHeaders())
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String, extraHeaders: [String] = []) {
        let statusText: String = switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        default: "Unknown"
        }

        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Content-Length: \(body.utf8.count)\r\n"
        response += "Connection: close\r\n"
        for header in extraHeaders {
            response += "\(header)\r\n"
        }
        response += "\r\n"
        response += body

        connection.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func corsHeaders() -> [String] {
        [
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
        ]
    }

    private func corsHeaderString() -> String {
        corsHeaders().map { $0 + "\r\n" }.joined()
    }

    private var activeModelName: String {
        switch brain.config.provider {
        case .local:              brain.config.localModel
        case .openai:             brain.config.openAIModel
        case .anthropic:          brain.config.anthropicModel
        case .apple:              "apple-intelligence"
        case .openrouter:         brain.config.openRouterModel
        case .groq:               brain.config.groqModel
        case .huggingface:        brain.config.huggingFaceModel
        case .dockerModelRunner:  brain.config.dockerModelRunnerModel
        case .vllm:               brain.config.vllmModel
        }
    }
}
