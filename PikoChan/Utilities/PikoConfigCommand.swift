import Foundation

/// Parses `[config:key=value]` and `[nudge_after:SECONDS:MESSAGE]` tags from
/// PikoChan's responses. Tags are stripped from display text and applied as side effects.
enum PikoConfigCommand {

    struct ParseResult {
        let cleanText: String
        let configChanges: [String: String]
        let scheduledNudge: ScheduledNudge?
    }

    struct ScheduledNudge {
        let delaySeconds: Int
        let message: String
    }

    /// Parses all command tags from response text. Returns cleaned text + extracted commands.
    static func parse(from text: String) -> ParseResult {
        var cleanText = text
        var configChanges: [String: String] = [:]
        var scheduledNudge: ScheduledNudge?

        // Parse [config:key=value] tags.
        let configPattern = /\[config:([a-z_]+)=([^\]]+)\]/
        for match in text.matches(of: configPattern) {
            let key = String(match.1)
            let value = String(match.2)
            configChanges[key] = value
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Parse [nudge_after:SECONDS:MESSAGE] tag (only first one).
        let nudgePattern = /\[nudge_after:(\d+):([^\]]+)\]/
        if let match = text.firstMatch(of: nudgePattern) {
            if let seconds = Int(match.1) {
                scheduledNudge = ScheduledNudge(
                    delaySeconds: max(5, seconds),
                    message: String(match.2)
                )
            }
            cleanText = cleanText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Clean up whitespace artifacts from tag removal.
        cleanText = cleanText
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParseResult(
            cleanText: cleanText,
            configChanges: configChanges,
            scheduledNudge: scheduledNudge
        )
    }

    /// Applies parsed config changes to PikoConfigStore and saves.
    @MainActor
    static func applyConfigChanges(_ changes: [String: String]) {
        guard !changes.isEmpty else { return }
        let config = PikoConfigStore.shared

        for (key, value) in changes {
            switch key {
            case "heartbeat_enabled":
                config.heartbeatEnabled = value == "true"
            case "heartbeat_interval":
                if let v = Int(value) { config.heartbeatInterval = max(15, v) }
            case "heartbeat_nudges_enabled":
                config.heartbeatNudgesEnabled = value == "true"
            case "nudge_long_idle":
                config.nudgeLongIdle = value == "true"
            case "nudge_late_night":
                config.nudgeLateNight = value == "true"
            case "nudge_marathon":
                config.nudgeMarathon = value == "true"
            case "quiet_hours_start":
                if let v = Int(value), (0...23).contains(v) { config.quietHoursStart = v }
            case "quiet_hours_end":
                if let v = Int(value), (0...23).contains(v) { config.quietHoursEnd = v }
            default:
                break
            }
        }

        try? config.save()

        PikoGateway.shared.logConfigReload(
            provider: config.provider.rawValue,
            model: config.openAIModel
        )
    }
}
