import Foundation

struct PikoConfig {
    enum Provider: String {
        case local
        case openai
        case anthropic
        case apple
        case openrouter
        case groq
        case huggingface
        case dockerModelRunner = "docker_model_runner"
        case vllm
    }

    enum CloudFallback: String {
        case none
        case openai
        case anthropic
        case openrouter
        case groq
        case huggingface
    }

    var provider: Provider
    var localModel: String
    var localEndpoint: URL
    var cloudFallback: CloudFallback
    var openAIModel: String
    var anthropicModel: String
    var openAIAPIKey: String?
    var anthropicAPIKey: String?
    var openRouterModel: String
    var openRouterAPIKey: String?
    var groqModel: String
    var groqAPIKey: String?
    var huggingFaceModel: String
    var huggingFaceAPIKey: String?
    var dockerModelRunnerModel: String
    var dockerModelRunnerEndpoint: URL
    var vllmModel: String
    var vllmEndpoint: URL
    var vllmAPIKey: String?
    var gatewayPort: UInt16
    var setupComplete: Bool
    var heartbeatEnabled: Bool
    var heartbeatInterval: Int
    var heartbeatNudgesEnabled: Bool
    var nudgeLongIdle: Bool
    var nudgeLateNight: Bool
    var nudgeMarathon: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var skillsTerminalEnabled: Bool
    var skillsBrowserEnabled: Bool
    var skillsAutoExecuteSafe: Bool

    static let `default` = PikoConfig(
        provider: .local,
        localModel: "phi4-mini",
        localEndpoint: URL(string: "http://127.0.0.1:11434")!,
        cloudFallback: .none,
        openAIModel: "gpt-4o-mini",
        anthropicModel: "claude-3-5-haiku-latest",
        openAIAPIKey: nil,
        anthropicAPIKey: nil,
        openRouterModel: "openai/gpt-4o-mini",
        openRouterAPIKey: nil,
        groqModel: "llama-3.3-70b-versatile",
        groqAPIKey: nil,
        huggingFaceModel: "meta-llama/Llama-3-70b",
        huggingFaceAPIKey: nil,
        dockerModelRunnerModel: "ai/smollm2",
        dockerModelRunnerEndpoint: URL(string: "http://localhost:12434")!,
        vllmModel: "NousResearch/Meta-Llama-3-8B-Instruct",
        vllmEndpoint: URL(string: "http://localhost:8000")!,
        vllmAPIKey: nil,
        gatewayPort: 7878,
        setupComplete: false,
        heartbeatEnabled: true,
        heartbeatInterval: 60,
        heartbeatNudgesEnabled: false,
        nudgeLongIdle: true,
        nudgeLateNight: true,
        nudgeMarathon: false,
        quietHoursStart: 23,
        quietHoursEnd: 7,
        skillsTerminalEnabled: true,
        skillsBrowserEnabled: true,
        skillsAutoExecuteSafe: true
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
        let openRouterModel = map["openrouter_model"]?.nonEmpty ?? PikoConfig.default.openRouterModel
        let openRouterAPIKey = PikoKeychain.load(account: "openrouter_api_key") ?? map["openrouter_api_key"]?.nonEmpty
        let groqModel = map["groq_model"]?.nonEmpty ?? PikoConfig.default.groqModel
        let groqAPIKey = PikoKeychain.load(account: "groq_api_key") ?? map["groq_api_key"]?.nonEmpty
        let huggingFaceModel = map["huggingface_model"]?.nonEmpty ?? PikoConfig.default.huggingFaceModel
        let huggingFaceAPIKey = PikoKeychain.load(account: "huggingface_api_key") ?? map["huggingface_api_key"]?.nonEmpty
        let dockerModelRunnerModel = map["docker_model_runner_model"]?.nonEmpty ?? PikoConfig.default.dockerModelRunnerModel
        let dockerModelRunnerEndpoint = URL(string: map["docker_model_runner_endpoint"] ?? "") ?? PikoConfig.default.dockerModelRunnerEndpoint
        let vllmModel = map["vllm_model"]?.nonEmpty ?? PikoConfig.default.vllmModel
        let vllmEndpoint = URL(string: map["vllm_endpoint"] ?? "") ?? PikoConfig.default.vllmEndpoint
        let vllmAPIKey = PikoKeychain.load(account: "vllm_api_key") ?? map["vllm_api_key"]?.nonEmpty
        let gatewayPort: UInt16 = {
            if let envPort = ProcessInfo.processInfo.environment["PIKOCHAN_PORT"],
               let port = UInt16(envPort) { return port }
            if let yamlPort = map["gateway_port"], let port = UInt16(yamlPort) { return port }
            return PikoConfig.default.gatewayPort
        }()

        let setupComplete = (map["setup_complete"] ?? "") == "true"

        let heartbeatEnabled = (map["heartbeat_enabled"] ?? "true") == "true"
        let heartbeatInterval = Int(map["heartbeat_interval"] ?? "60") ?? 60
        let heartbeatNudgesEnabled = (map["heartbeat_nudges_enabled"] ?? "false") == "true"
        let nudgeLongIdle = (map["nudge_long_idle"] ?? "true") == "true"
        let nudgeLateNight = (map["nudge_late_night"] ?? "true") == "true"
        let nudgeMarathon = (map["nudge_marathon"] ?? "false") == "true"
        let quietHoursStart = Int(map["quiet_hours_start"] ?? "23") ?? 23
        let quietHoursEnd = Int(map["quiet_hours_end"] ?? "7") ?? 7
        let skillsTerminalEnabled = (map["skills_terminal_enabled"] ?? "true") == "true"
        let skillsBrowserEnabled = (map["skills_browser_enabled"] ?? "true") == "true"
        let skillsAutoExecuteSafe = (map["skills_auto_execute_safe"] ?? "true") == "true"

        return PikoConfig(
            provider: provider,
            localModel: localModel,
            localEndpoint: localEndpoint,
            cloudFallback: cloudFallback,
            openAIModel: openAIModel,
            anthropicModel: anthropicModel,
            openAIAPIKey: openAIAPIKey,
            anthropicAPIKey: anthropicAPIKey,
            openRouterModel: openRouterModel,
            openRouterAPIKey: openRouterAPIKey,
            groqModel: groqModel,
            groqAPIKey: groqAPIKey,
            huggingFaceModel: huggingFaceModel,
            huggingFaceAPIKey: huggingFaceAPIKey,
            dockerModelRunnerModel: dockerModelRunnerModel,
            dockerModelRunnerEndpoint: dockerModelRunnerEndpoint,
            vllmModel: vllmModel,
            vllmEndpoint: vllmEndpoint,
            vllmAPIKey: vllmAPIKey,
            gatewayPort: gatewayPort,
            setupComplete: setupComplete,
            heartbeatEnabled: heartbeatEnabled,
            heartbeatInterval: heartbeatInterval,
            heartbeatNudgesEnabled: heartbeatNudgesEnabled,
            nudgeLongIdle: nudgeLongIdle,
            nudgeLateNight: nudgeLateNight,
            nudgeMarathon: nudgeMarathon,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd,
            skillsTerminalEnabled: skillsTerminalEnabled,
            skillsBrowserEnabled: skillsBrowserEnabled,
            skillsAutoExecuteSafe: skillsAutoExecuteSafe
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
