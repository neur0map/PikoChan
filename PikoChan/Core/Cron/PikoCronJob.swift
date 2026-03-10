import Foundation

// MARK: - Payload

enum PikoCronPayload: Codable, Sendable {
    case reminder(String)
    case shell(String)
    case open(String)

    var label: String {
        switch self {
        case .reminder: "Reminder"
        case .shell:    "Shell"
        case .open:     "Open"
        }
    }

    var detail: String {
        switch self {
        case .reminder(let msg): msg
        case .shell(let cmd):    cmd
        case .open(let url):     url
        }
    }

    // Type-discriminated JSON: {"reminder":"..."}, {"shell":"..."}, {"open":"..."}
    private enum CodingKeys: String, CodingKey { case reminder, shell, open }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reminder(let v): try container.encode(v, forKey: .reminder)
        case .shell(let v):    try container.encode(v, forKey: .shell)
        case .open(let v):     try container.encode(v, forKey: .open)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? container.decode(String.self, forKey: .reminder) {
            self = .reminder(v)
        } else if let v = try? container.decode(String.self, forKey: .shell) {
            self = .shell(v)
        } else if let v = try? container.decode(String.self, forKey: .open) {
            self = .open(v)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown payload type"))
        }
    }
}

// MARK: - Run Status

enum RunStatus: String, Codable, Sendable { case ok, failed, skipped }

// MARK: - Session Target

enum SessionTarget: String, Codable, Sendable { case main, isolated }

// MARK: - Job State

struct PikoCronJobState: Codable, Sendable {
    var nextFireDate: Date?
    var lastFireDate: Date?
    var lastStatus: RunStatus?
    var runCount: Int = 0
    var consecutiveErrors: Int = 0
}

// MARK: - Run Record

struct PikoCronRunRecord: Codable, Sendable {
    let time: Date
    let status: RunStatus
    let durationMs: Int
    let output: String
}

// MARK: - Cron Job

struct PikoCronJob: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var enabled: Bool
    var deleteAfterRun: Bool
    var sessionTarget: SessionTarget
    var createdAt: Date
    var schedule: PikoCronSchedule
    var payload: PikoCronPayload
    var state: PikoCronJobState

    init(
        id: UUID = UUID(),
        name: String,
        schedule: PikoCronSchedule,
        payload: PikoCronPayload,
        enabled: Bool = true,
        deleteAfterRun: Bool = false,
        sessionTarget: SessionTarget = .main
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.deleteAfterRun = deleteAfterRun
        self.sessionTarget = sessionTarget
        self.createdAt = Date()
        self.schedule = schedule
        self.payload = payload
        self.state = PikoCronJobState()
    }

    /// Human-readable schedule description.
    var scheduleLabel: String {
        schedule.label
    }
}
