import Observation
import Foundation

@Observable
@MainActor
final class PikoConfigStore {
    static let shared = PikoConfigStore()

    private let home = PikoHome()

    var provider: PikoConfig.Provider = .local
    var localModel: String = "phi4-mini"
    var localEndpoint: String = "http://127.0.0.1:11434"
    var cloudFallback: PikoConfig.CloudFallback = .none
    var openAIModel: String = "gpt-4o-mini"
    var anthropicModel: String = "claude-3-5-haiku-latest"
    var openAIAPIKey: String = ""
    var anthropicAPIKey: String = ""
    var openRouterModel: String = "openai/gpt-4o-mini"
    var openRouterAPIKey: String = ""
    var groqModel: String = "llama-3.3-70b-versatile"
    var groqAPIKey: String = ""
    var huggingFaceModel: String = "meta-llama/Llama-3-70b"
    var huggingFaceAPIKey: String = ""
    var dockerModelRunnerModel: String = "ai/smollm2"
    var dockerModelRunnerEndpoint: String = "http://localhost:12434"
    var vllmModel: String = "NousResearch/Meta-Llama-3-8B-Instruct"
    var vllmEndpoint: String = "http://localhost:8000"
    var vllmAPIKey: String = ""
    var setupComplete: Bool = false

    private init() {
        do {
            try home.bootstrap()
        } catch {
            // Bootstrap failure will be surfaced by NotchManager on start.
        }
        migrateKeysToKeychain()
        reload()
    }

    func reload() {
        let cfg = PikoConfigLoader.load(from: home.configFile)
        provider = cfg.provider
        localModel = cfg.localModel
        localEndpoint = cfg.localEndpoint.absoluteString
        cloudFallback = cfg.cloudFallback
        openAIModel = cfg.openAIModel
        anthropicModel = cfg.anthropicModel
        openRouterModel = cfg.openRouterModel
        groqModel = cfg.groqModel
        huggingFaceModel = cfg.huggingFaceModel
        dockerModelRunnerModel = cfg.dockerModelRunnerModel
        dockerModelRunnerEndpoint = cfg.dockerModelRunnerEndpoint.absoluteString
        vllmModel = cfg.vllmModel
        vllmEndpoint = cfg.vllmEndpoint.absoluteString
        // API keys come from Keychain, not YAML.
        openAIAPIKey = PikoKeychain.load(account: "openai_api_key") ?? ""
        anthropicAPIKey = PikoKeychain.load(account: "anthropic_api_key") ?? ""
        openRouterAPIKey = PikoKeychain.load(account: "openrouter_api_key") ?? ""
        groqAPIKey = PikoKeychain.load(account: "groq_api_key") ?? ""
        huggingFaceAPIKey = PikoKeychain.load(account: "huggingface_api_key") ?? ""
        vllmAPIKey = PikoKeychain.load(account: "vllm_api_key") ?? ""
        setupComplete = cfg.setupComplete
    }

    func save() throws {
        try home.bootstrap()

        // Save non-secret config to YAML (no API keys).
        let yaml = """
provider: \(provider.rawValue)
local_model: \(localModel.trimmingCharacters(in: .whitespacesAndNewlines))
local_endpoint: \(localEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
cloud_fallback: \(cloudFallback.rawValue)
openai_model: \(openAIModel.trimmingCharacters(in: .whitespacesAndNewlines))
anthropic_model: \(anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines))
openrouter_model: \(openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines))
groq_model: \(groqModel.trimmingCharacters(in: .whitespacesAndNewlines))
huggingface_model: \(huggingFaceModel.trimmingCharacters(in: .whitespacesAndNewlines))
docker_model_runner_model: \(dockerModelRunnerModel.trimmingCharacters(in: .whitespacesAndNewlines))
docker_model_runner_endpoint: \(dockerModelRunnerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
vllm_model: \(vllmModel.trimmingCharacters(in: .whitespacesAndNewlines))
vllm_endpoint: \(vllmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
setup_complete: \(setupComplete ? "true" : "false")
"""

        try yaml.write(to: home.configFile, atomically: true, encoding: .utf8)

        // Save API keys to Keychain.
        let keychainEntries: [(account: String, value: String)] = [
            ("openai_api_key", openAIAPIKey),
            ("anthropic_api_key", anthropicAPIKey),
            ("openrouter_api_key", openRouterAPIKey),
            ("groq_api_key", groqAPIKey),
            ("huggingface_api_key", huggingFaceAPIKey),
            ("vllm_api_key", vllmAPIKey),
        ]
        for entry in keychainEntries {
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                PikoKeychain.delete(account: entry.account)
            } else {
                PikoKeychain.save(account: entry.account, value: trimmed)
            }
        }
    }

    func markSetupComplete() throws {
        setupComplete = true
        try save()
    }

    /// Migrate API keys from config.yaml to Keychain on first run after update.
    private func migrateKeysToKeychain() {
        let cfg = PikoConfigLoader.load(from: home.configFile)

        if let key = cfg.openAIAPIKey, !key.isEmpty, PikoKeychain.load(account: "openai_api_key") == nil {
            PikoKeychain.save(account: "openai_api_key", value: key)
        }
        if let key = cfg.anthropicAPIKey, !key.isEmpty, PikoKeychain.load(account: "anthropic_api_key") == nil {
            PikoKeychain.save(account: "anthropic_api_key", value: key)
        }

        // Rewrite config.yaml without API keys if they were present.
        if cfg.openAIAPIKey != nil || cfg.anthropicAPIKey != nil {
            let yaml = """
provider: \(cfg.provider.rawValue)
local_model: \(cfg.localModel)
local_endpoint: \(cfg.localEndpoint.absoluteString)
cloud_fallback: \(cfg.cloudFallback.rawValue)
openai_model: \(cfg.openAIModel)
anthropic_model: \(cfg.anthropicModel)
openrouter_model: \(cfg.openRouterModel)
groq_model: \(cfg.groqModel)
huggingface_model: \(cfg.huggingFaceModel)
docker_model_runner_model: \(cfg.dockerModelRunnerModel)
docker_model_runner_endpoint: \(cfg.dockerModelRunnerEndpoint.absoluteString)
vllm_model: \(cfg.vllmModel)
vllm_endpoint: \(cfg.vllmEndpoint.absoluteString)
setup_complete: \(cfg.setupComplete ? "true" : "false")
"""
            try? yaml.write(to: home.configFile, atomically: true, encoding: .utf8)
        }
    }
}
