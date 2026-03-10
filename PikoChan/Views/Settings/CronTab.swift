import SwiftUI

struct CronTab: View {
    @State private var jobs: [PikoCronJob] = []
    @State private var refreshID = UUID()

    private var service: PikoCronService? { PikoCronService.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Jobs

                GroupBox("Scheduled Jobs") {
                    if jobs.isEmpty {
                        Text("No cron jobs scheduled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(jobs) { job in
                                jobRow(job)
                                if job.id != jobs.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Summary

                if !jobs.isEmpty {
                    HStack {
                        Text("\(jobs.count) job\(jobs.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(jobs.filter(\.enabled).count) active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(jobs.map(\.state.runCount).reduce(0, +)) total runs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Actions

                HStack(spacing: 12) {
                    Button("Refresh") {
                        reload()
                    }

                    Button("Open Cron Folder") {
                        let url = PikoHome().cronDir
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .id(refreshID)
        .onAppear { reload() }
    }

    // MARK: - Job Row

    @ViewBuilder
    private func jobRow(_ job: PikoCronJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.name)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(job.enabled ? 1.0 : 0.5)

                payloadBadge(job.payload)

                if !job.enabled {
                    Text("Paused")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.orange.opacity(0.15))
                        )
                }

                if job.deleteAfterRun {
                    Text("One-shot")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.secondary.opacity(0.15))
                        )
                }

                Spacer()

                // Action buttons.
                HStack(spacing: 6) {
                    Button {
                        service?.runJob(nameOrID: job.id.uuidString)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { reload() }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Run now")

                    Button {
                        if job.enabled {
                            service?.pauseJob(nameOrID: job.id.uuidString)
                        } else {
                            service?.resumeJob(nameOrID: job.id.uuidString)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reload() }
                    } label: {
                        Image(systemName: job.enabled ? "pause.fill" : "play.circle")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help(job.enabled ? "Pause" : "Resume")

                    Button {
                        service?.removeJob(nameOrID: job.id.uuidString)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reload() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }

            HStack(spacing: 12) {
                Label(job.scheduleLabel, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let next = job.state.nextFireDate {
                    Text("Next: \(next, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if job.state.runCount > 0 {
                    Text("\(job.state.runCount) run\(job.state.runCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let last = job.state.lastStatus {
                    Circle()
                        .fill(last == .ok ? .green : .red)
                        .frame(width: 6, height: 6)
                }
            }

            Text(job.payload.detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .opacity(job.enabled ? 1.0 : 0.6)
    }

    @ViewBuilder
    private func payloadBadge(_ payload: PikoCronPayload) -> some View {
        let (label, color): (String, Color) = switch payload {
        case .reminder: ("Reminder", .blue)
        case .shell:    ("Shell", .green)
        case .open:     ("URL", .purple)
        }

        Text(label)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
            )
    }

    private func reload() {
        jobs = service?.jobs ?? []
        refreshID = UUID()
    }
}
