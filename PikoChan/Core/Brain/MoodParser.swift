import Foundation

enum MoodParser {

    /// Parses an emotion tag from the start of a response.
    /// Returns the detected mood (if any) and the text with the tag stripped.
    ///
    /// Supports tags like `[playful]`, `[irritated]`, etc.
    /// Case-insensitive. If no valid tag is found, mood is nil and text is unchanged.
    static func parse(from response: String) -> (mood: NotchManager.Mood?, cleanText: String) {
        // First try: tag at the very start (ideal case).
        let startPattern = #"^\s*\[(\w+)\]\s*:?\s*"#
        if let regex = try? NSRegularExpression(pattern: startPattern),
           let match = regex.firstMatch(
               in: response,
               range: NSRange(response.startIndex..., in: response)
           ),
           let tagRange = Range(match.range(at: 1), in: response) {
            let tag = String(response[tagRange]).lowercased()
            if let mood = NotchManager.Mood.allCases.first(where: { $0.rawValue.lowercased() == tag }) {
                let fullMatchRange = Range(match.range(at: 0), in: response)!
                let cleanText = String(response[fullMatchRange.upperBound...])
                return (mood, cleanText)
            }
        }

        // Fallback: tag anywhere in the first 200 chars (phi4-mini sometimes
        // puts text before the tag or uses "[Tag]:" format mid-sentence).
        let prefix = String(response.prefix(200))
        let anyPattern = #"\[(\w+)\]\s*:?\s*"#
        if let regex = try? NSRegularExpression(pattern: anyPattern),
           let match = regex.firstMatch(
               in: prefix,
               range: NSRange(prefix.startIndex..., in: prefix)
           ),
           let tagRange = Range(match.range(at: 1), in: prefix) {
            let tag = String(prefix[tagRange]).lowercased()
            if let mood = NotchManager.Mood.allCases.first(where: { $0.rawValue.lowercased() == tag }) {
                // Strip the tag from wherever it appears.
                let fullMatchRange = Range(match.range(at: 0), in: prefix)!
                let before = String(response[..<fullMatchRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let after = String(response[fullMatchRange.upperBound...])
                let cleanText = before.isEmpty ? after : before + " " + after
                return (mood, cleanText)
            }
        }

        return (nil, response)
    }

    /// Attempts to extract an emotion tag from a partial (still-streaming) response.
    /// Returns the mood as soon as the closing `]` is found, or nil if not yet complete.
    static func parsePartial(from accumulated: String) -> NotchManager.Mood? {
        // Look for a mood tag anywhere in the first 200 chars of accumulated text.
        let prefix = String(accumulated.prefix(200))
        let pattern = #"\[(\w+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: prefix,
                  range: NSRange(prefix.startIndex..., in: prefix)
              ),
              let tagRange = Range(match.range(at: 1), in: prefix)
        else {
            return nil
        }

        let tag = String(prefix[tagRange]).lowercased()
        return NotchManager.Mood.allCases.first { $0.rawValue.lowercased() == tag }
    }
}
