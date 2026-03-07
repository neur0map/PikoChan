import AppKit
import CoreGraphics

/// Background heartbeat that observes the user's environment (frontmost app,
/// idle time, time of day) and feeds observations into the mood system.
/// Optionally triggers proactive nudges when conditions are met.
@MainActor
final class PikoHeartbeat {

    private let brain: PikoBrain
    private weak var notchManager: NotchManager?
    private var timerTask: Task<Void, Never>?

    // MARK: - Observation State

    private var appSwitchCount = 0
    private var lastFrontmostApp = ""
    private var lastNudgeTime: Date?
    private var lastNudgeText = ""
    private var sessionStartTime = Date()

    // MARK: - Scheduled One-Shot Nudges

    private var scheduledNudgeTask: Task<Void, Never>?

    // MARK: - Config (live from PikoConfigStore)

    private var interval: Int { max(15, PikoConfigStore.shared.heartbeatInterval) }
    private var nudgesEnabled: Bool { PikoConfigStore.shared.heartbeatNudgesEnabled }

    // MARK: - Observation

    struct Observation {
        let timestamp: Date
        let frontmostApp: String
        let idleSeconds: Double
        let timeOfDay: Int
        let sessionMinutes: Int
        let appSwitchCount: Int
    }

    // MARK: - Init

    init(brain: PikoBrain, notchManager: NotchManager) {
        self.brain = brain
        self.notchManager = notchManager
    }

    // MARK: - Start / Stop

    func start() {
        guard timerTask == nil else { return }
        sessionStartTime = Date()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        scheduledNudgeTask?.cancel()
        scheduledNudgeTask = nil
    }

