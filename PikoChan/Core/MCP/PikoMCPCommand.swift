import Foundation

/// Parses `[mcp:...]` tags from LLM response text. Follows PikoCronCommand pattern.
///
/// Tag formats:
///   [mcp:install:{"name":"...","command":"...","args":[...],"env":{...}}]
///   [mcp:server_name.tool_name:{"arg":"value"}]
///   [mcp:remove:server_name]
///   [mcp:list]
enum PikoMCPCommand {

    enum Command {
        case install(PikoMCPServerConfig)
        case toolCall(serverName: String, toolName: String, arguments: [String: Any])
        case remove(serverName: String)
        case list
    }

    struct ParseResult {
        let cleanText: String
        let commands: [Command]
    }

    /// Parse all `[mcp:...]` tags from text, returning clean text with tags stripped.
    static func parse(from text: String) -> ParseResult {
        var cleanText = text
        var commands: [Command] = []

        // Simple commands: [mcp:list], [mcp:remove:NAME]
        let simplePattern = /\[mcp:(list|remove)(?::([^\]]*))?\]/
        for match in text.matches(of: simplePattern) {
            let action = String(match.1)
            let arg = match.2.map(String.init) ?? ""

            switch action {
            case "list":
                commands.append(.list)
            case "remove":
                if !arg.isEmpty { commands.append(.remove(serverName: arg)) }
            default:
                break
            }

            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Install command: [mcp:install:{...JSON...}]
        cleanText = parseInstallCommands(from: cleanText, into: &commands)

        // Tool call: [mcp:server.tool:{...JSON...}]
        cleanText = parseToolCallCommands(from: cleanText, into: &commands)

        // Collapse whitespace.
        while cleanText.contains("  ") {
            cleanText = cleanText.replacingOccurrences(of: "  ", with: " ")
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParseResult(cleanText: cleanText, commands: commands)
    }

    // MARK: - Install Parser

    /// Parse `[mcp:install:{...}]` tags using JSON-aware bracket counting.
    /// Truncated or malformed tags are stripped from the output (never shown to user).
    private static func parseInstallCommands(from text: String, into commands: inout [Command]) -> String {
        var result = text
        let prefix = "[mcp:install:"

        while let startRange = result.range(of: prefix) {
            let afterPrefix = startRange.upperBound

            guard let jsonEnd = findJSONEnd(in: result, from: afterPrefix),
                  jsonEnd < result.endIndex else {
                // Truncated JSON — strip from [mcp:install: to end of string.
                result = String(result[..<startRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }

            // Expect `]` after JSON.
            let closingIdx = jsonEnd
            guard closingIdx < result.endIndex, result[closingIdx] == "]" else {
                // Malformed — strip from tag start to end.
                result = String(result[..<startRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }

            let jsonStr = String(result[afterPrefix..<jsonEnd])
            let fullTag = String(result[startRange.lowerBound...closingIdx])

            if let config = parseInstallJSON(jsonStr) {
                commands.append(.install(config))
            }

            result = result.replacingOccurrences(of: fullTag, with: "")
        }

        return result
    }

    // MARK: - Tool Call Parser

    /// Parse `[mcp:server.tool:{...}]` tags.
    private static func parseToolCallCommands(from text: String, into commands: inout [Command]) -> String {
        var result = text

        // Find [mcp: followed by server.tool: pattern
        let toolPrefix = "[mcp:"

        while let startRange = result.range(of: toolPrefix) {
            let afterPrefix = startRange.upperBound

            // Skip if this is install/remove/list (already handled).
            let remaining = result[afterPrefix...]
            if remaining.hasPrefix("install:") || remaining.hasPrefix("remove:") ||
               remaining.hasPrefix("list") {
                // Move past this tag to avoid infinite loop.
                let endOfTag = remaining.firstIndex(of: "]")
                if let end = endOfTag {
                    let searchStart = result.index(after: end)
                    if searchStart >= result.endIndex { break }
                    let nextOccurrence = result[searchStart...].range(of: toolPrefix)
                    if nextOccurrence == nil { break }
                    continue
                }
                break
            }

            // Expect "server.tool:" or "server.tool:{" pattern.
            guard let colonIdx = remaining.firstIndex(of: ":") else { break }
            let qualifiedName = String(remaining[remaining.startIndex..<colonIdx])

            // Split on first dot.
            guard let dotIdx = qualifiedName.firstIndex(of: ".") else { break }
            let serverName = String(qualifiedName[..<dotIdx])
            let toolName = String(qualifiedName[qualifiedName.index(after: dotIdx)...])

            guard !serverName.isEmpty, !toolName.isEmpty else { break }

            let afterColon = result.index(after: colonIdx)
            guard afterColon < result.endIndex else { break }

            // Check if there's a JSON body or just empty {}.
            if result[afterColon] == "{" {
                guard let jsonEnd = findJSONEnd(in: result, from: afterColon),
                      jsonEnd < result.endIndex, result[jsonEnd] == "]" else {
                    break
                }

                let jsonStr = String(result[afterColon..<jsonEnd])
                let fullTag = String(result[startRange.lowerBound...jsonEnd])

                if let jsonData = jsonStr.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    commands.append(.toolCall(serverName: serverName, toolName: toolName, arguments: args))
                } else {
                    commands.append(.toolCall(serverName: serverName, toolName: toolName, arguments: [:]))
                }

                result = result.replacingOccurrences(of: fullTag, with: "")
            } else {
                // No JSON args — find closing bracket.
                guard let closingIdx = remaining.firstIndex(of: "]") else { break }
                let fullTag = String(result[startRange.lowerBound...closingIdx])
                commands.append(.toolCall(serverName: serverName, toolName: toolName, arguments: [:]))
                result = result.replacingOccurrences(of: fullTag, with: "")
            }
        }

        return result
    }

    // MARK: - JSON Bracket Counter

    /// Find the end of a JSON object starting at `from`, tracking `{`/`}` nesting
    /// and skipping characters inside quoted strings. Returns the index AFTER
    /// the closing `}`.
    private static func findJSONEnd(in text: String, from start: String.Index) -> String.Index? {
        guard start < text.endIndex, text[start] == "{" else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var idx = start

        while idx < text.endIndex {
            let ch = text[idx]

            if escaped {
                escaped = false
                idx = text.index(after: idx)
                continue
            }

            if ch == "\\" && inString {
                escaped = true
                idx = text.index(after: idx)
                continue
            }

            if ch == "\"" {
                inString.toggle()
                idx = text.index(after: idx)
                continue
            }

            if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return text.index(after: idx)
                    }
                }
            }

            idx = text.index(after: idx)
        }

        return nil
    }

    // MARK: - Install JSON Parsing

    private static func parseInstallJSON(_ jsonStr: String) -> PikoMCPServerConfig? {
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, !name.isEmpty,
              let command = json["command"] as? String, !command.isEmpty
        else { return nil }

        let args = json["args"] as? [String] ?? []
        let env = json["env"] as? [String: String] ?? [:]

        return PikoMCPServerConfig(
            name: name,
            command: command,
            args: args,
            env: env
        )
    }
}
