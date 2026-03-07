import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ChatTurn {
    let user: String
    let assistant: String
    let at: Date
    let mood: String?

    init(user: String, assistant: String, at: Date, mood: String? = nil) {
        self.user = user
        self.assistant = assistant
        self.at = at
        self.mood = mood
    }
}

// MARK: - Codable Response Types

private struct OllamaResponse: Codable {
    let response: String
}

private struct OllamaStreamChunk: Codable {
    let response: String
    let done: Bool
}

private struct OllamaChatResponse: Codable {
    let message: OllamaChatMessage
}

private struct OllamaChatStreamChunk: Codable {
    let message: OllamaChatMessage
    let done: Bool
}

private struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Codable {
    let choices: [Choice]
    let usage: OpenAIUsage?
    struct Choice: Codable {
        let message: Message
    }
    struct Message: Codable {
        let content: String
    }
}

private struct OpenAIUsage: Codable {
    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int?
}

private struct OpenAIStreamChunk: Codable {
    let choices: [Choice]
    struct Choice: Codable {
        let delta: Delta
    }
    struct Delta: Codable {
        let content: String?
    }
}

private struct AnthropicResponse: Codable {
    let content: [ContentBlock]
    struct ContentBlock: Codable {
        let text: String
    }
}

private struct AnthropicStreamEvent: Codable {
    let type: String
    let delta: Delta?
    struct Delta: Codable {
        let type: String?
        let text: String?
    }
}

private struct APIErrorResponse: Codable {
    let error: APIErrorBody?
    struct APIErrorBody: Codable {
        let message: String?
        let type: String?
    }
}

// MARK: - PikoBrain

@MainActor
final class PikoBrain {
    let home: PikoHome
    private(set) var config: PikoConfig
    private(set) var soul: PikoSoul
    private(set) var history: [ChatTurn] = []
    private(set) var store: PikoStore?
    private let memory = PikoMemory()

