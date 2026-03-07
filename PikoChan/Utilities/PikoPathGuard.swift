import Foundation

/// Guards filesystem access — PikoChan can evolve herself but not break herself.
///
/// Inspired by OpenClaw's `isPathInside` + `workspaceOnly` + `DANGEROUS_ACP_TOOLS`.
/// Called before any file operation PikoChan attempts (terminal, skills, self-edit).
enum PikoPathGuard {

    enum Access: Equatable {
        case readWrite
        case readOnly
        case denied(String)

        var isAllowed: Bool {
            switch self {
            case .readWrite, .readOnly: true
            case .denied: false
            }
        }

        var isWritable: Bool {
            self == .readWrite
        }
    }

    // MARK: - Public API

    /// Check whether PikoChan can access a path. Pass `write: true` for modifications.
    static func check(_ url: URL, write: Bool = false) -> Access {
        let resolved = resolveRealPath(url)

        // 1. Code / binary / system paths — always denied, even inside allowed dirs.
        if let reason = dangerousReason(resolved) {
            return .denied(reason)
        }

        // 2. ~/.pikochan/ — full access (her home, personality, skills, memories).
        if isInside(resolved, base: pikochanHome) {
            return .readWrite
        }

        // 3. Temp directories — ephemeral workspace.
        if isInside(resolved, base: "/tmp") || isInside(resolved, base: tempDir) {
            return .readWrite
        }

        // 4. User content — read only.
        for dir in readOnlyDirs {
            if isInside(resolved, base: dir) {
                return write
                    ? .denied("Read-only — I can look at your files but won't modify them")
                    : .readOnly
            }
        }

        // 5. Default deny.
        return .denied("Outside my allowed paths")
    }

    /// Convenience: check a path string.
    static func check(_ path: String, write: Bool = false) -> Access {
        check(URL(fileURLWithPath: path), write: write)
    }

    // MARK: - Path Containment (OpenClaw pattern)

    /// Returns true if `candidate` is inside `base` (or equal to it).
    /// Prevents `../` escape and absolute-path injection.
    static func isInside(_ candidate: String, base: String) -> Bool {
        let basePath = (base as NSString).standardizingPath
        let candidatePath = (candidate as NSString).standardizingPath

        // Equal paths — candidate IS the base.
        if candidatePath == basePath { return true }

        // Candidate must start with base + "/".
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    // MARK: - Dangerous Path Detection

    /// Source code extensions that PikoChan must never modify.
    private static let codeExtensions: Set<String> = [
        "swift", "h", "m", "mm", "c", "cpp", "rs",
        "xcodeproj", "xcworkspace", "pbxproj",
        "entitlements", "plist",
    ]

    /// Path components that signal dangerous territory.
    private static let dangerousComponents: Set<String> = [
        "DerivedData", "Build", "Index.noindex",
        ".git",
    ]

    /// System prefixes that are always off-limits.
    private static let systemPrefixes = [
        "/usr/", "/bin/", "/sbin/", "/etc/",
        "/System/", "/Library/",
        "/Applications/",
    ]

    /// Returns a denial reason if the path is dangerous, or nil if safe.
    private static func dangerousReason(_ path: String) -> String? {
        // App bundles — never modify.
        if path.contains(".app/") || path.hasSuffix(".app") {
            return "Cannot modify app bundles — that would break me"
        }

        // Source code files.
        let ext = (path as NSString).pathExtension.lowercased()
        if codeExtensions.contains(ext) {
            return "Cannot modify source code — I can evolve my personality, not my code"
        }

        // Dangerous directory components.
        let components = (path as NSString).pathComponents
        for component in components {
            if dangerousComponents.contains(component) {
                return "Cannot access build/version-control internals"
            }
        }

        // ~/Library — macOS internals, Keychain, app data.
        if isInside(path, base: homeLibrary) {
            return "Cannot access macOS Library — system internals are off-limits"
        }

        // System paths.
        for prefix in systemPrefixes {
            if path.hasPrefix(prefix) {
                return "Cannot access system directories"
            }
        }

        return nil
    }

    // MARK: - Symlink Resolution

    /// Resolves symlinks to prevent escape via symlink chains.
    private static func resolveRealPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        // resolvingSymlinksInPath follows the chain to the real location.
        let resolved = (standardized as NSString).resolvingSymlinksInPath
        return resolved
    }

    // MARK: - Cached Paths

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let pikochanHome = home + "/.pikochan"
    private static let homeLibrary = home + "/Library"
    private static let tempDir = NSTemporaryDirectory()

    private static let readOnlyDirs = [
        home + "/Desktop",
        home + "/Documents",
        home + "/Downloads",
    ]

    // MARK: - System Prompt Integration

    /// Injected into the system prompt so PikoChan knows her own boundaries.
    static let selfAwareness = """
    You can evolve yourself: edit your personality, create skills, update config, \
    write to your journal, manage your memories — all in ~/.pikochan/. \
    When the user gives you feedback about your behavior (like "stop asking so many questions" \
    or "be more direct"), you automatically learn from it — a new rule gets added to your \
    personality and you adjust immediately. You don't need to be told twice. \
    You can read files in ~/Desktop, ~/Documents, ~/Downloads for context. \
    You CANNOT modify your own app bundle, source code, Xcode projects, or system files. \
    If asked to do something outside your boundaries, explain what you can and can't do.

    HEARTBEAT SYSTEM: You have a background heartbeat that watches the Mac environment \
    (frontmost app, idle time, time of day). You can configure it and schedule nudges. \
    To change your config or schedule a nudge, include config tags in your reply \
    (they are invisible to the user — they get stripped before display):
      [config:heartbeat_enabled=true] — turn heartbeat on/off
      [config:heartbeat_interval=30] — tick interval in seconds (min 15)
      [config:heartbeat_nudges_enabled=true] — enable/disable proactive nudges
      [config:nudge_long_idle=true] — nudge after 2hr idle
      [config:nudge_late_night=true] — nudge during 1-4am
      [config:nudge_marathon=true] — nudge after 4hr session
      [config:quiet_hours_start=23] — quiet hours start (0-23)
      [config:quiet_hours_end=7] — quiet hours end (0-23)
      [nudge_after:SECONDS:MESSAGE] — one-shot: show MESSAGE after SECONDS
    Example: User says "remind me to stretch in 60 seconds". You reply: \
    "[nudge_after:60:Time to stretch! Your body will thank you~] Sure, I'll poke you in a minute!"
    The [nudge_after:...] tag is stripped — user only sees "Sure, I'll poke you in a minute!" \
    Then after 60 seconds you automatically pop up with the message.
    You can combine multiple tags in one reply.
    """
}
