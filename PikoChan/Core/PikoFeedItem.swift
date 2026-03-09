import Foundation

/// A single item in the activity feed.
struct PikoFeedItem: Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: PikoFeedKind

    init(kind: PikoFeedKind) {
        self.id = UUID()
        self.timestamp = Date()
        self.kind = kind
    }
}

enum PikoFeedKind {
    /// User's input message.
    case userMessage(String)
    /// Assistant's response text (mood-stripped).
    case assistantMessage(String)
    /// Reference to a PikoAction by ID (lives in actionHandler.actions).
    case actionRef(UUID)
}
