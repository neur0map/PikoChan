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
        // Enable FK enforcement so ON DELETE CASCADE works for memory_vectors.
        execute("PRAGMA foreign_keys = ON;")
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

        execute("""
            CREATE TABLE IF NOT EXISTS memory_vectors (
                memory_id INTEGER PRIMARY KEY,
                vector BLOB NOT NULL,
                embedder TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY (memory_id) REFERENCES memories(id) ON DELETE CASCADE
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

    @discardableResult
    func saveMemory(fact: String, turnId: Int?) -> Int? {
        let sql = """
            INSERT INTO memories (fact, source_turn_id, created_at)
            VALUES (?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (fact as NSString).utf8String, -1, nil)
        if let turnId {
            sqlite3_bind_int(stmt, 2, Int32(turnId))
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, Date.now.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return Int(sqlite3_last_insert_rowid(db))
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
        execute("DELETE FROM memory_vectors;")
        execute("DELETE FROM chat_history;")
        execute("DELETE FROM memories;")
    }

    // MARK: - Memory Vectors

    func saveVector(memoryId: Int, vector: [Double], embedder: String) {
        let sql = "INSERT OR REPLACE INTO memory_vectors (memory_id, vector, embedder, created_at) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(memoryId))
        // SQLITE_TRANSIENT (-1 cast) tells SQLite to copy the blob immediately,
        // so the pointer doesn't need to outlive this call.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        _ = data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(data.count), transient)
        }
        sqlite3_bind_text(stmt, 3, (embedder as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 4, Date.now.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    func allMemoryVectors() -> [(id: Int, fact: String, vector: [Double])] {
        let sql = """
            SELECT m.id, m.fact, v.vector
            FROM memories m
            INNER JOIN memory_vectors v ON v.memory_id = m.id;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [(id: Int, fact: String, vector: [Double])] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            let fact = String(cString: sqlite3_column_text(stmt, 1))
            let blobPtr = sqlite3_column_blob(stmt, 2)
            let blobSize = Int(sqlite3_column_bytes(stmt, 2))
            let doubleCount = blobSize / MemoryLayout<Double>.size
            guard let blobPtr, doubleCount > 0 else { continue }
            let vector = Array(UnsafeBufferPointer(
                start: blobPtr.assumingMemoryBound(to: Double.self),
                count: doubleCount
            ))
            results.append((id: id, fact: fact, vector: vector))
        }
        return results
    }

    func memoriesWithoutVectors() -> [(id: Int, fact: String)] {
        let sql = """
            SELECT m.id, m.fact FROM memories m
            LEFT JOIN memory_vectors v ON v.memory_id = m.id
            WHERE v.memory_id IS NULL;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [(id: Int, fact: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            let fact = String(cString: sqlite3_column_text(stmt, 1))
            results.append((id: id, fact: fact))
        }
        return results
    }

    func vectorCount() -> Int {
        let sql = "SELECT COUNT(*) FROM memory_vectors;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Helpers

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
