import AppKit
import Foundation

struct PikoBrowser {

    /// Opens a URL in the default browser. Returns true if successful.
    /// Only opens web URLs — rejects file paths, tildes, and non-http schemes.
    static func open(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject file paths — these are not URLs.
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("./") {
            return false
        }

        // Reject dangerous schemes.
        let lower = trimmed.lowercased()
        if lower.hasPrefix("javascript:") || lower.hasPrefix("data:") || lower.hasPrefix("file://") {
            return false
        }

        // Add https:// if no scheme is present.
        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard let url = URL(string: withScheme) else { return false }

        // Only allow http/https schemes.
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }

        // Must have a valid host (not empty, not a path).
        guard let host = url.host, host.contains(".") || host == "localhost" else { return false }

        return NSWorkspace.shared.open(url)
    }

    /// Opens a Google search for the given query.
    static func search(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        else { return false }
        return NSWorkspace.shared.open(url)
    }
}
