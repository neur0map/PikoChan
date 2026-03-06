import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ChatTurn {
    let user: String
    let assistant: String
    let at: Date
}

// MARK: - Codable Response Types

private struct OllamaResponse: Codable {
    let response: String
}

private struct OllamaStreamChunk: Codable {
    let response: String
    let done: Bool
}

private struct OpenAIResponse: Codable {
    let choices: [Choice]
    struct Choice: Codable {
        let message: Message
    }
    struct Message: Codable {
        let content: String
    }
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
    private let home: PikoHome
    private(set) var config: PikoConfig
    private(set) var history: [ChatTurn] = []

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
    }

    init(home: PikoHome) {
        self.home = home
        self.config = .default
    }

    func bootstrap() throws {
        try home.bootstrap()
        reloadConfig()
    }

    func reloadConfig() {
        config = PikoConfigLoader.load(from: home.configFile)
    }

    // MARK: - Full Response (non-streaming)

    func respond(to prompt: String) async throws -> String {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }

        let response: String
        switch config.provider {
        case .local:
            do {
                response = try await localGenerate(prompt: clean)
            } catch {
                if let fallback = try await cloudFallbackResponse(prompt: clean) {
                    appendHistory(user: clean, assistant: fallback)
                    return fallback
                }
                throw error
            }
        case .openai:
            guard let key = config.openAIAPIKey, !key.isEmpty else {
                throw PikoBrainError.missingCloudCredentials("No API key configured")
            }
            response = try await openAIGenerate(prompt: clean, apiKey: key, model: config.openAIModel)
        case .anthropic:
            guard let key = config.anthropicAPIKey, !key.isEmpty else {
                throw PikoBrainError.missingCloudCredentials("No API key configured")
            }
            response = try await anthropicGenerate(prompt: clean, apiKey: key, model: config.anthropicModel)
        }

        appendHistory(user: clean, assistant: response)
        return response
    }

    // MARK: - Streaming Response

    func respondStreaming(to prompt: String) -> AsyncStream<String> {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return AsyncStream { $0.finish() }
        }

        let cfg = config
        return AsyncStream { continuation in
            Task {
                var fullResponse = ""
                do {
                    switch cfg.provider {
                    case .local:
                        do {
                            for try await chunk in self.localStreamGenerate(prompt: clean) {
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
                                let fallback = try await self.cloudFallbackResponse(prompt: clean)
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
                        for try await chunk in self.openAIStreamGenerate(prompt: clean, apiKey: key, model: cfg.openAIModel) {
                            try Task.checkCancellation()
                            fullResponse += chunk
                            continuation.yield(chunk)
                        }
                    case .anthropic:
                        guard let key = cfg.anthropicAPIKey, !key.isEmpty else {
                            throw PikoBrainError.missingCloudCredentials("No API key configured")
                        }
                        for try await chunk in self.anthropicStreamGenerate(prompt: clean, apiKey: key, model: cfg.anthropicModel) {
                            try Task.checkCancellation()
                            fullResponse += chunk
                            continuation.yield(chunk)
                        }
                    }

                    if !fullResponse.isEmpty {
                        await MainActor.run {
                            self.appendHistory(user: clean, assistant: fullResponse)
                        }
                    }
                } catch is CancellationError {
                    if !fullResponse.isEmpty {
                        await MainActor.run {
                            self.appendHistory(user: clean, assistant: fullResponse)
                        }
                    }
                } catch {
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
    }

    // MARK: - History Management

    private func appendHistory(user: String, assistant: String) {
        history.append(ChatTurn(user: user, assistant: assistant, at: .now))
        if history.count > Self.maxHistoryTurns {
            history.removeFirst(history.count - Self.maxHistoryTurns)
        }
    }

    // MARK: - Cloud Fallback

    private func cloudFallbackResponse(prompt: String) async throws -> String? {
        switch config.cloudFallback {
        case .none:
            return nil
        case .openai:
            guard let key = config.openAIAPIKey, !key.isEmpty else { return nil }
            return try await openAIGenerate(prompt: prompt, apiKey: key, model: config.openAIModel)
        case .anthropic:
            guard let key = config.anthropicAPIKey, !key.isEmpty else { return nil }
            return try await anthropicGenerate(prompt: prompt, apiKey: key, model: config.anthropicModel)
        }
    }

    // MARK: - Local Backend

    private func localGenerate(prompt: String) async throws -> String {
        if let localText = try await generateWithFoundationModels(prompt: prompt), !localText.isEmpty {
            return localText
        }

        let endpoint = config.localEndpoint.appendingPathComponent("api/generate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = try JSONEncoder().encode(OllamaRequestBody(model: config.localModel, prompt: prompt, stream: false))
        request.httpBody = body

        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response)

        let parsed = try JSONDecoder().decode(OllamaResponse.self, from: data)
        let text = parsed.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PikoBrainError.emptyResponse }
        return text
    }

    private func localStreamGenerate(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Try FoundationModels first (no streaming — simulate it)
                if let localText = try? await self.generateWithFoundationModels(prompt: prompt), !localText.isEmpty {
                    for char in localText {
                        try Task.checkCancellation()
                        continuation.yield(String(char))
                        try await Task.sleep(for: .milliseconds(15))
                    }
                    continuation.finish()
                    return
                }

                let endpoint = self.config.localEndpoint.appendingPathComponent("api/generate")
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let body = try JSONEncoder().encode(OllamaRequestBody(model: self.config.localModel, prompt: prompt, stream: true))
                request.httpBody = body

                let (bytes, response) = try await Self.session.bytes(for: request)
                try self.checkHTTPResponse(response)

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard let data = line.data(using: .utf8) else { continue }
                    if let chunk = try? JSONDecoder().decode(OllamaStreamChunk.self, from: data) {
                        if !chunk.response.isEmpty {
                            continuation.yield(chunk.response)
                        }
                        if chunk.done { break }
                    }
                }
                continuation.finish()
            }
        }
    }

    private func generateWithFoundationModels(prompt: String) async throws -> String? {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else { return nil }
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt)
            let text = String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
#endif
        return nil
    }

    // MARK: - OpenAI Backend

    private func openAIGenerate(prompt: String, apiKey: String, model: String) async throws -> String {
        let request = try openAIRequest(prompt: prompt, apiKey: apiKey, model: model, stream: false)

        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)

        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = parsed.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }
        return text
    }

    private func openAIStreamGenerate(prompt: String, apiKey: String, model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let request = try self.openAIRequest(prompt: prompt, apiKey: apiKey, model: model, stream: true)

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

    private func openAIRequest(prompt: String, apiKey: String, model: String, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7,
            "stream": stream,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Anthropic Backend

    private func anthropicGenerate(prompt: String, apiKey: String, model: String) async throws -> String {
        let request = try anthropicRequest(prompt: prompt, apiKey: apiKey, model: model, stream: false)

        let (data, response) = try await Self.session.data(for: request)
        try checkHTTPResponse(response, data: data)

        let parsed = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = parsed.content.first?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PikoBrainError.emptyResponse
        }
        return text
    }

    private func anthropicStreamGenerate(prompt: String, apiKey: String, model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let request = try self.anthropicRequest(prompt: prompt, apiKey: apiKey, model: model, stream: true)

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

    private func anthropicRequest(prompt: String, apiKey: String, model: String, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]],
            "stream": stream,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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

// MARK: - Request Bodies

private struct OllamaRequestBody: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

// MARK: - Errors

enum PikoBrainError: LocalizedError {
    case localBackendUnavailable
    case badHTTPResponse(statusCode: Int, detail: String?)
    case emptyResponse
    case missingCloudCredentials(String)

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