    static let maxHistoryTurns = 50
    static let contextWindowTurns = 20

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg)
    }()

    init() {
        self.home = PikoHome()
        self.config = .default
        self.soul = .default
    }

    init(home: PikoHome) {
        self.home = home
        self.config = .default
        self.soul = .default
    }

    private let gateway = PikoGateway.shared

    func bootstrap() throws {
        try home.bootstrap()
        gateway.configure(logsDir: home.logsDir)
        reloadConfig()
        store = PikoStore(path: home.memoryDBFile)
        if let store {
            history = store.recentTurns(limit: Self.maxHistoryTurns)
        }
        gateway.logBoot(
            provider: config.provider.rawValue,
            model: activeModelName,
            historyCount: history.count,
            memoryCount: store?.memoryCount() ?? 0
        )

        // Auto-maintenance: rotate journal, prune old chat turns.
        PikoMaintenance.runAll(home: home, store: store)
    }

    func reloadConfig() {
        config = PikoConfigLoader.load(from: home.configFile)
        soul = PikoSoul.load(from: home.personalityFile)
        gateway.logConfigReload(provider: config.provider.rawValue, model: activeModelName)
    }

    // MARK: - Full Response (non-streaming)

    /// Internal-only flag combo: `skipHistory` + `skipMemoryExtraction` lets
    /// memory-extraction calls use the LLM without polluting chat history.
    func respond(
        to prompt: String,
        mood: NotchManager.Mood = .neutral,
        skipMemoryExtraction: Bool = false,
        skipHistory: Bool = false
    ) async throws -> String {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }

        let start = Date.now
        let response: String
        do {
            switch config.provider {
            case .local:
                do {
                    response = try await localGenerate(prompt: clean, mood: mood)
                } catch {
                    if let fallback = try await cloudFallbackResponse(prompt: clean, mood: mood) {
                        if !skipHistory {
                            appendHistory(user: clean, assistant: fallback, mood: mood.rawValue, extractMemory: !skipMemoryExtraction)
                        }
                        return fallback
                    }
                    throw error
                }
            case .openai:
                guard let key = config.openAIAPIKey, !key.isEmpty else {
                    throw PikoBrainError.missingCloudCredentials("No API key configured")
                }
                response = try await openAIGenerate(prompt: clean, apiKey: key, model: config.openAIModel, mood: mood)
            case .anthropic:
                guard let key = config.anthropicAPIKey, !key.isEmpty else {
                    throw PikoBrainError.missingCloudCredentials("No API key configured")
                }
                response = try await anthropicGenerate(prompt: clean, apiKey: key, model: config.anthropicModel, mood: mood)
            case .apple:
                guard let text = await generateWithFoundationModels(prompt: clean, mood: mood), !text.isEmpty else {
                    throw PikoBrainError.appleIntelligenceUnavailable
                }
                response = text
            case .openrouter, .groq, .huggingface, .dockerModelRunner, .vllm:
                let (baseURL, apiKey, model) = try openAICompatibleConfig()
                response = try await openAICompatibleGenerate(baseURL: baseURL, apiKey: apiKey, model: model, prompt: clean, mood: mood)
            }
        } catch {
            gateway.logError(
                message: error.localizedDescription,
                subsystem: .brain,
                detail: "prompt=\(String(clean.prefix(200)))"
            )
            throw error
        }

        let durationMs = Int(Date.now.timeIntervalSince(start) * 1000)
        gateway.logAssistantResponse(
            message: response,
            provider: config.provider.rawValue,
            model: activeModelName,
            mood: mood.rawValue,
            durationMs: durationMs,
            streaming: false
        )

        if !skipHistory {
            appendHistory(user: clean, assistant: response, mood: mood.rawValue, extractMemory: !skipMemoryExtraction)
        }
        return response
    }

    // MARK: - Streaming Response

    func respondStreaming(to prompt: String, mood: NotchManager.Mood = .neutral, skipHistory: Bool = false) -> AsyncStream<String> {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return AsyncStream { $0.finish() }
        }

        let cfg = config
        return AsyncStream { continuation in
            Task {
                let streamStart = Date.now
                self.gateway.logStreamStart(provider: cfg.provider.rawValue, model: self.activeModelName)
                var fullResponse = ""
                do {
                    switch cfg.provider {
                    case .local:
                        do {
                            for try await chunk in self.localStreamGenerate(prompt: clean, mood: mood) {
                                try Task.checkCancellation()
                                fullResponse += chunk
                                continuation.yield(chunk)
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            if let key = cfg.openAIAPIKey ?? cfg.anthropicAPIKey,
                               !key.isEmpty,
                               cfg.cloudFallback != .none {
                                let fallback = try await self.cloudFallbackResponse(prompt: clean, mood: mood)
                                if let fallback {
                                    fullResponse = fallback
                                    continuation.yield(fallback)
                                } else {
                                    throw error
                                }
                            } else {
                                throw error
                            }
                        }
                    case .openai:
                        guard let key = cfg.openAIAPIKey, !key.isEmpty else {
                            throw PikoBrainError.missingCloudCredentials("No API key configured")
                        }
                        for try await chunk in self.openAIStreamGenerate(prompt: clean, apiKey: key, model: cfg.openAIModel, mood: mood) {
                            try Task.checkCancellation()
                            fullResponse += chunk
                            continuation.yield(chunk)
                        }
                    case .anthropic:
                        guard let key = cfg.anthropicAPIKey, !key.isEmpty else {
                            throw PikoBrainError.missingCloudCredentials("No API key configured")
                        }
                        for try await chunk in self.anthropicStreamGenerate(prompt: clean, apiKey: key, model: cfg.anthropicModel, mood: mood) {
                            try Task.checkCancellation()
                            fullResponse += chunk
                            continuation.yield(chunk)
                        }
                    case .apple:
                        guard let text = await self.generateWithFoundationModels(prompt: clean, mood: mood), !text.isEmpty else {
                            throw PikoBrainError.appleIntelligenceUnavailable
                        }
                        // Simulate streaming character-by-character.
                        for char in text {
                            try Task.checkCancellation()
                            let s = String(char)
                            fullResponse += s
                            continuation.yield(s)
                            try await Task.sleep(for: .milliseconds(15))
                        }
                    case .openrouter, .groq, .huggingface, .dockerModelRunner, .vllm:
                        let (baseURL, apiKey, model) = try self.openAICompatibleConfig()
                        for try await chunk in self.openAICompatibleStreamGenerate(baseURL: baseURL, apiKey: apiKey, model: model, prompt: clean, mood: mood) {
                            try Task.checkCancellation()
                            fullResponse += chunk
                            continuation.yield(chunk)
                        }
                    }

                    if !fullResponse.isEmpty {
                        let (parsedMood, cleanForHistory) = MoodParser.parse(from: fullResponse)
                        let durationMs = Int(Date.now.timeIntervalSince(streamStart) * 1000)
                        self.gateway.logStreamEnd(
                            charCount: fullResponse.count,
                            durationMs: durationMs,
                            mood: parsedMood?.rawValue
                        )
                        if !skipHistory {
                            await MainActor.run {
                                self.appendHistory(user: clean, assistant: cleanForHistory, mood: mood.rawValue)
                            }
                        }
                    }
                } catch is CancellationError {
                    if !skipHistory && !fullResponse.isEmpty {
                        let (_, cleanForHistory) = MoodParser.parse(from: fullResponse)
                        await MainActor.run {
                            self.appendHistory(user: clean, assistant: cleanForHistory, mood: mood.rawValue)
                        }
                    }
                } catch {
                    self.gateway.logError(
                        message: error.localizedDescription,
                        subsystem: .brain,
                        detail: "streaming prompt=\(String(clean.prefix(200)))"
                    )
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
    }

    // MARK: - History Management

    private func appendHistory(user: String, assistant: String, mood: String? = nil, extractMemory: Bool = true) {
        let turn = ChatTurn(user: user, assistant: assistant, at: .now, mood: mood)
        history.append(turn)
        if history.count > Self.maxHistoryTurns {
            history.removeFirst(history.count - Self.maxHistoryTurns)
        }

        let turnId = store?.save(
            turn: turn,
            mood: mood ?? "neutral",
            provider: config.provider.rawValue,
            model: activeModelName
        )

        // Fire-and-forget memory extraction (skipped for internal extraction calls).
        guard extractMemory else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.memory.extractAndStore(from: turn, turnId: turnId, using: self)
        }
    }

    private var activeModelName: String {
        switch config.provider {
        case .local:              config.localModel
        case .openai:             config.openAIModel
        case .anthropic:          config.anthropicModel
        case .apple:              "apple-intelligence"
        case .openrouter:         config.openRouterModel
        case .groq:               config.groqModel
        case .huggingface:        config.huggingFaceModel
        case .dockerModelRunner:  config.dockerModelRunnerModel
        case .vllm:               config.vllmModel
        }
    }

    // MARK: - Context Messages

    /// Max characters for history context (system prompt excluded).
    /// Keeps total context safe for small models (4K-8K token windows).
    static let maxContextChars = 6000

    /// Builds a chat messages array from recent history + the current prompt.
    /// Used by OpenAI, Anthropic, and Ollama chat endpoints.
    private func contextMessages(for prompt: String, mood: NotchManager.Mood = .neutral) -> [[String: String]] {
        let recalled = memory.recallRelevant(for: prompt, from: store)
        if !recalled.isEmpty {
            gateway.logMemoryRecall(query: prompt, recalled: recalled)
        }
        let systemContent = soul.systemPrompt(mood: mood, memories: recalled)

        var messages: [[String: String]] = [
            ["role": "system", "content": systemContent],
        ]

        // Budget-aware history: include as many recent turns as fit.
        let recentTurns = Array(history.suffix(Self.contextWindowTurns))
        var charBudget = Self.maxContextChars - prompt.count
        var startIndex = recentTurns.count

        // Walk backwards to find how many turns fit in the budget.
        for i in stride(from: recentTurns.count - 1, through: 0, by: -1) {
            let turn = recentTurns[i]
            let turnChars = turn.user.count + turn.assistant.count
            if charBudget - turnChars < 0 { break }
            charBudget -= turnChars
            startIndex = i
        }

        for turn in recentTurns[startIndex...] {
            messages.append(["role": "user", "content": turn.user])
            messages.append(["role": "assistant", "content": turn.assistant])
        }

        // Post-history identity reinforcement (Airi pattern).
        // Injected after history, right before the current prompt, so the LLM
        // sees this reminder immediately before generating — much more effective
        // than burying it at the end of the system prompt for small models.
        messages.append(["role": "system", "content": soul.postHistoryReminder(mood: mood)])

        messages.append(["role": "user", "content": prompt])
        return messages
    }

    // MARK: - Internal (Raw) LLM Call

    /// Sends a bare prompt to the current provider WITHOUT personality context,
    /// history, mood tags, or any system prompt. Used for internal operations
    /// like memory extraction where the personality framing confuses small models.
    func respondInternal(to prompt: String) async throws -> String {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }

        let start = Date.now
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a helpful assistant. Follow instructions exactly."],
            ["role": "user", "content": clean],
        ]

        let result: String
        do {
            switch config.provider {
            case .local:
                result = try await rawOllamaGenerate(messages: messages)
            case .openai:
                guard let key = config.openAIAPIKey, !key.isEmpty else {
                    throw PikoBrainError.missingCloudCredentials("No API key configured")
                }
                result = try await rawOpenAIGenerate(messages: messages, apiKey: key, model: config.openAIModel)
            case .anthropic:
                guard let key = config.anthropicAPIKey, !key.isEmpty else {
                    throw PikoBrainError.missingCloudCredentials("No API key configured")
                }
                result = try await rawAnthropicGenerate(messages: messages, apiKey: key, model: config.anthropicModel)
            case .apple:
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *) {
                    let model = SystemLanguageModel.default
                    guard model.isAvailable else { throw PikoBrainError.appleIntelligenceUnavailable }
                    let session = LanguageModelSession(model: model)
                    let response = try await session.respond(to: clean)
                    let text = String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw PikoBrainError.emptyResponse }
                    result = text
                } else {
                    throw PikoBrainError.appleIntelligenceUnavailable
                }
                #else
                throw PikoBrainError.appleIntelligenceUnavailable
                #endif
            case .openrouter, .groq, .huggingface, .dockerModelRunner, .vllm:
                let (baseURL, apiKey, model) = try openAICompatibleConfig()
                result = try await rawOpenAICompatibleGenerate(baseURL: baseURL, apiKey: apiKey, model: model, messages: messages)
            }
        } catch {
            gateway.logError(message: error.localizedDescription, subsystem: .memory, detail: "internal_call")
            throw error
        }

        let durationMs = Int(Date.now.timeIntervalSince(start) * 1000)
        gateway.logInternalLLMCall(
            purpose: "memory_extraction",
            promptChars: clean.count,
            responseChars: result.count,
            durationMs: durationMs
        )
        return result
    }

    /// Raw Ollama chat call with explicit messages (no contextMessages).
    private func rawOllamaGenerate(messages: [[String: String]]) async throws -> String {
        let endpoint = config.localEndpoint.appendingPathComponent("api/chat")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.localModel,
            "messages": messages,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response)
        let parsed = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let text = parsed.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PikoBrainError.emptyResponse }
        return text
    }

    /// Raw OpenAI chat call with explicit messages.
    private func rawOpenAIGenerate(messages: [[String: String]], apiKey: String, model: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)
        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = parsed.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }
        return text
    }

    /// Raw Anthropic call with explicit messages.
    private func rawAnthropicGenerate(messages: [[String: String]], apiKey: String, model: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        var chatMessages: [[String: String]] = []
        var systemText: String?
        for msg in messages {
            if msg["role"] == "system" { systemText = msg["content"] }
            else { chatMessages.append(msg) }
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 512,
            "messages": chatMessages,
            "stream": false,
        ]
        if let systemText { body["system"] = systemText }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)
        let parsed = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = parsed.content.first?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }
        return text
    }

    // MARK: - Cloud Fallback

    private func cloudFallbackResponse(prompt: String, mood: NotchManager.Mood = .neutral) async throws -> String? {
        switch config.cloudFallback {
        case .none:
            return nil
        case .openai:
            guard let key = config.openAIAPIKey, !key.isEmpty else { return nil }
            return try await openAIGenerate(prompt: prompt, apiKey: key, model: config.openAIModel, mood: mood)
        case .anthropic:
            guard let key = config.anthropicAPIKey, !key.isEmpty else { return nil }
            return try await anthropicGenerate(prompt: prompt, apiKey: key, model: config.anthropicModel, mood: mood)
        case .openrouter:
            guard let key = config.openRouterAPIKey, !key.isEmpty else { return nil }
            return try await openAICompatibleGenerate(
                baseURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                apiKey: key, model: config.openRouterModel, prompt: prompt, mood: mood)
        case .groq:
            guard let key = config.groqAPIKey, !key.isEmpty else { return nil }
            return try await openAICompatibleGenerate(
                baseURL: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                apiKey: key, model: config.groqModel, prompt: prompt, mood: mood)
        case .huggingface:
            guard let key = config.huggingFaceAPIKey, !key.isEmpty else { return nil }
            return try await openAICompatibleGenerate(
                baseURL: URL(string: "https://router.huggingface.co/v1/chat/completions")!,
                apiKey: key, model: config.huggingFaceModel, prompt: prompt, mood: mood)
        }
    }

    // MARK: - Local Backend

    private func localGenerate(prompt: String, mood: NotchManager.Mood = .neutral) async throws -> String {
        let request = try ollamaRequest(prompt: prompt, stream: false, mood: mood)
        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response)

        let parsed = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let text = parsed.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PikoBrainError.emptyResponse }
        return text
    }

    private func localStreamGenerate(prompt: String, mood: NotchManager.Mood = .neutral) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let request = try self.ollamaRequest(prompt: prompt, stream: true, mood: mood)

                let (bytes, response) = try await Self.session.bytes(for: request)
                try self.checkHTTPResponse(response)

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard let data = line.data(using: .utf8) else { continue }
                    if let chunk = try? JSONDecoder().decode(OllamaChatStreamChunk.self, from: data) {
                        let text = chunk.message.content
                        if !text.isEmpty {
                            continuation.yield(text)
                        }
                        if chunk.done { break }
                    }
                }
                continuation.finish()
            }
        }
    }

    private func generateWithFoundationModels(prompt: String, mood: NotchManager.Mood = .neutral) async -> String? {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else { return nil }
            do {
                // FoundationModels doesn't support chat messages, so compose
                // the system prompt + history into a single text prompt.
                let recalled = memory.recallRelevant(for: prompt, from: store)
                let systemText = soul.systemPrompt(mood: mood, memories: recalled)
                var composed = "System: \(systemText)\n\n"
                let recentTurns = history.suffix(Self.contextWindowTurns)
                for turn in recentTurns {
                    composed += "User: \(turn.user)\nAssistant: \(turn.assistant)\n\n"
                }
                composed += "System: \(soul.postHistoryReminder(mood: mood))\n\n"
                composed += "User: \(prompt)\nAssistant:"

                let session = LanguageModelSession(model: model)
                let response = try await session.respond(to: composed)
                let text = String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                // Safety guardrails or other FoundationModels errors —
                // fall through to Ollama / cloud backend.
                return nil
            }
        }
