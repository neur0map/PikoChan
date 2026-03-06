import Foundation

/// Coordinates memory extraction (after responses) and recall (before responses).
struct PikoMemory {

    // MARK: - Recall

    /// Returns semantically relevant memories using embedding cosine similarity.
    /// Uses Arctic Embed XS (384-dim, retrieval-optimized) with NLEmbedding fallback.
    /// Falls back to brute-force injection if no embedding is available.
    func recallRelevant(for prompt: String, from store: PikoStore?) -> [String] {
        guard let store else { return [] }
        if PikoEmbedding.isAvailable, let promptVec = PikoEmbedding.embedQuery(prompt) {
            let allVectors = store.allMemoryVectors()
            guard !allVectors.isEmpty else { return fallbackRecall(from: store) }
            let ranked = allVectors
                .map { ($0.fact, PikoEmbedding.cosineSimilarity(promptVec, $0.vector)) }
                .sorted { $0.1 > $1.1 }
                .prefix(15)
                .map { $0.0 }
            // If not all memories are vectorized, supplement with unvectorized ones.
            let unvectorized = store.memoriesWithoutVectors()
            if unvectorized.isEmpty { return Array(ranked) }
            let rankedSet = Set(ranked)
            let extras = unvectorized
                .suffix(10)
                .map { $0.fact }
                .filter { !rankedSet.contains($0) }
            return Array(ranked) + extras
        }
        return fallbackRecall(from: store)
    }

    /// All memories oldest-first — used when embedding is unavailable.
    private func fallbackRecall(from store: PikoStore) -> [String] {
        store.recentMemories(limit: 200).reversed()
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
                if let memoryId = store.saveMemory(fact: fact, turnId: turnId) {
                    PikoGateway.shared.logMemorySave(fact: fact, turnId: turnId)
                    if PikoEmbedding.isAvailable, let vec = PikoEmbedding.embed(fact) {
                        store.saveVector(memoryId: memoryId, vector: vec, embedder: PikoEmbedding.activeEmbedder.rawValue)
                    }
                }
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
