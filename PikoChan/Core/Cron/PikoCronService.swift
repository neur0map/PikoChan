import Foundation

/// Orchestrates cron job scheduling, firing, and lifecycle management.
@Observable
@MainActor
final class PikoCronService {

    static private(set) var shared: PikoCronService?

    private let store: PikoCronStore
    private weak var notchManager: NotchManager?
    private let gateway = PikoGateway.shared

    private var timerTask: Task<Void, Never>?
    private var runningJobs: Set<UUID> = []

    /// Tick interval in seconds.
    private static let tickInterval: TimeInterval = 30

    /// Max consecutive errors before auto-disable.
    private static let maxConsecutiveErrors = 3

    var jobs: [PikoCronJob] { store.jobs }

    init(store: PikoCronStore, notchManager: NotchManager) {
        self.store = store
        self.notchManager = notchManager
    }

    // MARK: - Lifecycle

    func start() {
        Self.shared = self
        store.load()
        computeNextFireDates()
        startTimer()
        gateway.logCronTick(jobCount: store.jobs.count, firedCount: 0)
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        store.save()
    }

    // MARK: - Command Handling

    func handleCommands(_ commands: [PikoCronCommand.Command]) {
        for command in commands {
            switch command {
            case .add(let name, let schedule, let payload):
                addJob(name: name, schedule: schedule, payload: payload)
            case .remove(let nameOrID):
                removeJob(nameOrID: nameOrID)
            case .list:
                let listing = listJobs()
                notchManager?.addFeedItem(.assistantMessage(listing))
            case .run(let nameOrID):
                runJob(nameOrID: nameOrID)
            case .pause(let nameOrID):
                pauseJob(nameOrID: nameOrID)
            case .resume(let nameOrID):
                resumeJob(nameOrID: nameOrID)
            }
        }
    }

    // MARK: - Job Management

    func addJob(name: String, schedule: PikoCronSchedule, payload: PikoCronPayload) {
        var job = PikoCronJob(name: name, schedule: schedule, payload: payload)

        // For one-shot .at schedules, mark as deleteAfterRun.
        if case .at = schedule {
            job.deleteAfterRun = true
        }

        job.state.nextFireDate = schedule.nextFireDate()
        store.add(job)

        gateway.logCronAdd(name: name, schedule: job.scheduleLabel, payload: payload.label)
        notchManager?.addFeedItem(.assistantMessage("Scheduled: \(name) (\(job.scheduleLabel))"))
    }

    func removeJob(nameOrID: String) {
        guard let job = store.find(byNameOrID: nameOrID) else {
            notchManager?.addFeedItem(.assistantMessage("No cron job found: \(nameOrID)"))
            return
        }
        let name = job.name
        store.remove(id: job.id)
        gateway.logCronRemove(name: name)
        notchManager?.addFeedItem(.assistantMessage("Removed cron job: \(name)"))
    }

    func listJobs() -> String {
        guard !store.jobs.isEmpty else { return "No scheduled jobs." }

        var lines: [String] = ["Scheduled jobs:"]
        for job in store.jobs {
            let status = job.enabled ? "active" : "paused"
            let next = job.state.nextFireDate.map { formatRelative($0) } ?? "none"
            lines.append("- \(job.name) [\(status)] \(job.scheduleLabel) | next: \(next) | runs: \(job.state.runCount)")
        }
        return lines.joined(separator: "\n")
    }

    func runJob(nameOrID: String) {
        guard let job = store.find(byNameOrID: nameOrID) else {
            notchManager?.addFeedItem(.assistantMessage("No cron job found: \(nameOrID)"))
            return
        }
        Task { await fire(job) }
    }

    func pauseJob(nameOrID: String) {
        guard var job = store.find(byNameOrID: nameOrID) else {
            notchManager?.addFeedItem(.assistantMessage("No cron job found: \(nameOrID)"))
            return
        }
        job.enabled = false
        store.update(job)
        gateway.logCronPause(name: job.name)
        notchManager?.addFeedItem(.assistantMessage("Paused: \(job.name)"))
    }