#endif
        return nil
    }

    private func ollamaRequest(prompt: String, stream: Bool, mood: NotchManager.Mood = .neutral) throws -> URLRequest {
        let endpoint = config.localEndpoint.appendingPathComponent("api/chat")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = contextMessages(for: prompt, mood: mood)
        let body: [String: Any] = [
            "model": config.localModel,
            "messages": messages,
            "stream": stream,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - OpenAI Backend

    private func openAIGenerate(prompt: String, apiKey: String, model: String, mood: NotchManager.Mood = .neutral) async throws -> String {
        let request = try openAIRequest(prompt: prompt, apiKey: apiKey, model: model, stream: false, mood: mood)

        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)

        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = parsed.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }
        return text
    }

    private func openAIStreamGenerate(prompt: String, apiKey: String, model: String, mood: NotchManager.Mood = .neutral) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let request = try self.openAIRequest(prompt: prompt, apiKey: apiKey, model: model, stream: true, mood: mood)

                let (bytes, response) = try await Self.session.bytes(for: request)
                try self.checkHTTPResponse(response)

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8) else { continue }
                    if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                       let content = chunk.choices.first?.delta.content, !content.isEmpty {
                        continuation.yield(content)
                    }
                }
                continuation.finish()
            }
        }
    }

    private func openAIRequest(prompt: String, apiKey: String, model: String, stream: Bool, mood: NotchManager.Mood = .neutral) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": contextMessages(for: prompt, mood: mood),
            "temperature": 0.7,
            "stream": stream,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Anthropic Backend

    private func anthropicGenerate(prompt: String, apiKey: String, model: String, mood: NotchManager.Mood = .neutral) async throws -> String {
        let request = try anthropicRequest(prompt: prompt, apiKey: apiKey, model: model, stream: false, mood: mood)

        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)

        let parsed = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = parsed.content.first?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }
        return text
    }

    private func anthropicStreamGenerate(prompt: String, apiKey: String, model: String, mood: NotchManager.Mood = .neutral) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let request = try self.anthropicRequest(prompt: prompt, apiKey: apiKey, model: model, stream: true, mood: mood)

                let (bytes, response) = try await Self.session.bytes(for: request)
                try self.checkHTTPResponse(response)

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    guard let data = payload.data(using: .utf8) else { continue }
                    if let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data),
                       event.type == "content_block_delta",
                       let text = event.delta?.text, !text.isEmpty {
                        continuation.yield(text)
                    }
                }
                continuation.finish()
            }
        }
    }

    private func anthropicRequest(prompt: String, apiKey: String, model: String, stream: Bool, mood: NotchManager.Mood = .neutral) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Anthropic uses a separate "system" param, not a system message in the array.
        let allMessages = contextMessages(for: prompt, mood: mood)
        var systemText: String?
        var chatMessages: [[String: String]] = []
        for msg in allMessages {
            if msg["role"] == "system" {
                systemText = msg["content"]
            } else {
                chatMessages.append(msg)
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": chatMessages,
            "stream": stream,
        ]
        if let systemText {
            body["system"] = systemText
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - OpenAI-Compatible Shared Handler

    /// Returns (baseURL, apiKey, model) for the current provider.
    private func openAICompatibleConfig() throws -> (URL, String?, String) {
        switch config.provider {
        case .openrouter:
            guard let key = config.openRouterAPIKey, !key.isEmpty else {
                throw PikoBrainError.missingCloudCredentials("No OpenRouter API key configured")
            }
            return (URL(string: "https://openrouter.ai/api/v1/chat/completions")!, key, config.openRouterModel)
        case .groq:
            guard let key = config.groqAPIKey, !key.isEmpty else {
                throw PikoBrainError.missingCloudCredentials("No Groq API key configured")
            }
            return (URL(string: "https://api.groq.com/openai/v1/chat/completions")!, key, config.groqModel)
        case .huggingface:
            guard let key = config.huggingFaceAPIKey, !key.isEmpty else {
                throw PikoBrainError.missingCloudCredentials("No HuggingFace API key configured")
            }
            return (URL(string: "https://router.huggingface.co/v1/chat/completions")!, key, config.huggingFaceModel)
        case .dockerModelRunner:
            let base = config.dockerModelRunnerEndpoint.appendingPathComponent("engines/v1/chat/completions")
            return (base, nil, config.dockerModelRunnerModel)
        case .vllm:
            let base = config.vllmEndpoint.appendingPathComponent("v1/chat/completions")
            let key = config.vllmAPIKey?.isEmpty == false ? config.vllmAPIKey : nil
            return (base, key, config.vllmModel)
        default:
            throw PikoBrainError.missingCloudCredentials("Provider is not OpenAI-compatible")
        }
    }

    private func openAICompatibleRequest(baseURL: URL, apiKey: String?, model: String, prompt: String, stream: Bool, mood: NotchManager.Mood = .neutral) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": contextMessages(for: prompt, mood: mood),
            "temperature": 0.7,
            "stream": stream,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func openAICompatibleGenerate(baseURL: URL, apiKey: String?, model: String, prompt: String, mood: NotchManager.Mood = .neutral) async throws -> String {
        let request = try openAICompatibleRequest(baseURL: baseURL, apiKey: apiKey, model: model, prompt: prompt, stream: false, mood: mood)
        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)

        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = parsed.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }

        // Record token usage if available.
        if let usage = parsed.usage {
            store?.recordUsage(
                provider: config.provider.rawValue,
                model: model,
                promptTokens: usage.prompt_tokens ?? 0,
                completionTokens: usage.completion_tokens ?? 0
            )
        }
        return text
    }

    private func openAICompatibleStreamGenerate(baseURL: URL, apiKey: String?, model: String, prompt: String, mood: NotchManager.Mood = .neutral) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let request = try self.openAICompatibleRequest(baseURL: baseURL, apiKey: apiKey, model: model, prompt: prompt, stream: true, mood: mood)

                let (bytes, response) = try await Self.session.bytes(for: request)
                try self.checkHTTPResponse(response)

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8) else { continue }
                    if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                       let content = chunk.choices.first?.delta.content, !content.isEmpty {
                        continuation.yield(content)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Raw OpenAI-compatible call with explicit messages (for respondInternal).
    private func rawOpenAICompatibleGenerate(baseURL: URL, apiKey: String?, model: String, messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)
        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = parsed.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }
        return text
    }

    // MARK: - HTTP Helpers

    private func checkHTTPResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PikoBrainError.badHTTPResponse(statusCode: 0, detail: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            var detail: String?
            if let data, let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                detail = apiError.error?.message
            }
            throw PikoBrainError.badHTTPResponse(statusCode: http.statusCode, detail: detail)
        }
    }
}

