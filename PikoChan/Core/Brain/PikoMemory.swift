import Foundation

/// Coordinates memory extraction (after responses) and recall (before responses).
struct PikoMemory {

    /// Max characters for recalled memories injected into the system prompt.
    private static let maxRecallChars = 600
    /// Minimum cosine similarity to include a vectorized memory.
    private static let minSimilarity: Double = 0.3

    // MARK: - Recall

    /// Returns semantically relevant memories using embedding cosine similarity.
    /// Uses Arctic Embed XS (384-dim, retrieval-optimized) with NLEmbedding fallback.
    /// Falls back to brute-force injection if no embedding is available.
    /// Results are budget-capped to ~600 chars to limit system prompt token usage.
    func recallRelevant(for prompt: String, from store: PikoStore?) -> [String] {
        guard let store else { return [] }
        if PikoEmbedding.isAvailable, let promptVec = PikoEmbedding.embedQuery(prompt) {
            let allVectors = store.allMemoryVectors()
            guard !allVectors.isEmpty else { return fallbackRecall(from: store) }
            let ranked = allVectors
                .map { ($0.fact, PikoEmbedding.cosineSimilarity(promptVec, $0.vector)) }
                .filter { $0.1 >= Self.minSimilarity }
                .sorted { $0.1 > $1.1 }
            let budgeted = budgetCap(ranked.map { $0.0 })

            // If not all memories are vectorized, supplement with unvectorized ones.
            let unvectorized = store.memoriesWithoutVectors()
            if unvectorized.isEmpty { return budgeted }
            let budgetUsed = budgeted.reduce(0) { $0 + $1.count + 3 }
            let remaining = Self.maxRecallChars - budgetUsed
            guard remaining > 0 else { return budgeted }
            let rankedSet = Set(budgeted)
            let extras = budgetCap(
                unvectorized.map { $0.fact }.filter { !rankedSet.contains($0) },
                budget: remaining
            )
            return budgeted + extras
        }
        return fallbackRecall(from: store)
    }

    /// All memories oldest-first — used when embedding is unavailable.
    /// Budget-capped to limit system prompt token usage.
    private func fallbackRecall(from store: PikoStore) -> [String] {
        let all = store.recentMemories(limit: 200).reversed()
        return budgetCap(Array(all))
    }

    /// Walk memories accumulating chars until budget is exceeded.
    /// Each memory costs `fact.count + 3` chars (for `"- "` prefix + `"\n"` suffix).
    private func budgetCap(_ memories: [String], budget: Int = PikoMemory.maxRecallChars) -> [String] {
        var result: [String] = []
        var chars = 0
        for fact in memories {
            let cost = fact.count + 3
            if chars + cost > budget { break }
            chars += cost
            result.append(fact)
        }
        return result
    }

    // MARK: - Extraction

