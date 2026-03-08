import Foundation
import UniformTypeIdentifiers

/// Scans user prompts for file/path references, resolves them on disk,
/// and enriches the prompt with `<file_context>` so the LLM has ground truth.
enum PikoFileDetector {

    struct FileContext {
        let originalRef: String   // what the user wrote ("~/Downloads")
        let resolvedPath: String  // full expanded path
        let exists: Bool
        let isDirectory: Bool
        let size: Int64           // bytes, 0 if dir or missing
        let mimeHint: String      // "audio/mpeg", "directory", "unknown"
        let children: [String]?   // first 10 entries if directory
    }

    // MARK: - Public API

    /// Scan user prompt for path references, resolve on disk.
    static func detect(in text: String) -> [FileContext] {
        var results: [FileContext] = []
        var seen = Set<String>()

        // 1. Explicit paths: ~/..., /Users/..., ./...
        let explicitPaths = extractExplicitPaths(from: text)
        for path in explicitPaths {
            let resolved = (path as NSString).expandingTildeInPath
            guard !seen.contains(resolved) else { continue }
            seen.insert(resolved)
            results.append(resolve(originalRef: path, resolvedPath: resolved))
        }

        // 2. Well-known directory names
        let lower = text.lowercased()
        let knownDirs: [(keyword: String, path: String)] = [
            ("downloads", "~/Downloads"),
            ("download", "~/Downloads"),
            ("desktop", "~/Desktop"),
            ("documents", "~/Documents"),
            ("pictures", "~/Pictures"),
            ("music", "~/Music"),
            ("movies", "~/Movies"),
        ]
        for entry in knownDirs {
            if lower.contains(entry.keyword) {
                let resolved = (entry.path as NSString).expandingTildeInPath
                guard !seen.contains(resolved) else { continue }
                seen.insert(resolved)
                results.append(resolve(originalRef: entry.path, resolvedPath: resolved))
            }
        }

        // 3. Fuzzy file matching — if we resolved a directory, search children
        //    for filenames that match words in the user's prompt.
        let dirs = results.filter { $0.exists && $0.isDirectory }
        for dir in dirs {
            let fuzzyMatches = fuzzySearch(in: dir.resolvedPath, query: text)
            for match in fuzzyMatches {
                let fullPath = (dir.resolvedPath as NSString).appendingPathComponent(match)
                guard !seen.contains(fullPath) else { continue }
                seen.insert(fullPath)
                let shortRef = (dir.originalRef as NSString).appendingPathComponent(match)
                results.append(resolve(originalRef: shortRef, resolvedPath: fullPath))
            }
        }

        return results
    }

    /// Build enriched prompt with file context appended.
    /// Returns original prompt if no paths detected.
    static func enrichPrompt(_ prompt: String) -> String {
        let contexts = detect(in: prompt)
        guard !contexts.isEmpty else { return prompt }

        var lines: [String] = []
        // Collect non-directory file matches for the suggested command.
        var bestFile: FileContext?

        for ctx in contexts {
            if ctx.isDirectory && ctx.exists {
                let count = ctx.children?.count ?? 0
                let recent = ctx.children?.prefix(5).joined(separator: ", ") ?? ""
                lines.append("\(ctx.resolvedPath) | directory | \(count) items | recent: \(recent)")
            } else if ctx.exists {
                let sizeStr = formatSize(ctx.size)
                lines.append("\(ctx.resolvedPath) | exists | \(ctx.mimeHint) | \(sizeStr)")
                if bestFile == nil { bestFile = ctx }
            } else {
                lines.append("\(ctx.resolvedPath) | not found")
            }
        }

        // If we found a specific file and the user seems to want to open/play it,
        // include a ready-to-use action tag so the LLM can copy it verbatim.
        if let file = bestFile {
            let actionWords = ["play", "open", "listen", "hear", "watch", "run", "show", "launch"]
            let lower = prompt.lowercased()
            let wantsAction = actionWords.contains { lower.contains($0) }
            if wantsAction {
                lines.append("USE THIS EXACT TAG: [shell:open \"\(file.resolvedPath)\"]")
            }
        }

        let block = "<file_context>\n" + lines.joined(separator: "\n") + "\n</file_context>"
        return prompt + "\n\n" + block
    }