// MARK: - Errors

enum PikoBrainError: LocalizedError {
    case localBackendUnavailable
    case badHTTPResponse(statusCode: Int, detail: String?)
    case emptyResponse
    case missingCloudCredentials(String)
    case appleIntelligenceUnavailable

    var errorDescription: String? {
        switch self {
        case .localBackendUnavailable:
            return "Can't reach local model"
        case .badHTTPResponse(let code, let detail):
            if code == 401 {
                return "API key was rejected"
            } else if code == 429 {
                return "Too many requests"
            } else if let detail {
                return detail
            }
            return "Backend returned HTTP \(code)"
        case .emptyResponse:
            return "Model returned nothing"
        case .missingCloudCredentials(let msg):
            return msg
        case .appleIntelligenceUnavailable:
            return "Apple Intelligence is not available"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .localBackendUnavailable:
            return "Start Ollama or switch to cloud in Settings"
        case .badHTTPResponse(let code, _):
            if code == 401 { return "Check your key in Settings → AI Model" }
            if code == 429 { return "Wait a moment and try again" }
            return "Check your connection and try again"
        case .emptyResponse:
            return "Try a different prompt or model"
        case .missingCloudCredentials:
            return "Add your key in Settings → AI Model"
        case .appleIntelligenceUnavailable:
            return "Requires macOS 26+ with Apple Intelligence enabled"
        }
    }

    var opensSettings: Bool {
        switch self {
        case .missingCloudCredentials, .badHTTPResponse(401, _):
            return true
        default:
            return false
        }
    }
}