    @MainActor
    func extractAndStore(from turn: ChatTurn, turnId: Int?, using brain: PikoBrain) async {
        // Skip extraction on trivial messages — "hi", "ok", "lol", etc.
        if turn.user.count < 15 && turn.assistant.count < 100 {
            PikoGateway.shared.logExtractionSkip(
                reason: "trivial_message",
                userChars: turn.user.count,
                assistantChars: turn.assistant.count
            )
            return
        }

        guard let store = brain.store else { return }

        // Smart dedup: embed the user message, find top-5 most similar existing memories.
        // This replaces dumping 50 memories (~3000 chars) with ~5 relevant ones (~300 chars).
        let existing: [String]
        if PikoEmbedding.isAvailable, let queryVec = PikoEmbedding.embedQuery(turn.user) {
            let allVectors = store.allMemoryVectors()
            existing = allVectors
                .map { ($0.fact, PikoEmbedding.cosineSimilarity(queryVec, $0.vector)) }
                .sorted { $0.1 > $1.1 }
                .prefix(5)
                .map { $0.0 }
        } else {
            existing = store.recentMemories(limit: 10)
        }
        let existingList = existing.isEmpty ? "None yet." : existing.map { "- \($0)" }.joined(separator: "\n")

        // Load current personality rules for dedup.
        let currentRules = brain.soul.rules

        // Use respondInternal() — a bare LLM call WITHOUT personality context.
        // Single call extracts both user facts AND behavioral rules.
        let extractionPrompt = """
        Analyze this conversation and extract TWO things:

        1. "facts": NEW facts about the user (name, preferences, interests, job, etc).
        2. "rules": Behavioral instructions the user gave about how you should act.
           Examples of rules: "Don't ask me a question every time", "Be more direct", "Stop bringing up old topics".
           Only extract rules when the user is clearly giving feedback about YOUR behavior.

        Already known facts (do NOT repeat these):
        \(existingList)

        User said: \(turn.user)
        Reply was: \(turn.assistant)

        Return JSON only: {"facts": [...], "rules": [...]}
        Use empty arrays if nothing new. Example: {"facts": ["User works at NASA"], "rules": []}
        """

        do {
            let response = try await brain.respondInternal(to: extractionPrompt)
            let (facts, rules) = parseCombinedJSON(response)

            // Save new facts to memory.
            // Broad string-match dedup (cheap, no LLM cost) — catches exact duplicates.
            let allExisting = store.recentMemories(limit: 200)
            let existingLower = Set(allExisting.map { $0.lowercased() })
            var savedFacts: [String] = []
            for fact in facts {
                if existingLower.contains(fact.lowercased()) { continue }
                if let memoryId = store.saveMemory(fact: fact, turnId: turnId) {
                    savedFacts.append(fact)
                    PikoGateway.shared.logMemorySave(fact: fact, turnId: turnId)
                    if PikoEmbedding.isAvailable, let vec = PikoEmbedding.embed(fact) {
                        store.saveVector(memoryId: memoryId, vector: vec, embedder: PikoEmbedding.activeEmbedder.rawValue)
                    }
                }
            }
            if !savedFacts.isEmpty {
                PikoGateway.shared.logMemoryExtract(userMessage: turn.user, facts: savedFacts)
                appendToJournal(facts: savedFacts, journalFile: brain.home.journalFile)
            }

            // Apply behavioral rules → soul evolution.
            let rulesLower = Set(currentRules.map { $0.lowercased() })
            let newRules = rules.filter { !rulesLower.contains($0.lowercased()) }
            if !newRules.isEmpty {
                do {
                    try PikoSoul.appendRules(newRules, to: brain.home.personalityFile)
                    brain.reloadConfig()
                    PikoGateway.shared.logSoulEvolution(rules: newRules, trigger: turn.user)
                    appendToJournal(
                        facts: newRules.map { "Soul evolution: \($0)" },
                        journalFile: brain.home.journalFile
                    )
                } catch {
                    PikoGateway.shared.logError(
                        message: "Soul evolution failed: \(error.localizedDescription)",
                        subsystem: .brain
                    )
                }
            }
        } catch {
            PikoGateway.shared.logError(
                message: "Memory extraction failed: \(error.localizedDescription)",
                subsystem: .memory
            )
        }
    }

    /// Parses `{"facts": [...], "rules": [...]}` from LLM response.
    /// Falls back to treating the entire response as a flat facts array if no object found.
    private func parseCombinedJSON(_ response: String) -> (facts: [String], rules: [String]) {
        // Try to find a JSON object first.
        if let objStart = response.firstIndex(of: "{"),
           let objEnd = response.lastIndex(of: "}") {
            let jsonString = String(response[objStart...objEnd])
            if let data = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let facts = extractStringArray(obj["facts"])
                let rules = extractStringArray(obj["rules"])
                return (facts, rules)
            }
        }
        // Fallback: treat as flat array (backward compat with older response format).
        return (parseFactsJSON(response), [])
    }

    private func extractStringArray(_ value: Any?) -> [String] {
        if let arr = value as? [String] {
            return arr.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        // Handle nested arrays from small models.
        if let nested = value as? [[String]] {
            return nested.flatMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return []
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