    func resumeJob(nameOrID: String) {
        guard var job = store.find(byNameOrID: nameOrID) else {
            notchManager?.addFeedItem(.assistantMessage("No cron job found: \(nameOrID)"))
            return
        }
        job.enabled = true
        job.state.consecutiveErrors = 0
        job.state.nextFireDate = job.schedule.nextFireDate()
        store.update(job)
        gateway.logCronResume(name: job.name)
        notchManager?.addFeedItem(.assistantMessage("Resumed: \(job.name)"))
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickInterval))
                guard !Task.isCancelled else { break }
                await self?.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        var firedCount = 0

        for job in store.jobs {
            guard job.enabled,
                  let fireDate = job.state.nextFireDate,
                  fireDate <= now,
                  !runningJobs.contains(job.id)
            else { continue }

            // Check quiet hours for reminders.
            if case .reminder = job.payload, isQuietHours() {
                // Skip reminders during quiet hours but don't count as error.
                var updated = job
                updated.state.nextFireDate = job.schedule.nextFireDate(after: now)
                if updated.state.nextFireDate == nil { updated.state.nextFireDate = nil }
                store.update(updated)
                continue
            }

            Task { await fire(job) }
            firedCount += 1
        }

        if firedCount > 0 {
            gateway.logCronTick(jobCount: store.jobs.count, firedCount: firedCount)
        }
    }

    // MARK: - Fire

    private func fire(_ job: PikoCronJob) async {
        guard !runningJobs.contains(job.id) else { return }
        runningJobs.insert(job.id)

        let startTime = Date()
        gateway.logCronFire(name: job.name, payload: job.payload.label, detail: job.payload.detail)

        var status: RunStatus = .ok
        var output = ""

        switch job.payload {
        case .reminder(let message):
            // Show reminder in feed and expand notch.
            notchManager?.addFeedItem(.assistantMessage("Reminder: \(message)"))
            notchManager?.transition(to: .expanded)
            output = message

        case .shell(let command):
            if job.sessionTarget == .main {
                let result = await PikoTerminal.execute(command)
                status = result.exitCode == 0 ? .ok : .failed
                output = result.stdout.isEmpty ? result.stderr : result.stdout
                if job.sessionTarget == .main {
                    notchManager?.addFeedItem(.assistantMessage("Cron [\(job.name)]: exit \(result.exitCode)"))
                }
            } else {
                // Isolated — run silently.
                let result = await PikoTerminal.execute(command)
                status = result.exitCode == 0 ? .ok : .failed
                output = result.stdout.isEmpty ? result.stderr : result.stdout
            }

        case .open(let url):
            let success = PikoBrowser.open(url)
            status = success ? .ok : .failed
            output = success ? "Opened \(url)" : "Failed to open \(url)"
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let record = PikoCronRunRecord(time: startTime, status: status, durationMs: durationMs, output: String(output.prefix(4000)))
        store.appendRunRecord(record, forJob: job.id)

        // Update job state.
        var updated = job
        updated.state.lastFireDate = startTime
        updated.state.lastStatus = status
        updated.state.runCount += 1

        if status == .failed {
            updated.state.consecutiveErrors += 1
            if updated.state.consecutiveErrors >= Self.maxConsecutiveErrors {
                updated.enabled = false
                gateway.logCronDisabled(name: job.name, reason: "3 consecutive failures")
                notchManager?.addFeedItem(.assistantMessage("Auto-disabled cron job '\(job.name)' after 3 failures"))
            }
        } else {
            updated.state.consecutiveErrors = 0
        }

        // Compute next fire date.
        if updated.deleteAfterRun {
            store.remove(id: job.id)
        } else {
            updated.state.nextFireDate = updated.schedule.nextFireDate(after: Date())
            store.update(updated)
        }

        runningJobs.remove(job.id)
    }

    // MARK: - Helpers

    private func computeNextFireDates() {
        let now = Date()
        for job in store.jobs {
            if job.state.nextFireDate == nil || job.state.nextFireDate! <= now {
                var updated = job
                updated.state.nextFireDate = job.schedule.nextFireDate(after: now)
                store.update(updated)
            }
        }
    }

    private func isQuietHours() -> Bool {
        let config = PikoConfigStore.shared
        let hour = Calendar.current.component(.hour, from: Date())
        let start = config.quietHoursStart
        let end = config.quietHoursEnd

        if start < end {
            return hour >= start && hour < end
        } else {
            // Wraps midnight: e.g. 23-7.
            return hour >= start || hour < end
        }
    }

    private func formatRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Nudge Backward Compat

    /// Route a one-shot nudge through the cron system (backward compat with [nudge_after:]).
    func scheduleNudge(afterSeconds: Int, message: String) {
        let schedule = PikoCronSchedule.at(Date().addingTimeInterval(Double(afterSeconds)))
        var job = PikoCronJob(
            name: "nudge-\(UUID().uuidString.prefix(8))",
            schedule: schedule,
            payload: .reminder(message),
            deleteAfterRun: true
        )
        job.state.nextFireDate = schedule.nextFireDate()
        store.add(job)
    }
}
