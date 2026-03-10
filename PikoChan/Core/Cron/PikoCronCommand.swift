import Foundation

/// Parses `[cron:...]` tags from LLM response text. Follows PikoConfigCommand pattern.
enum PikoCronCommand {

    enum Command {
        case add(name: String, schedule: PikoCronSchedule, payload: PikoCronPayload)
        case remove(nameOrID: String)
        case list
        case run(nameOrID: String)
        case pause(nameOrID: String)
        case resume(nameOrID: String)
    }

    struct ParseResult {
        let cleanText: String
        let commands: [Command]
    }

    /// Parse all `[cron:...]` tags from text, returning clean text with tags stripped.
    static func parse(from text: String) -> ParseResult {
        var cleanText = text
        var commands: [Command] = []

        // Simple commands: [cron:list], [cron:remove:NAME], [cron:run:NAME], [cron:pause:NAME], [cron:resume:NAME]
        let simplePattern = /\[cron:(list|remove|run|pause|resume)(?::([^\]]*))?\]/
        for match in text.matches(of: simplePattern) {
            let action = String(match.1)
            let arg = match.2.map(String.init) ?? ""

            switch action {
            case "list":
                commands.append(.list)
            case "remove":
                if !arg.isEmpty { commands.append(.remove(nameOrID: arg)) }
            case "run":
                if !arg.isEmpty { commands.append(.run(nameOrID: arg)) }
            case "pause":
                if !arg.isEmpty { commands.append(.pause(nameOrID: arg)) }
            case "resume":
                if !arg.isEmpty { commands.append(.resume(nameOrID: arg)) }
            default:
                break
            }

            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Add command: [cron:add:NAME:SCHEDULE_TYPE:SCHEDULE_VALUE:PAYLOAD]
        // Complex parse — walk through each [cron:add:...] tag manually.
        cleanText = parseAddCommands(from: cleanText, into: &commands)

        // Collapse double spaces.
        while cleanText.contains("  ") {
            cleanText = cleanText.replacingOccurrences(of: "  ", with: " ")
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParseResult(cleanText: cleanText, commands: commands)
    }

    // MARK: - Add Command Parser

    /// Parse `[cron:add:NAME:SCHEDULE_TYPE:SCHEDULE_VALUE...:PAYLOAD]` tags.
    ///
    /// Token layout:
    ///   [cron:add:NAME:TYPE:VALUE...:PAYLOAD...]
    ///
    /// TYPE determines how many tokens SCHEDULE_VALUE consumes:
    /// - `in`, `every`: 1 token (e.g., "2h", "30m")
    /// - `at`: 1 token (ISO8601 date)
    /// - `cron`: 5 tokens (minute hour dayOfMonth month dayOfWeek)
    ///
    /// Remaining tokens after schedule → payload.
    /// Payload starts with `shell:`, `open:`, or plain text (reminder).
    /// Payload tokens rejoin with `:` (preserves URLs like http://host:port/path).
    private static func parseAddCommands(from text: String, into commands: inout [Command]) -> String {
        var result = text
        let addPrefix = "[cron:add:"

        while let startRange = result.range(of: addPrefix) {
            // Find the closing bracket.
            guard let endIdx = result[startRange.upperBound...].firstIndex(of: "]") else { break }

            let tagContent = String(result[startRange.upperBound..<endIdx])
            let fullTag = String(result[startRange.lowerBound...endIdx])

            if let cmd = parseAddContent(tagContent) {
                commands.append(cmd)
            }

            result = result.replacingOccurrences(of: fullTag, with: "")
        }

        return result
    }

    /// Parse the content inside `[cron:add:...]` (everything between `add:` and `]`).
    private static func parseAddContent(_ content: String) -> Command? {
        // Split by `:` but we need to be careful about colons in values.
        let tokens = content.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard tokens.count >= 3 else { return nil } // Need at least: name, schedType, schedValue

        let name = tokens[0]
        let schedType = tokens[1].lowercased()
        var cursor = 2

        // Parse schedule.
        let schedule: PikoCronSchedule?
        switch schedType {
        case "in":
            guard cursor < tokens.count else { return nil }
            let value = tokens[cursor]
            cursor += 1
            guard let secs = PikoCronSchedule.parseDuration(value) else { return nil }
            schedule = .at(Date().addingTimeInterval(secs))

        case "every":
            guard cursor < tokens.count else { return nil }
            let value = tokens[cursor]
            cursor += 1
            guard let secs = PikoCronSchedule.parseDuration(value) else { return nil }
            schedule = .every(secs)

        case "at":
            guard cursor < tokens.count else { return nil }
            // Rejoin remaining date tokens (in case ISO date contains colons like "09:00:00").
            // Take tokens until we hit a payload keyword or run out.
            var dateTokens: [String] = []
            while cursor < tokens.count {
                let tok = tokens[cursor]
                if tok.hasPrefix("shell") || tok.hasPrefix("open") || tok.hasPrefix("reminder") {
                    break
                }
                dateTokens.append(tok)
                cursor += 1
            }
            let dateStr = dateTokens.joined(separator: ":")
            guard let parsed = PikoCronSchedule.parse(from: "at:\(dateStr)") else { return nil }
            schedule = parsed

        case "cron":
            // 5 tokens for cron fields.
            guard cursor + 5 <= tokens.count else { return nil }
            let cronFields = tokens[cursor..<cursor+5].joined(separator: " ")
            cursor += 5
            schedule = .cron(cronFields)

        default:
            return nil
        }

        guard let schedule else { return nil }

        // Remaining tokens → payload. Rejoin with `:`.
        let payloadStr: String
        if cursor < tokens.count {
            payloadStr = tokens[cursor...].joined(separator: ":")
        } else {
            // No payload tokens — use name as reminder text.
            payloadStr = name
        }

        let payload = parsePayload(payloadStr)
        return .add(name: name, schedule: schedule, payload: payload)
    }

    private static func parsePayload(_ string: String) -> PikoCronPayload {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("shell:") {
            return .shell(String(trimmed.dropFirst(6)))
        }
        if trimmed.hasPrefix("open:") {
            return .open(String(trimmed.dropFirst(5)))
        }
        return .reminder(trimmed)
    }
}
