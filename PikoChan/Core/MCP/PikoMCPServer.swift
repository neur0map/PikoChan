import Foundation

// MARK: - Server Config

struct PikoMCPServerConfig: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var enabled: Bool

    init(name: String, command: String, args: [String] = [], env: [String: String] = [:], enabled: Bool = true) {
        self.id = UUID().uuidString
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.enabled = enabled
    }
}

// MARK: - Tool

struct PikoMCPTool {
    let serverName: String
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var qualifiedName: String { "\(serverName).\(name)" }
}

// MARK: - Tool Result

struct PikoMCPToolResult {
    let content: String
    let isError: Bool
}

// MARK: - Server Status

enum PikoMCPServerStatus: Equatable {
    case stopped
    case starting
    case ready
    case errored(String)

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .ready: "Ready"
        case .errored(let msg): "Error: \(msg)"
        }
    }

    var isRunning: Bool {
        switch self {
        case .ready, .starting: true
        default: false
        }
    }
}

// MARK: - Persistence Wrapper

struct PikoMCPServersFile: Codable {
    var servers: [PikoMCPServerConfig]
}
