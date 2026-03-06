import Foundation

/// Coordinates memory extraction (after responses) and recall (before responses).
struct PikoMemory {

    // MARK: - Recall

    /// Returns all stored memories (up to limit), scored by temporal decay.
    /// Keyword filtering was too rigid for small models — just inject everything.
    /// With few memories (<50) this is cheap and much more reliable.
    func recallRelevant(for prompt: String, from store: PikoStore?) -> [String] {
        guard let store else { return [] }
        // Fetch all memories and return oldest-first so core identity facts
        // (name, city, birthday) get priority over recent conversational noise.
        let all = store.recentMemories(limit: 200) // newest-first from DB
        return all.reversed() // oldest-first → core facts first
    }

    // MARK: - Extraction

    @MainActor
    func extractAndStore(from turn: ChatTurn, turnId: Int?, using brain: PikoBrain) async {
        guard let store = brain.store else { return }

        // Use respondInternal() — a bare LLM call WITHOUT personality context.
        // This prevents the model from being confused by PikoChan's personality
        // framing when it should be doing simple fact extraction.
        let extractionPrompt = """
        Extract facts about the user from this conversation. Return a JSON array of short factual statements. Only include facts about the USER (name, preferences, interests, job, etc). Return [] if none.

        User said: \(turn.user)
        Reply was: \(turn.assistant)

        JSON array only, nothing else. Example: ["User's name is Alex", "User likes dark mode"]
        """

        do {
            let response = try await brain.respondInternal(to: extractionPrompt)
            let facts = parseFactsJSON(response)
            for fact in facts {
                store.saveMemory(fact: fact, turnId: turnId)
                PikoGateway.shared.logMemorySave(fact: fact, turnId: turnId)
            }
            if !facts.isEmpty {
                PikoGateway.shared.logMemoryExtract(userMessage: turn.user, facts: facts)
                appendToJournal(facts: facts, journalFile: brain.home.journalFile)
            }
        } catch {
            PikoGateway.shared.logError(
                message: "Memory extraction failed: \(error.localizedDescription)",
                subsystem: .memory
            )
        }
    }

    private func parseFactsJSON(_ response: String) -> [String] {
        // Find JSON array in response (may have surrounding text).
        guard let start = response.firstIndex(of: "["),
              let end = response.lastIndex(of: "]")
        else { return [] }

        let jsonString = String(response[start...end])
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data)
        else { return [] }

        // Handle both flat ["fact1", "fact2"] and nested [["fact1", "fact2"]] from small models.
        if let array = raw as? [String] {
            return array.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let nested = raw as? [[String]] {
            return nested.flatMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return []
    }

    private func appendToJournal(facts: [String], journalFile: URL) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateHeader = "## \(formatter.string(from: .now))"

        var existing = (try? String(contentsOf: journalFile, encoding: .utf8)) ?? ""

        // Add date header if not already present for today.
        if !existing.contains(dateHeader) {
            if !existing.hasSuffix("\n") { existing += "\n" }
            existing += "\n\(dateHeader)\n"
        }

        for fact in facts {
            existing += "- \(fact)\n"
        }

        try? existing.write(to: journalFile, atomically: true, encoding: .utf8)
    }
}
