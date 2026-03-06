import Foundation

struct PikoConfig {
    enum Provider: String {
        case local
        case openai
        case anthropic
        case apple
    }

    enum CloudFallback: String {
        case none
        case openai
        case anthropic
    }

    var provider: Provider
    var localModel: String
    var localEndpoint: URL
    var cloudFallback: CloudFallback
    var openAIModel: String
    var anthropicModel: String
    var openAIAPIKey: String?
    var anthropicAPIKey: String?
    var gatewayPort: UInt16

    static let `default` = PikoConfig(
        provider: .local,
        localModel: "phi4-mini",
        localEndpoint: URL(string: "http://127.0.0.1:11434")!,
        cloudFallback: .none,
        openAIModel: "gpt-4o-mini",
        anthropicModel: "claude-3-5-haiku-latest",
        openAIAPIKey: nil,
        anthropicAPIKey: nil,
        gatewayPort: 7878
    )
}

enum PikoConfigLoader {
    static func load(from file: URL) -> PikoConfig {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .default
        }

        let map = parseSimpleYAML(text)

        let provider = PikoConfig.Provider(rawValue: map["provider"] ?? "") ?? .local
        let localModel = map["local_model"]?.nonEmpty ?? PikoConfig.default.localModel
        let localEndpoint = URL(string: map["local_endpoint"] ?? "") ?? PikoConfig.default.localEndpoint
        let cloudFallback = PikoConfig.CloudFallback(rawValue: map["cloud_fallback"] ?? "") ?? .none
        let openAIModel = map["openai_model"]?.nonEmpty ?? PikoConfig.default.openAIModel
        let anthropicModel = map["anthropic_model"]?.nonEmpty ?? PikoConfig.default.anthropicModel
        // API keys: prefer Keychain, fall back to YAML for migration.
        let openAIAPIKey = PikoKeychain.load(account: "openai_api_key") ?? map["openai_api_key"]?.nonEmpty
        let anthropicAPIKey = PikoKeychain.load(account: "anthropic_api_key") ?? map["anthropic_api_key"]?.nonEmpty
        let gatewayPort: UInt16 = {
            if let envPort = ProcessInfo.processInfo.environment["PIKOCHAN_PORT"],
               let port = UInt16(envPort) { return port }
            if let yamlPort = map["gateway_port"], let port = UInt16(yamlPort) { return port }
            return PikoConfig.default.gatewayPort
        }()

        return PikoConfig(
            provider: provider,
            localModel: localModel,
            localEndpoint: localEndpoint,
            cloudFallback: cloudFallback,
            openAIModel: openAIModel,
            anthropicModel: anthropicModel,
            openAIAPIKey: openAIAPIKey,
            anthropicAPIKey: anthropicAPIKey,
            gatewayPort: gatewayPort
        )
    }

    private static func parseSimpleYAML(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes (single or double).
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            // Strip inline comments (only if preceded by space).
            if let commentIdx = value.range(of: " #") {
                value = String(value[..<commentIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            map[key] = value
        }
        return map
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
