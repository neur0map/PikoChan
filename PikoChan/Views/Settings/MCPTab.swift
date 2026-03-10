import SwiftUI

struct MCPTab: View {
    @State private var mcpManager = PikoMCPManager.shared
    @State private var refreshID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Installed Servers

                GroupBox("MCP Servers") {
                    if mcpManager.servers.isEmpty {
                        VStack(spacing: 8) {
                            Text("No MCP servers installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Paste an MCP config in chat to install one.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(mcpManager.servers) { server in
                                serverRow(server)
                                if server.id != mcpManager.servers.last?.id {
                                    Divider().padding(.vertical, 4)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .id(refreshID)

                // MARK: - Actions

                HStack(spacing: 12) {
                    Button("Reload") {
                        mcpManager.loadServers()
                        refreshID = UUID()
                    }

                    Button("Open MCP Folder") {
                        let url = PikoHome().mcpDir
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }

                // MARK: - Info

                GroupBox("About MCP") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MCP (Model Context Protocol) lets PikoChan connect to external tool servers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Paste any MCP server config in chat and PikoChan will install it, discover tools, and learn how to use them automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Spacer()
            }
            .padding(20)
        }
    }

    // MARK: - Server Row

    @ViewBuilder
    private func serverRow(_ server: PikoMCPServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Status dot.
                Circle()
                    .fill(statusColor(for: server.name))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(server.command) \(server.args.joined(separator: " "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                let toolCount = mcpManager.toolCountForServer(name: server.name)
                if toolCount > 0 {
                    Text("\(toolCount) tools")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.secondary.opacity(0.15))
                        )
                }
            }

            // Error message if errored.
            let status = mcpManager.statusForServer(name: server.name)
            if case .errored(let msg) = status {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Action buttons.
            HStack(spacing: 8) {
                if status == .ready {
                    Button("Stop") {
                        mcpManager.transports[server.name]?.stop()
                        refreshID = UUID()
                    }
                    .controlSize(.small)
                } else if status == .stopped || status != .starting {
                    Button("Start") {
                        Task {
                            try? await mcpManager.restartServer(name: server.name)
                            refreshID = UUID()
                        }
                    }
                    .controlSize(.small)
                }

                Button("Remove") {
                    mcpManager.removeServer(name: server.name)
                    refreshID = UUID()
                }
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
    }

    private func statusColor(for serverName: String) -> Color {
        switch mcpManager.statusForServer(name: serverName) {
        case .ready: .green
        case .starting: .orange
        case .errored: .red
        case .stopped: .gray
        }
    }
}
