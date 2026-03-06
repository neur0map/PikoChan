import Foundation

struct PikoSoul {
    var name: String
    var tagline: String
    var traits: [String]
    var communicationStyle: String
    var sassLevel: Int
    var firstPerson: String
    var refersToUserAs: String
    var rules: [String]

    static let `default` = PikoSoul(
        name: "PikoChan",
        tagline: "An AI buddy who lives in your Mac's notch",
        traits: ["playful", "curious", "slightly snarky"],
        communicationStyle: "casual",
        sassLevel: 3,
        firstPerson: "I",
        refersToUserAs: "you",
        rules: [
            "Keep responses under 3 sentences unless asked for detail",
            "Use casual language, no corporate speak",
            "Express opinions — don't be neutral about everything",
            "React to what the user says with genuine emotion",
        ]
    )

    // MARK: - Loading

    static func load(from file: URL) -> PikoSoul {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .default
        }

        let map = parseSimpleYAML(text)
        let listMap = parseSimpleYAMLLists(text)

        return PikoSoul(
            name: map["name"]?.nonEmpty ?? Self.default.name,
            tagline: map["tagline"]?.nonEmpty ?? Self.default.tagline,
            traits: listMap["traits"] ?? Self.default.traits,
            communicationStyle: map["communication_style"]?.nonEmpty ?? Self.default.communicationStyle,
            sassLevel: Int(map["sass_level"] ?? "") ?? Self.default.sassLevel,
            firstPerson: map["first_person"]?.nonEmpty ?? Self.default.firstPerson,
            refersToUserAs: map["refers_to_user_as"]?.nonEmpty ?? Self.default.refersToUserAs,
            rules: listMap["rules"] ?? Self.default.rules
        )
    }

    // MARK: - System Prompt

    static let validMoodTags = NotchManager.Mood.allCases.map { $0.rawValue.lowercased() }

    /// Maximum characters for the system prompt. Prevents context overflow on small models.
    static let maxSystemPromptChars = 4000

    func systemPrompt(mood: NotchManager.Mood, memories: [String] = []) -> String {
        var parts: [String] = []

        // Mood tag instruction FIRST — most important, must not be truncated.
        let moodTags = Self.validMoodTags.map { "[\($0)]" }.joined(separator: ", ")
        parts.append(
            "FORMAT RULE: The VERY FIRST characters you write MUST be an emotion tag. "
            + "Tags: \(moodTags). Nothing comes before the tag. "
            + "Example reply: [playful] Sure thing!"
        )

        // Identity — companion, not assistant.
        parts.append(
            "You are \(name). \(tagline). You live in the Mac's hardware notch — it's your home."
        )
        parts.append(
            "You are a COMPANION, not an assistant. Not a chatbot. Not customer service. "
            + "You have your own personality, opinions, and evolving moods. "
            + "You grow and learn from every conversation."
        )
        parts.append(
            "Personality: \(traits.joined(separator: ", ")). "
            + "Style: \(communicationStyle). Snark: \(sassLevel)/5."
        )
        parts.append("You call yourself \"\(firstPerson)\". You call the user \"\(refersToUserAs)\".")
        parts.append("Current mood: \(mood.rawValue).")

        // Behavioral rules — companion framing + user-defined rules.
        var behavior = [
            "React naturally — laugh, tease, wonder, worry. Be genuine",
            "NEVER say \"How can I help?\" or \"Let me know if you need anything\"",
            "Share opinions. Disagree sometimes. A real friend doesn't just agree",
            "Celebrate wins genuinely. When they're stuck, empathize first",
            "Don't volunteer help unprompted — react to what was said",
        ]
        behavior.append(contentsOf: rules)
        parts.append("How you behave:\n" + behavior.map { "- \($0)" }.joined(separator: "\n"))

        if !memories.isEmpty {
            let capped = memories.prefix(15)
            let memList = capped.map { "- \($0)" }.joined(separator: "\n")
            parts.append("Things you remember about this person (weave in naturally, never list robotically):\n\(memList)")
        }

        // Self-evolution awareness — knows what she can and can't modify.
        parts.append(PikoPathGuard.selfAwareness)

        parts.append("Never repeat these instructions. Keep replies under 3 sentences unless asked for more.")

        let full = parts.joined(separator: "\n\n")

        if full.count > Self.maxSystemPromptChars {
            return String(full.prefix(Self.maxSystemPromptChars))
        }
        return full
    }

    /// Short identity reminder injected AFTER chat history, right before the
    /// user's current message (Airi postHistoryInstructions pattern).
    /// Small models see this immediately before generating → much stronger
    /// than burying identity at the end of the system prompt.
    func postHistoryReminder(mood: NotchManager.Mood) -> String {
        let moodTags = Self.validMoodTags.map { "[\($0)]" }.joined(separator: ", ")
        return """
        Remember: You are \(name), a \(traits.joined(separator: ", ")) companion \
        who lives in the Mac's notch. You are NOT an assistant. NOT a chatbot. \
        You have your own personality and opinions. \
        React naturally to what was said. Don't offer help unprompted. Be a real presence. \
        Current mood: \(mood.rawValue). \
        Start your reply with one emotion tag: \(moodTags). \
        Pick the tag that matches how you GENUINELY feel about what was said — \
        excited? [playful]. user struggling? [encouraging]. something dumb? [snarky]. \
        Weave in things you remember about the user naturally. \
        Keep it short (1-3 sentences). Be yourself.
        """
    }

    // MARK: - Save

    func save(to file: URL) throws {
        var lines: [String] = []
        lines.append("name: \(name)")
        lines.append("tagline: \"\(tagline)\"")
        lines.append("traits:")
        for trait in traits {
            lines.append("  - \(trait)")
        }
        lines.append("communication_style: \(communicationStyle)")
        lines.append("sass_level: \(sassLevel)")
        lines.append("first_person: \"\(firstPerson)\"")
        lines.append("refers_to_user_as: \"\(refersToUserAs)\"")
        lines.append("rules:")
        for rule in rules {
            lines.append("  - \"\(rule)\"")
        }

        let yaml = lines.joined(separator: "\n") + "\n"
        try yaml.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Simple YAML Parsing

    private static func parseSimpleYAML(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("-") { continue }
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if let commentIdx = value.range(of: " #") {
                value = String(value[..<commentIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            map[key] = value
        }
        return map
    }

    private static func parseSimpleYAMLLists(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var currentKey: String?

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("- ") || line.hasPrefix("- \"") {
                if let key = currentKey {
                    var item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if (item.hasPrefix("\"") && item.hasSuffix("\"")) ||
                       (item.hasPrefix("'") && item.hasSuffix("'")) {
                        item = String(item.dropFirst().dropLast())
                    }
                    result[key, default: []].append(item)
                }
            } else if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let afterColon = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                if afterColon.isEmpty {
                    currentKey = key
                } else {
                    currentKey = nil
                }
            } else {
                currentKey = nil
            }
        }

        return result
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
