import Foundation
import SQLite3

/// SQLite wrapper for persistent conversation history and memories.
@MainActor
final class PikoStore {
    private var db: OpaquePointer?

    init?(path: URL) {
        let dbPath = path.path
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return nil
        }
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema

    private func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS chat_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_message TEXT NOT NULL,
                assistant_message TEXT NOT NULL,
                mood TEXT,
                provider TEXT,
                model TEXT,
                created_at REAL NOT NULL
            );
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS memories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fact TEXT NOT NULL,
                source_turn_id INTEGER,
                created_at REAL NOT NULL,
                last_recalled REAL
            );
        """)
    }

    // MARK: - Chat History

    /// Saves a turn and returns its row ID.
    @discardableResult
    func save(turn: ChatTurn, mood: String, provider: String, model: String) -> Int? {
        let sql = """
            INSERT INTO chat_history (user_message, assistant_message, mood, provider, model, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (turn.user as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (turn.assistant as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (mood as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (provider as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (model as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 6, turn.at.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return Int(sqlite3_last_insert_rowid(db))
    }

    func recentTurns(limit: Int) -> [ChatTurn] {
        let sql = """
            SELECT user_message, assistant_message, created_at, mood
            FROM chat_history ORDER BY created_at DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var turns: [ChatTurn] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let user = String(cString: sqlite3_column_text(stmt, 0))
            let assistant = String(cString: sqlite3_column_text(stmt, 1))
            let ts = sqlite3_column_double(stmt, 2)
            let mood: String? = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 3))
                : nil
            turns.append(ChatTurn(
                user: user,
                assistant: assistant,
                at: Date(timeIntervalSince1970: ts),
                mood: mood
            ))
        }
        return turns.reversed() // oldest first
    }

    func turnCount() -> Int {
        let sql = "SELECT COUNT(*) FROM chat_history;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Memories

    func saveMemory(fact: String, turnId: Int?) {
        let sql = """
            INSERT INTO memories (fact, source_turn_id, created_at)
            VALUES (?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (fact as NSString).utf8String, -1, nil)
        if let turnId {
            sqlite3_bind_int(stmt, 2, Int32(turnId))
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, Date.now.timeIntervalSince1970)

        sqlite3_step(stmt)
    }

    /// Returns all memories sorted by temporal decay (newest first), up to limit.
    /// No keyword filtering — for small models with few memories, inject them all.
    func recentMemories(limit: Int) -> [String] {
        let sql = "SELECT fact, created_at FROM memories ORDER BY created_at DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var facts: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let fact = String(cString: sqlite3_column_text(stmt, 0))
            facts.append(fact)
        }
        return facts
    }

    /// Recalls memories matching keywords, scored by match count * temporal decay.
    func recallMemories(keywords: [String], limit: Int) -> [(fact: String, score: Double)] {
        guard !keywords.isEmpty else { return [] }

        let sql = "SELECT id, fact, created_at, last_recalled FROM memories;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let now = Date.now.timeIntervalSince1970
        var results: [(fact: String, score: Double)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let fact = String(cString: sqlite3_column_text(stmt, 1))
            let createdAt = sqlite3_column_double(stmt, 2)
            let factLower = fact.lowercased()

            let matchCount = keywords.filter { factLower.contains($0) }.count
            guard matchCount > 0 else { continue }

            let ageInDays = (now - createdAt) / 86400.0
            let decay = exp(-0.023 * ageInDays)
            let score = Double(matchCount) * decay

            results.append((fact: fact, score: score))
        }

        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    func touchMemory(id: Int) {
        let sql = "UPDATE memories SET last_recalled = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, Date.now.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 2, Int32(id))
        sqlite3_step(stmt)
    }

    func memoryCount() -> Int {
        let sql = "SELECT COUNT(*) FROM memories;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    func clearAll() {
        execute("DELETE FROM chat_history;")
        execute("DELETE FROM memories;")
    }

    // MARK: - Helpers

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
