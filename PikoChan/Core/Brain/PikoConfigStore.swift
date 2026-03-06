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
        // API keys come from Keychain, not YAML.
        openAIAPIKey = PikoKeychain.load(account: "openai_api_key") ?? ""
        anthropicAPIKey = PikoKeychain.load(account: "anthropic_api_key") ?? ""
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
setup_complete: \(setupComplete ? "true" : "false")
"""

        try yaml.write(to: home.configFile, atomically: true, encoding: .utf8)

        // Save API keys to Keychain.
        let trimmedOpenAI = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnthropic = anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedOpenAI.isEmpty {
            PikoKeychain.delete(account: "openai_api_key")
        } else {
            PikoKeychain.save(account: "openai_api_key", value: trimmedOpenAI)
        }

        if trimmedAnthropic.isEmpty {
            PikoKeychain.delete(account: "anthropic_api_key")
        } else {
            PikoKeychain.save(account: "anthropic_api_key", value: trimmedAnthropic)
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
setup_complete: \(cfg.setupComplete ? "true" : "false")
"""
            try? yaml.write(to: home.configFile, atomically: true, encoding: .utf8)
        }
    }
}