    // MARK: - Path Extraction

    private static func extractExplicitPaths(from text: String) -> [String] {
        // Match ~/path, /Users/path, ./path — allowing alphanumeric, dots, hyphens, underscores, spaces (quoted)
        let pattern = #"(?:~/[\w/.@\-]+|/(?:Users|Volumes|Applications|Library|tmp|var|etc|opt|usr)[\w/.@\-]*|\.{1,2}/[\w/.@\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    // MARK: - Resolution

    private static func resolve(originalRef: String, resolvedPath: String) -> FileContext {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: resolvedPath, isDirectory: &isDir)

        var size: Int64 = 0
        var mime = "unknown"
        var children: [String]? = nil

        if exists {
            if isDir.boolValue {
                mime = "directory"
                // List first 10 children sorted by modification date
                if let contents = try? fm.contentsOfDirectory(atPath: resolvedPath) {
                    let sorted = contents
                        .filter { !$0.hasPrefix(".") }  // skip hidden
                        .sorted { a, b in
                            let pathA = (resolvedPath as NSString).appendingPathComponent(a)
                            let pathB = (resolvedPath as NSString).appendingPathComponent(b)
                            let dateA = (try? fm.attributesOfItem(atPath: pathA)[.modificationDate] as? Date) ?? .distantPast
                            let dateB = (try? fm.attributesOfItem(atPath: pathB)[.modificationDate] as? Date) ?? .distantPast
                            return dateA > dateB
                        }
                    children = Array(sorted.prefix(10))
                }
            } else {
                if let attrs = try? fm.attributesOfItem(atPath: resolvedPath) {
                    size = (attrs[.size] as? Int64) ?? 0
                }
                mime = mimeFromExtension((resolvedPath as NSString).pathExtension)
            }
        }

        return FileContext(
            originalRef: originalRef,
            resolvedPath: resolvedPath,
            exists: exists,
            isDirectory: isDir.boolValue,
            size: size,
            mimeHint: mime,
            children: children
        )
    }

    // MARK: - Fuzzy Search

    /// Search directory children for filenames matching words in the query.
    private static func fuzzySearch(in dirPath: String, query: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }

        // Extract meaningful words from the query (3+ chars, not common words)
        let stopWords: Set<String> = [
            "the", "from", "play", "open", "show", "what", "that", "this",
            "with", "find", "file", "folder", "want", "listen", "song",
            "can", "you", "hey", "piko", "please", "check", "look",
        ]
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        guard !words.isEmpty else { return [] }

        var matches: [String] = []
        for filename in contents where !filename.hasPrefix(".") {
            let lowerName = filename.lowercased()
            // File matches if any query word appears in the filename
            let hit = words.contains { lowerName.contains($0) }
            if hit {
                matches.append(filename)
            }
        }
        return Array(matches.prefix(5))  // cap to avoid flooding
    }

    // MARK: - Helpers

    private static func mimeFromExtension(_ ext: String) -> String {
        let lower = ext.lowercased()

        // Use UTType if available
        if let uttype = UTType(filenameExtension: lower), let mime = uttype.preferredMIMEType {
            return mime
        }

        // Fallback for common types
        let map: [String: String] = [
            "mp3": "audio/mpeg", "wav": "audio/wav", "m4a": "audio/mp4",
            "flac": "audio/flac", "ogg": "audio/ogg", "aac": "audio/aac",
            "mp4": "video/mp4", "mov": "video/quicktime", "avi": "video/x-msvideo",
            "mkv": "video/x-matroska", "webm": "video/webm",
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
            "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml",
            "pdf": "application/pdf", "zip": "application/zip",
            "txt": "text/plain", "md": "text/markdown",
            "json": "application/json", "xml": "application/xml",
            "html": "text/html", "css": "text/css", "js": "text/javascript",
            "py": "text/x-python", "swift": "text/x-swift",
        ]
        return map[lower] ?? "application/octet-stream"
    }

    private static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1fKB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1fMB", mb) }
        let gb = mb / 1024
        return String(format: "%.1fGB", gb)
    }
}
