import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Drives the first-time setup wizard flow.
@Observable
final class SetupManager {

    enum Step: Int, CaseIterable {
        case welcome, provider, providerConfig, memory, summary
    }

    enum ProviderValidation: Equatable {
        case idle, testing, success, failure(String)
    }

    enum MemoryMigration: Equatable {
        case idle, inProgress(done: Int, total: Int), complete(Int), skipped
    }

    // MARK: - State

    var currentStep: Step = .welcome
    var providerValidation: ProviderValidation = .idle
    var memoryMigration: MemoryMigration = .idle

    // Provider config
    var selectedProvider: PikoConfig.Provider = .local
    var apiKey: String = ""
    var localModel: String = "phi4-mini"
    var localEndpoint: String = "http://127.0.0.1:11434"

    // Ollama model list (populated on validation)
    var ollamaModels: [String] = []

    // Check results
    var providerReady: Bool = false
    var embeddingAvailable: Bool = false
    var gatewayReady: Bool = false
    var dbReady: Bool = false

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func goBack() {
        guard let prev = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
        // Reset validation when going back to provider selection.
        if currentStep == .provider {
            providerValidation = .idle
            providerReady = false
        }
    }

    // MARK: - Provider Validation

    private static let validationSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }()

    func validateProvider() async {
        providerValidation = .testing
        providerReady = false

        do {
            switch selectedProvider {
            case .local:
                try await validateOllama()
            case .openai:
                try await validateOpenAI()
            case .anthropic:
                try await validateAnthropic()
            case .apple:
                try validateApple()
            }
            providerValidation = .success
            providerReady = true
        } catch {
            providerValidation = .failure(error.localizedDescription)
        }
    }

    private func validateOllama() async throws {
        guard let base = URL(string: localEndpoint) else { throw SetupError.ollamaNotRunning }
        let endpoint = base.appendingPathComponent("api/tags")
        let (data, response) = try await Self.validationSession.data(from: endpoint)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SetupError.ollamaNotRunning
        }
        // Parse model list.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = json["models"] as? [[String: Any]] {
            ollamaModels = models.compactMap { $0["name"] as? String }
            if !ollamaModels.isEmpty && !ollamaModels.contains(localModel) {
                localModel = ollamaModels[0]
            }
        }
    }

    private func validateOpenAI() async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SetupError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.addValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await Self.validationSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw SetupError.invalidAPIKey }
            throw SetupError.networkError("HTTP \(code)")
        }
    }

    private func validateAnthropic() async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SetupError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(trimmed, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": "claude-3-5-haiku-latest",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await Self.validationSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SetupError.networkError("No response")
        }
        // 200 = success, 400 = bad request but key is valid
        if http.statusCode == 401 { throw SetupError.invalidAPIKey }
        if http.statusCode >= 500 { throw SetupError.networkError("HTTP \(http.statusCode)") }
    }

    private func validateApple() throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else { throw SetupError.appleUnavailable }
        } else {
            throw SetupError.appleUnavailable
        }
        #else
        throw SetupError.appleUnavailable
        #endif
    }

    // MARK: - Memory Migration

    func migrateMemories(store: PikoStore?) async {
        guard let store else {
            memoryMigration = .skipped
            return
        }

        embeddingAvailable = PikoEmbedding.isAvailable

        guard embeddingAvailable else {
            memoryMigration = .skipped
            return
        }

        let unindexed = store.memoriesWithoutVectors()
        guard !unindexed.isEmpty else {
            memoryMigration = .complete(0)
            return
        }

        memoryMigration = .inProgress(done: 0, total: unindexed.count)
        var indexed = 0
        for item in unindexed {
            if let vec = PikoEmbedding.embed(item.fact) {
                store.saveVector(memoryId: item.id, vector: vec, embedder: PikoEmbedding.activeEmbedder.rawValue)
                indexed += 1
                memoryMigration = .inProgress(done: indexed, total: unindexed.count)
            }
        }
        memoryMigration = .complete(indexed)
    }

    // MARK: - System Checks

    func runSystemChecks(store: PikoStore?, gatewayPort: UInt16) async {
        dbReady = store != nil
        embeddingAvailable = PikoEmbedding.isAvailable

        // Check gateway
        do {
            let url = URL(string: "http://127.0.0.1:\(gatewayPort)/health")!
            let (_, response) = try await Self.validationSession.data(from: url)
            gatewayReady = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            gatewayReady = false
        }

        // Migrate memories
        await migrateMemories(store: store)
    }

    // MARK: - Finalize

    func finalize(configStore: PikoConfigStore) throws {
        // Apply provider settings.
        configStore.provider = selectedProvider
        switch selectedProvider {
        case .local:
            configStore.localModel = localModel
            configStore.localEndpoint = localEndpoint
        case .openai:
            configStore.openAIAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anthropic:
            configStore.anthropicAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .apple:
            break
        }
        try configStore.markSetupComplete()
    }

    // MARK: - Errors

    enum SetupError: LocalizedError {
        case ollamaNotRunning
        case missingAPIKey
        case invalidAPIKey
        case networkError(String)
        case appleUnavailable

        var errorDescription: String? {
            switch self {
            case .ollamaNotRunning: "Ollama is not running"
            case .missingAPIKey: "API key is required"
            case .invalidAPIKey: "API key was rejected"
            case .networkError(let detail): "Network error: \(detail)"
            case .appleUnavailable: "Apple Intelligence is not available on this Mac"
            }
        }
    }
}