    /// Schedule a one-shot nudge after a delay. Called when PikoChan emits
    /// `[nudge_after:SECONDS:MESSAGE]` in her response.
    func scheduleNudge(afterSeconds delay: Int, message: String) {
        scheduledNudgeTask?.cancel()
        scheduledNudgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let manager = self.notchManager else { return }

            manager.lastResponseText = message
            manager.lastResponseError = nil
            manager.isResponding = false
            if manager.state == .hidden || manager.state == .hovered {
                manager.transition(to: .expanded)
            }

            PikoGateway.shared.logHeartbeatNudge(
                trigger: "scheduled_\(delay)s",
                message: message,
                app: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
            )
        }
    }

    // MARK: - Core Loop

    private func tick() async {
        guard PikoConfigStore.shared.heartbeatEnabled else { return }

        let obs = observe()

        PikoGateway.shared.logHeartbeatTick(
            app: obs.frontmostApp,
            idleSeconds: Int(obs.idleSeconds),
            timeOfDay: obs.timeOfDay
        )

        evaluateMood(obs)

        if nudgesEnabled, let trigger = shouldNudge(obs) {
            await fireNudge(trigger: trigger, observation: obs)
        }
    }

    // MARK: - Observe

    private func observe() -> Observation {
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

        // Track app switches.
        if frontApp != lastFrontmostApp {
            if !lastFrontmostApp.isEmpty { appSwitchCount += 1 }
            lastFrontmostApp = frontApp
        }

        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )

        let hour = Calendar.current.component(.hour, from: .now)
        let sessionMinutes = Int(Date.now.timeIntervalSince(sessionStartTime) / 60)

        return Observation(
            timestamp: .now,
            frontmostApp: frontApp,
            idleSeconds: idleSeconds,
            timeOfDay: hour,
            sessionMinutes: sessionMinutes,
            appSwitchCount: appSwitchCount
        )
    }

    // MARK: - Mood Evaluation

    private func evaluateMood(_ obs: Observation) {
        guard let manager = notchManager else { return }
        let oldMood = manager.currentMood

        // Late night (1–4am) → concerned
        if obs.timeOfDay >= 1 && obs.timeOfDay <= 4 && oldMood != .concerned {
            manager.currentMood = .concerned
            PikoGateway.shared.logHeartbeatMoodShift(
                from: oldMood.rawValue, to: "Concerned", trigger: "late_night"
            )
            return
        }

        // Returning from long idle (2+ min) → playful
        if obs.idleSeconds < 5 && obs.sessionMinutes > 2 && oldMood == .neutral {
            // Only shift if the user just came back (idle was recently high).
            // We approximate by checking session length vs low idle.
            manager.currentMood = .playful
            PikoGateway.shared.logHeartbeatMoodShift(
                from: oldMood.rawValue, to: "Playful", trigger: "idle_return"
            )
            return
        }

        // Marathon session (4+ hours) → encouraging
        if obs.sessionMinutes >= 240 && oldMood != .encouraging {
            manager.currentMood = .encouraging
            PikoGateway.shared.logHeartbeatMoodShift(
                from: oldMood.rawValue, to: "Encouraging", trigger: "marathon_session"
            )
            return
        }
    }

    // MARK: - Nudge Logic

    private func shouldNudge(_ obs: Observation) -> String? {
        let config = PikoConfigStore.shared

        // Respect quiet hours.
        if isQuietHour(obs.timeOfDay) { return nil }

        // Cooldown: at least 30 minutes between nudges.
        if let last = lastNudgeTime, Date.now.timeIntervalSince(last) < 1800 {
            return nil
        }

        // Long idle (2+ hours).
        if config.nudgeLongIdle && obs.idleSeconds >= 7200 {
            return "long_idle"
        }

        // Late night (1–4am) — only if the user is active (low idle).
        if config.nudgeLateNight && obs.timeOfDay >= 1 && obs.timeOfDay <= 4 && obs.idleSeconds < 60 {
            return "late_night"
        }

        // Marathon session (4+ hours continuous).
        if config.nudgeMarathon && obs.sessionMinutes >= 240 && obs.idleSeconds < 300 {
            return "marathon_session"
        }

        return nil
    }

    private func isQuietHour(_ hour: Int) -> Bool {
        let config = PikoConfigStore.shared
        let start = config.quietHoursStart
        let end = config.quietHoursEnd

        if start <= end {
            // e.g. 23–23 means no quiet hours; 9–17 means 9am–5pm
            return hour >= start && hour < end
        } else {
            // Wraps midnight: e.g. 23–7 means 11pm–7am
            return hour >= start || hour < end
        }
    }

    private func fireNudge(trigger: String, observation: Observation) async {
        guard let manager = notchManager else { return }

        let contextPrompt: String
        switch trigger {
        case "long_idle":
            contextPrompt = "The user has been away from their Mac for over 2 hours. They just came back. Welcome them back warmly in 1–2 sentences. Be natural, not robotic."
        case "late_night":
            contextPrompt = "It's \(observation.timeOfDay):00 and the user is still working on their Mac (using \(observation.frontmostApp)). Gently suggest they get some rest in 1–2 sentences. Be caring, not preachy."
        case "marathon_session":
            contextPrompt = "The user has been on their Mac for \(observation.sessionMinutes / 60) hours straight (currently in \(observation.frontmostApp)). Encourage them to take a break in 1–2 sentences. Be supportive."
        default:
            return
        }

        do {
            let response = try await brain.respondInternal(to: contextPrompt)
            let cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanResponse.isEmpty else { return }

            // Dedup: don't send exact same text within 24 hours.
            if cleanResponse == lastNudgeText,
               let last = lastNudgeTime,
               Date.now.timeIntervalSince(last) < 86400 {
                return
            }

            lastNudgeTime = .now
            lastNudgeText = cleanResponse

            // Show the nudge in the notch.
            manager.lastResponseText = cleanResponse
            manager.lastResponseError = nil
            manager.isResponding = false
            if manager.state == .hidden || manager.state == .hovered {
                manager.transition(to: .expanded)
            }

            PikoGateway.shared.logHeartbeatNudge(
                trigger: trigger,
                message: cleanResponse,
                app: observation.frontmostApp
            )
        } catch {
            PikoGateway.shared.logError(
                message: "Heartbeat nudge failed: \(error.localizedDescription)",
                subsystem: .heartbeat
            )
        }
    }
}
