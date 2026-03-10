import Foundation

/// Orchestrates all MCP server connections, tool discovery, and auto-skill generation.
@Observable
@MainActor
final class PikoMCPManager {

    static let shared = PikoMCPManager()

    var servers: [PikoMCPServerConfig] = []
    private(set) var transports: [String: PikoMCPTransport] = [:]

    private let home = PikoHome()
    private let gateway = PikoGateway.shared

    // MARK: - Persistence

    func loadServers() {
        let file = home.mcpServersFile
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return }

        servers = parseServersYAML(text)

        // Auto-start enabled servers.
        for config in servers where config.enabled {
            Task {
                do {
                    var runtimeConfig = config
                    runtimeConfig.env = self.resolveSecretsFromKeychain(serverName: config.name, env: config.env)
                    let transport = PikoMCPTransport(config: runtimeConfig)
                    self.transports[config.name] = transport
                    try await transport.start()
                } catch {
                    self.gateway.logMCPServerError(name: config.name, error: error.localizedDescription)
                }
            }
        }
    }

    func saveServers() {
        let yaml = buildServersYAML()
        try? yaml.write(to: home.mcpServersFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Install / Remove

    func installServer(_ config: PikoMCPServerConfig, brain: PikoBrain?) async throws {
        // Remove existing with same name.
        if let idx = servers.firstIndex(where: { $0.name == config.name }) {
            clearKeychainEntries(for: config.name)
            transports[config.name]?.stop()
            transports.removeValue(forKey: config.name)
            servers.remove(at: idx)
        }

        // Store sensitive env values in Keychain, replace with sentinel.
        var safeConfig = config
        safeConfig.env = storeSecretsInKeychain(serverName: config.name, env: config.env)

        servers.append(safeConfig)
        saveServers()

        // Transport gets resolved env (secrets from Keychain).
        var runtimeConfig = safeConfig
        runtimeConfig.env = resolveSecretsFromKeychain(serverName: safeConfig.name, env: safeConfig.env)
        let transport = PikoMCPTransport(config: runtimeConfig)
        transports[safeConfig.name] = transport
        try await transport.start()

        gateway.logMCPInstall(name: safeConfig.name, toolCount: transport.tools.count)

        // Auto-generate skill file via internal LLM call.
        if let brain, !transport.tools.isEmpty {
            await generateSkillFile(for: safeConfig.name, tools: transport.tools, brain: brain)
        }
    }

    func removeServer(name: String) {
        clearKeychainEntries(for: name)
        transports[name]?.stop()
        transports.removeValue(forKey: name)
        servers.removeAll { $0.name == name }
        saveServers()

        // Remove auto-generated skill file.
        let skillFile = home.mcpSkillsDir.appendingPathComponent("\(name).md")
        try? FileManager.default.removeItem(at: skillFile)

        PikoSkillLoader.shared.reload()
        gateway.logMCPRemove(name: name)
    }

    func stopAll() {
        for (_, transport) in transports {
            transport.stop()
        }
        transports.removeAll()
    }

    func restartServer(name: String) async throws {
        guard let config = servers.first(where: { $0.name == name }) else { return }
        transports[name]?.stop()
        var runtimeConfig = config
        runtimeConfig.env = resolveSecretsFromKeychain(serverName: config.name, env: config.env)
        let transport = PikoMCPTransport(config: runtimeConfig)
        transports[name] = transport
        try await transport.start()
    }

    // MARK: - Tool Calls

    func callTool(serverName: String, toolName: String, arguments: [String: Any]) async throws -> PikoMCPToolResult {
        guard let transport = transports[serverName] else {
            // Try lazy start.
            guard let config = servers.first(where: { $0.name == serverName }) else {
                throw MCPError.toolNotFound("\(serverName).\(toolName)")
            }
            var runtimeConfig = config
            runtimeConfig.env = resolveSecretsFromKeychain(serverName: config.name, env: config.env)
            let newTransport = PikoMCPTransport(config: runtimeConfig)
            transports[serverName] = newTransport
            try await newTransport.start()
            return try await newTransport.callTool(name: toolName, arguments: arguments)
        }
        return try await transport.callTool(name: toolName, arguments: arguments)
    }

    // MARK: - Tool Schemas for System Prompt

    var allTools: [PikoMCPTool] {
        transports.values.flatMap(\.tools)
    }

    func buildToolSchemasBlock() -> String {
        let readyTransports = transports.values.filter { $0.status == .ready && !$0.tools.isEmpty }
        guard !readyTransports.isEmpty else { return "" }

        var lines = ["<mcp_tools>"]
        for transport in readyTransports {
            lines.append("<server name=\"\(transport.config.name)\">")
            var serverChars = 0
            for tool in transport.tools {
                let params = formatParams(tool.inputSchema)
                let entry = "<tool name=\"\(tool.name)\">\(tool.description). Params: \(params)</tool>"
                if serverChars + entry.count > 1000 { break }
                lines.append(entry)
                serverChars += entry.count
            }
            lines.append("</server>")
        }
        lines.append("</mcp_tools>")
        return lines.joined(separator: "\n")
    }

    func statusForServer(name: String) -> PikoMCPServerStatus {
        transports[name]?.status ?? .stopped
    }

    func toolCountForServer(name: String) -> Int {
        transports[name]?.tools.count ?? 0
    }

    // MARK: - Auto Skill Generation

    private func generateSkillFile(for serverName: String, tools: [PikoMCPTool], brain: PikoBrain) async {
        let toolDescriptions = tools.map { tool -> String in
            let params = formatParams(tool.inputSchema)
            return "- \(tool.name): \(tool.description). Params: \(params)"
        }.joined(separator: "\n")

        let prompt = """
        You are writing brief instructions for an MCP tool server named "\(serverName)".
        These tools are available:
        \(toolDescriptions)

        Write a SHORT skill file (under 300 words) explaining:
        1. What this server does (1 sentence)
        2. When to use it (1 sentence)
        3. Example [mcp:\(serverName).TOOL_NAME:{"param":"value"}] tags for the most useful tools

        Use the exact tag format: [mcp:SERVER.TOOL:{"args"}]
        Be concise. No markdown headers.
        """

        do {
            let instructions = try await brain.respondInternal(to: prompt)
            let skillContent = """
            ---
            name: \(serverName) (MCP)
            description: Auto-generated MCP tool instructions for \(serverName)
            permissions:
              - mcp
            ---

            \(instructions.trimmingCharacters(in: .whitespacesAndNewlines))
            """

            let skillFile = home.mcpSkillsDir.appendingPathComponent("\(serverName).md")
            try skillContent.write(to: skillFile, atomically: true, encoding: .utf8)
            PikoSkillLoader.shared.reload()
        } catch {
            gateway.logError(
                message: "Failed to generate skill for \(serverName): \(error.localizedDescription)",
                subsystem: .mcp
            )
        }
    }

    // MARK: - Keychain Secrets

    /// Sentinel value stored in YAML instead of the real secret.
    private static let keychainSentinel = "__keychain__"

    /// Env key patterns that indicate sensitive values.
    private static let secretPatterns = ["KEY", "SECRET", "TOKEN", "PASSWORD", "CREDENTIAL"]

    /// Returns true if an env key looks like a secret.
    private func isSensitiveKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        return Self.secretPatterns.contains { upper.contains($0) }
    }

    /// Keychain account name for an MCP server env var.
    private func keychainAccount(serverName: String, envKey: String) -> String {
        "mcp_\(serverName)_\(envKey)"
    }

    /// Stores sensitive env values in Keychain, returns env dict with sentinels.
    func storeSecretsInKeychain(serverName: String, env: [String: String]) -> [String: String] {
        var safeEnv = env
        for (key, value) in env {
            if isSensitiveKey(key) && value != Self.keychainSentinel {
                PikoKeychain.save(account: keychainAccount(serverName: serverName, envKey: key), value: value)
                safeEnv[key] = Self.keychainSentinel
            }
        }
        return safeEnv
    }

    /// Resolves sentinel values from Keychain back to real secrets.
    func resolveSecretsFromKeychain(serverName: String, env: [String: String]) -> [String: String] {
        var resolved = env
        for (key, value) in env {
            if value == Self.keychainSentinel {
                if let secret = PikoKeychain.load(account: keychainAccount(serverName: serverName, envKey: key)) {
                    resolved[key] = secret
                }
            }
        }
        return resolved
    }

    /// Removes all Keychain entries for a server.
    private func clearKeychainEntries(for serverName: String) {
        guard let config = servers.first(where: { $0.name == serverName }) else { return }
        for (key, value) in config.env where value == Self.keychainSentinel {
            PikoKeychain.delete(account: keychainAccount(serverName: serverName, envKey: key))
        }
    }

    // MARK: - YAML Parsing

    private func parseServersYAML(_ text: String) -> [PikoMCPServerConfig] {
        // Simple YAML parser for servers list.
        // Format: servers: [{id, name, command, args, env, enabled}]
        // Since our YAML is simple, we parse it manually.
        var configs: [PikoMCPServerConfig] = []
        var currentServer: [String: String] = [:]
        var currentArgs: [String] = []
        var currentEnv: [String: String] = [:]
        var inArgs = false
        var inEnv = false
        var inServers = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "servers:" || trimmed == "servers: []" {
                inServers = true
                if trimmed == "servers: []" { return [] }
                continue
            }

            guard inServers else { continue }

            // New server entry.
            if trimmed.hasPrefix("- name:") || trimmed.hasPrefix("-  name:") {
                // Save previous server if any.
                if !currentServer.isEmpty {
                    if let cfg = buildConfig(from: currentServer, args: currentArgs, env: currentEnv) {
                        configs.append(cfg)
                    }
                }
                currentServer = [:]
                currentArgs = []
                currentEnv = [:]
                inArgs = false
                inEnv = false
                let value = extractValue(from: trimmed.replacingOccurrences(of: "- ", with: ""))
                currentServer["name"] = value.key == "name" ? value.val : ""
                continue
            }

            if trimmed.hasPrefix("- ") && inArgs {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentArgs.append(unquote(item))
                continue
            }

            if inEnv && trimmed.contains(":") && !trimmed.hasPrefix("args:") && !trimmed.hasPrefix("enabled:") && !trimmed.hasPrefix("command:") && !trimmed.hasPrefix("id:") {
                let kv = extractValue(from: trimmed)
                currentEnv[kv.key] = kv.val
                continue
            }

            if trimmed.hasPrefix("args:") {
                inArgs = true
                inEnv = false
                continue
            }
            if trimmed.hasPrefix("env:") {
                inEnv = true
                inArgs = false
                continue
            }
            if trimmed.hasPrefix("command:") || trimmed.hasPrefix("id:") || trimmed.hasPrefix("enabled:") {
                inArgs = false
                inEnv = false
            }

            let kv = extractValue(from: trimmed)
            if !kv.key.isEmpty {
                currentServer[kv.key] = kv.val
            }
        }

        // Save last server.
        if !currentServer.isEmpty {
            if let cfg = buildConfig(from: currentServer, args: currentArgs, env: currentEnv) {
                configs.append(cfg)
            }
        }

        return configs
    }

    private func buildConfig(from map: [String: String], args: [String], env: [String: String]) -> PikoMCPServerConfig? {
        guard let name = map["name"], !name.isEmpty,
              let command = map["command"], !command.isEmpty else { return nil }
        let enabled = map["enabled"]?.lowercased() != "false"
        return PikoMCPServerConfig(
            name: name, command: command, args: args,
            env: env, enabled: enabled
        )
    }

    private func extractValue(from line: String) -> (key: String, val: String) {
        guard let colonIdx = line.firstIndex(of: ":") else { return ("", "") }
        let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
        var val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        val = unquote(val)
        return (key, val)
    }

    private func unquote(_ s: String) -> String {
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) ||
           (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private func buildServersYAML() -> String {
        guard !servers.isEmpty else { return "servers: []\n" }
        var lines = ["servers:"]
        for cfg in servers {
            lines.append("  - name: \(cfg.name)")
            lines.append("    id: \(cfg.id)")
            lines.append("    command: \(cfg.command)")
            lines.append("    args:")
            for arg in cfg.args {
                lines.append("      - \"\(arg)\"")
            }
            if !cfg.env.isEmpty {
                lines.append("    env:")
                for (k, v) in cfg.env.sorted(by: { $0.key < $1.key }) {
                    lines.append("      \(k): \"\(v)\"")
                }
            }
            lines.append("    enabled: \(cfg.enabled)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Param Formatting

    private func formatParams(_ schema: [String: Any]) -> String {
        guard let properties = schema["properties"] as? [String: Any] else { return "{}" }
        let required = schema["required"] as? [String] ?? []
        let params = properties.keys.sorted().map { key -> String in
            let isReq = required.contains(key)
            return "\(key)\(isReq ? "*" : "")"
        }
        return "{\(params.joined(separator: ", "))}"
    }
}
