import Foundation

/// Central message gateway inspired by OpenClaw's gateway pattern.
/// All PikoBrain operations flow through here. Logs every event as structured
/// JSONL to `~/.pikochan/logs/YYYY-MM-DD.jsonl`.
///
/// Event types: boot, user_message, assistant_response, assistant_stream_start,
/// assistant_stream_end, memory_recall, memory_extract, mood_change,
/// config_reload, error, internal_llm_call.
@MainActor
final class PikoGateway {

    static let shared = PikoGateway()

    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [] // compact single-line JSON
        return e
    }()

    private var logsDir: URL?
    private var currentFileHandle: FileHandle?
    private var currentLogDate: String?

    /// Max age for log files before auto-prune (7 days).
    private static let maxLogAgeDays = 7
    /// Max file size before rotating (50 MB).
    private static let maxFileSizeBytes: UInt64 = 50 * 1024 * 1024

    // MARK: - Setup

    func configure(logsDir: URL) {
        self.logsDir = logsDir
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        pruneOldLogs()
    }

    // MARK: - Event Types

    enum EventType: String, Encodable {
        case boot
        case userMessage = "user_message"
        case assistantResponse = "assistant_response"
        case assistantStreamStart = "assistant_stream_start"
        case assistantStreamEnd = "assistant_stream_end"
        case memoryRecall = "memory_recall"
        case memoryExtract = "memory_extract"
        case memorySave = "memory_save"
        case moodChange = "mood_change"
        case configReload = "config_reload"
        case error
        case internalLLMCall = "internal_llm_call"
        case httpServerStart = "http_server_start"
        case httpRequest = "http_request"
        case httpResponse = "http_response"
        case httpChatRequest = "http_chat_request"
        case soulEvolution = "soul_evolution"
        case extractionSkip = "extraction_skip"
        case heartbeatTick = "heartbeat_tick"
        case heartbeatNudge = "heartbeat_nudge"
        case heartbeatMoodShift = "heartbeat_mood_shift"
        case ttsStart = "tts_start"
        case ttsEnd = "tts_end"
        case sttStart = "stt_start"
        case sttEnd = "stt_end"
    }

    enum Subsystem: String, Encodable {
        case brain
        case memory
        case mood
        case gateway
        case config
        case ui
        case http
        case heartbeat
        case voice
    }

    // MARK: - Log Events

    func logBoot(provider: String, model: String, historyCount: Int, memoryCount: Int) {
        log(
            type: .boot,
            subsystem: .gateway,
            data: [
                "provider": provider,
                "model": model,
                "history_loaded": String(historyCount),
                "memories_loaded": String(memoryCount),
            ]
        )
    }

    func logUserMessage(_ message: String, mood: String) {
        log(
            type: .userMessage,
            subsystem: .ui,
            data: [
                "message": message,
                "mood": mood,
            ]
        )
    }

    func logAssistantResponse(
        message: String,
        provider: String,
        model: String,
        mood: String,
        durationMs: Int,
        streaming: Bool
    ) {
        log(
            type: .assistantResponse,
            subsystem: .brain,
            data: [
                "message": truncate(message, max: 2000),
                "provider": provider,
                "model": model,
                "mood": mood,
                "duration_ms": String(durationMs),
                "streaming": String(streaming),
            ]
        )
    }

    func logStreamStart(provider: String, model: String) {
        log(
            type: .assistantStreamStart,
            subsystem: .brain,
            data: [
                "provider": provider,
                "model": model,
            ]
        )
    }

    func logStreamEnd(charCount: Int, durationMs: Int, mood: String?) {
        log(
            type: .assistantStreamEnd,
            subsystem: .brain,
            data: [
                "chars": String(charCount),
                "duration_ms": String(durationMs),
                "detected_mood": mood ?? "none",
            ]
        )
    }

    func logMemoryRecall(query: String, recalled: [String]) {
        log(
            type: .memoryRecall,
            subsystem: .memory,
            data: [
                "query": truncate(query, max: 500),
                "count": String(recalled.count),
                "facts": recalled.prefix(5).joined(separator: " | "),
            ]
        )
    }

    func logMemoryExtract(userMessage: String, facts: [String]) {
        log(
            type: .memoryExtract,
            subsystem: .memory,
            data: [
                "source": truncate(userMessage, max: 500),
                "facts": facts.joined(separator: " | "),
                "count": String(facts.count),
            ]
        )
    }

    func logMemorySave(fact: String, turnId: Int?) {
        log(
            type: .memorySave,
            subsystem: .memory,
            data: [
                "fact": fact,
                "turn_id": turnId.map(String.init) ?? "nil",
            ]
        )
    }

    func logMoodChange(from: String, to: String, trigger: String) {
        log(
            type: .moodChange,
            subsystem: .mood,
            data: [
                "from": from,
                "to": to,
                "trigger": trigger,
            ]
        )
    }

    func logConfigReload(provider: String, model: String) {
        log(
            type: .configReload,
            subsystem: .config,
            data: [
                "provider": provider,
                "model": model,
            ]
        )
    }

    func logError(message: String, subsystem: Subsystem = .brain, detail: String? = nil) {
        var data = ["message": message]
        if let detail { data["detail"] = detail }
        log(type: .error, subsystem: subsystem, data: data)
    }

    func logInternalLLMCall(purpose: String, promptChars: Int, responseChars: Int, durationMs: Int) {
        log(
            type: .internalLLMCall,
            subsystem: .memory,
            data: [
                "purpose": purpose,
                "prompt_chars": String(promptChars),
                "response_chars": String(responseChars),
                "duration_ms": String(durationMs),
            ]
        )
    }

    func logSoulEvolution(rules: [String], trigger: String) {
        log(
            type: .soulEvolution,
            subsystem: .brain,
            data: [
                "rules_added": rules.joined(separator: " | "),
                "count": String(rules.count),
                "trigger": truncate(trigger, max: 500),
            ]
        )
    }

    func logExtractionSkip(reason: String, userChars: Int, assistantChars: Int) {
        log(
            type: .extractionSkip,
            subsystem: .memory,
            data: [
                "reason": reason,
                "user_chars": String(userChars),
                "assistant_chars": String(assistantChars),
            ]
        )
    }

    // MARK: - HTTP Events

    func logHTTPServerStart(port: UInt16) {
        log(type: .httpServerStart, subsystem: .http, data: ["port": String(port)])
    }

    func logHTTPRequest(method: String, path: String, remoteAddress: String?) {
        var data = ["method": method, "path": path]
        if let addr = remoteAddress { data["remote"] = addr }
        log(type: .httpRequest, subsystem: .http, data: data)
    }

    func logHTTPResponse(method: String, path: String, status: Int, durationMs: Int) {
        log(type: .httpResponse, subsystem: .http, data: [
            "method": method,
            "path": path,
            "status": String(status),
            "duration_ms": String(durationMs),
        ])
    }

    func logHTTPChatRequest(prompt: String, stream: Bool) {
        log(type: .httpChatRequest, subsystem: .http, data: [
            "prompt": truncate(prompt, max: 500),
            "stream": String(stream),
        ])
    }

    // MARK: - Heartbeat Events

    func logHeartbeatTick(app: String, idleSeconds: Int, timeOfDay: Int) {
        log(type: .heartbeatTick, subsystem: .heartbeat, data: [
            "app": app,
            "idle_seconds": String(idleSeconds),
            "time_of_day": String(timeOfDay),
        ])
    }

    func logHeartbeatNudge(trigger: String, message: String, app: String) {
        log(type: .heartbeatNudge, subsystem: .heartbeat, data: [
            "trigger": trigger,
            "message": truncate(message, max: 500),
            "app": app,
        ])
    }

    func logHeartbeatMoodShift(from: String, to: String, trigger: String) {
        log(type: .heartbeatMoodShift, subsystem: .heartbeat, data: [
            "from": from,
            "to": to,
            "trigger": trigger,
        ])
    }

    // MARK: - Voice Events

    func logTTSStart(provider: String, textChars: Int) {
        log(type: .ttsStart, subsystem: .voice, data: [
            "provider": provider,
            "text_chars": String(textChars),
        ])
    }

    func logTTSEnd(provider: String, durationMs: Int, audioBytes: Int) {
        log(type: .ttsEnd, subsystem: .voice, data: [
            "provider": provider,
            "duration_ms": String(durationMs),
            "audio_bytes": String(audioBytes),
        ])
    }

    func logSTTStart(provider: String, audioBytes: Int) {
        log(type: .sttStart, subsystem: .voice, data: [
            "provider": provider,
            "audio_bytes": String(audioBytes),
        ])
    }

    func logSTTEnd(provider: String, durationMs: Int, transcript: String) {
        log(type: .sttEnd, subsystem: .voice, data: [
            "provider": provider,
            "duration_ms": String(durationMs),
            "transcript": truncate(transcript, max: 500),
        ])
    }

    // MARK: - Log Reading

    /// Returns today's log file URL.
    var todayLogFile: URL? {
        guard let logsDir else { return nil }
        return logsDir.appendingPathComponent("\(Self.dateString()).jsonl")
    }

    /// Returns all log file URLs sorted newest first.
    func allLogFiles() -> [URL] {
        guard let logsDir else { return [] }
        let files = (try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Reads the last N lines from today's log.
    func tailLog(lines: Int = 100) -> [String] {
        guard let file = todayLogFile,
              let data = try? String(contentsOf: file, encoding: .utf8)
        else { return [] }

        let allLines = data.components(separatedBy: "\n").filter { !$0.isEmpty }
        return Array(allLines.suffix(lines))
    }

    /// Total log entry count for today.
    func todayEntryCount() -> Int {
        guard let file = todayLogFile,
              let data = try? String(contentsOf: file, encoding: .utf8)
        else { return 0 }
        return data.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    // MARK: - Private

    private struct LogEntry: Encodable {
        let time: String
        let type: EventType
        let subsystem: Subsystem
        let data: [String: String]
    }

    private func log(type: EventType, subsystem: Subsystem, data: [String: String]) {
        let entry = LogEntry(
            time: Self.iso8601Now(),
            type: type,
            subsystem: subsystem,
            data: data
        )

        guard let jsonData = try? encoder.encode(entry),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return }

        let line = jsonString + "\n"
        writeToFile(line)
    }

    private func writeToFile(_ line: String) {
        guard let logsDir else { return }

        let today = Self.dateString()

        // Rotate if date changed.
        if today != currentLogDate {
            currentFileHandle?.closeFile()
            currentFileHandle = nil
            currentLogDate = today
        }

        let filePath = logsDir.appendingPathComponent("\(today).jsonl")

        // Check size cap.
        if let attrs = try? fm.attributesOfItem(atPath: filePath.path),
           let size = attrs[.size] as? UInt64,
           size >= Self.maxFileSizeBytes {
            return // File too large, skip write.
        }

        if currentFileHandle == nil {
            if !fm.fileExists(atPath: filePath.path) {
                fm.createFile(atPath: filePath.path, contents: nil)
            }
            currentFileHandle = try? FileHandle(forWritingTo: filePath)
            currentFileHandle?.seekToEndOfFile()
        }

        if let data = line.data(using: .utf8) {
            currentFileHandle?.write(data)
        }
    }

    private func pruneOldLogs() {
        guard let logsDir else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(Self.maxLogAgeDays) * 86400)
        let files = (try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []

        for file in files where file.pathExtension == "jsonl" {
            guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = attrs.contentModificationDate,
                  modified < cutoff
            else { continue }
            try? fm.removeItem(at: file)
        }
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    private static func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: .now)
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "..." : s
    }

    deinit {
        currentFileHandle?.closeFile()
    }
}
