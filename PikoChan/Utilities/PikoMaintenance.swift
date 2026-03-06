import Foundation

/// Handles storage maintenance: journal rotation and auto-pruning.
enum PikoMaintenance {

    /// Maximum journal size before rotation (500 KB).
    static let maxJournalBytes = 512_000

    /// Rotates the journal if it exceeds `maxJournalBytes`.
    /// Moves content older than the last 50 entries into a monthly archive file.
    /// Returns `true` if rotation occurred.
    @discardableResult
    static func rotateJournal(at journalURL: URL, maxBytes: Int = maxJournalBytes) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: journalURL.path),
              let size = attrs[.size] as? Int,
              size > maxBytes else {
            return false
        }

        guard let content = try? String(contentsOf: journalURL, encoding: .utf8) else {
            return false
        }

        let lines = content.components(separatedBy: "\n")

        // Keep last 50 lines as the active journal.
        let keepCount = min(50, lines.count)
        let archiveLines = Array(lines.dropLast(keepCount))
        let keepLines = Array(lines.suffix(keepCount))

        guard !archiveLines.isEmpty else { return false }

        // Archive file: journal-archive-YYYY-MM.md
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthTag = formatter.string(from: Date.now)
        let archiveURL = journalURL
            .deletingLastPathComponent()
            .appendingPathComponent("journal-archive-\(monthTag).md")

        // Append to existing archive or create new.
        let archiveContent = archiveLines.joined(separator: "\n") + "\n"
        if fm.fileExists(atPath: archiveURL.path) {
            if let handle = try? FileHandle(forWritingTo: archiveURL) {
                handle.seekToEndOfFile()
                if let data = archiveContent.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? archiveContent.write(to: archiveURL, atomically: true, encoding: .utf8)
        }

        // Rewrite active journal with kept lines.
        let active = "# PikoChan Journal\n\n" + keepLines.joined(separator: "\n") + "\n"
        try? active.write(to: journalURL, atomically: true, encoding: .utf8)

        return true
    }

    /// Runs all maintenance tasks. Call once on app launch.
    static func runAll(home: PikoHome, store: PikoStore?) {
        // 1. Rotate journal if oversized.
        rotateJournal(at: home.journalFile)

        // 2. Auto-prune chat turns older than 90 days.
        store?.pruneOldTurns(olderThanDays: 90)
    }
}
