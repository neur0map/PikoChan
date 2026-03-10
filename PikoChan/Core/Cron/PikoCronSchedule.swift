import Foundation

enum PikoCronSchedule: Codable, Sendable {
    /// One-shot at absolute time.
    case at(Date)
    /// Recurring interval in seconds.
    case every(TimeInterval)
    /// 5-field cron expression (minute hour dayOfMonth month dayOfWeek).
    case cron(String)

    var label: String {
        switch self {
        case .at(let date):
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return "at \(f.string(from: date))"
        case .every(let interval):
            return "every \(Self.formatDuration(interval))"
        case .cron(let expr):
            return "cron: \(expr)"
        }
    }

    /// Compute the next fire date after the given reference date.
    func nextFireDate(after ref: Date = Date()) -> Date? {
        switch self {
        case .at(let date):
            return date > ref ? date : nil
        case .every(let interval):
            // For recurring: next = ref + interval.
            return ref.addingTimeInterval(interval)
        case .cron(let expr):
            guard let cron = CronExpression.parse(expr) else { return nil }
            return cron.nextFireDate(after: ref)
        }
    }

    // MARK: - Codable (type-discriminated)

    private enum CodingKeys: String, CodingKey { case at, every, cron }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .at(let date):       try container.encode(date, forKey: .at)
        case .every(let secs):    try container.encode(secs, forKey: .every)
        case .cron(let expr):     try container.encode(expr, forKey: .cron)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let date = try? container.decode(Date.self, forKey: .at) {
            self = .at(date)
        } else if let secs = try? container.decode(TimeInterval.self, forKey: .every) {
            self = .every(secs)
        } else if let expr = try? container.decode(String.self, forKey: .cron) {
            self = .cron(expr)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown schedule type"))
        }
    }

    // MARK: - Parse from string

    /// Parse schedule from a string like "every:2h", "in:20m", "at:2026-03-10T09:00:00", "cron:0 9 * * *".
    static func parse(from string: String) -> PikoCronSchedule? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("every:") {
            let value = String(trimmed.dropFirst(6))
            guard let seconds = parseDuration(value) else { return nil }
            return .every(seconds)
        }

        if trimmed.hasPrefix("in:") {
            let value = String(trimmed.dropFirst(3))
            guard let seconds = parseDuration(value) else { return nil }
            return .at(Date().addingTimeInterval(seconds))
        }

        if trimmed.hasPrefix("at:") {
            let value = String(trimmed.dropFirst(3))
            if let date = parseDate(value) {
                return .at(date)
            }
            return nil
        }

        if trimmed.hasPrefix("cron:") {
            let expr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            // Validate by parsing.
            guard CronExpression.parse(expr) != nil else { return nil }
            return .cron(expr)
        }

        return nil
    }

    // MARK: - Duration Parsing

    /// Parse duration strings like "30s", "5m", "2h", "1d", "1h30m".
    static func parseDuration(_ string: String) -> TimeInterval? {
        let pattern = /(\d+)([smhd])/
        var total: TimeInterval = 0
        var found = false

        for match in string.matches(of: pattern) {
            guard let value = Double(match.1) else { continue }
            found = true
            switch match.2 {
            case "s": total += value
            case "m": total += value * 60
            case "h": total += value * 3600
            case "d": total += value * 86400
            default: break
            }
        }

        return found ? total : nil
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 {
            let m = s / 60
            let rem = s % 60
            return rem > 0 ? "\(m)m\(rem)s" : "\(m)m"
        }
        if s < 86400 {
            let h = s / 3600
            let m = (s % 3600) / 60
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        let d = s / 86400
        let h = (s % 86400) / 3600
        return h > 0 ? "\(d)d\(h)h" : "\(d)d"
    }

    private static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) { return d }

        // Try without timezone.
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }

        // Try simple date+time: "2026-03-10 09:00"
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss"] {
            df.dateFormat = fmt
            if let d = df.date(from: string) { return d }
        }

        return nil
    }
}

// MARK: - Cron Expression Parser

/// Minimal 5-field cron parser: minute hour dayOfMonth month dayOfWeek.
/// Supports: *, N, N-M, */N, N,M,O, N-M/S.
private struct CronExpression {
    let minutes: Set<Int>    // 0-59
    let hours: Set<Int>      // 0-23
    let daysOfMonth: Set<Int> // 1-31
    let months: Set<Int>     // 1-12
    let daysOfWeek: Set<Int> // 0-6 (0=Sunday)

    static func parse(_ expression: String) -> CronExpression? {
        let fields = expression.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 5 else { return nil }

        guard let minutes = parseField(String(fields[0]), min: 0, max: 59),
              let hours = parseField(String(fields[1]), min: 0, max: 23),
              let daysOfMonth = parseField(String(fields[2]), min: 1, max: 31),
              let months = parseField(String(fields[3]), min: 1, max: 12),
              let daysOfWeek = parseField(String(fields[4]), min: 0, max: 6)
        else { return nil }

        return CronExpression(
            minutes: minutes, hours: hours, daysOfMonth: daysOfMonth,
            months: months, daysOfWeek: daysOfWeek
        )
    }

    private static func parseField(_ field: String, min: Int, max: Int) -> Set<Int>? {
        var result = Set<Int>()

        for part in field.split(separator: ",") {
            let s = String(part)

            if s == "*" {
                return Set(min...max)
            }

            // */N — step over full range.
            if s.hasPrefix("*/") {
                guard let step = Int(s.dropFirst(2)), step > 0 else { return nil }
                for v in stride(from: min, through: max, by: step) { result.insert(v) }
                continue
            }

            // N-M or N-M/S — range with optional step.
            if s.contains("-") {
                let rangeParts = s.split(separator: "/", maxSplits: 1)
                let rangePart = String(rangeParts[0])
                let step = rangeParts.count > 1 ? Int(rangeParts[1]) : 1
                guard let step, step > 0 else { return nil }

                let bounds = rangePart.split(separator: "-", maxSplits: 1)
                guard bounds.count == 2,
                      let lo = Int(bounds[0]), let hi = Int(bounds[1]),
                      lo >= min, hi <= max, lo <= hi
                else { return nil }

                for v in stride(from: lo, through: hi, by: step) { result.insert(v) }
                continue
            }

            // Single value.
            guard let v = Int(s), v >= min, v <= max else { return nil }
            result.insert(v)
        }

        return result.isEmpty ? nil : result
    }

    func matches(_ components: DateComponents) -> Bool {
        guard let minute = components.minute,
              let hour = components.hour,
              let day = components.day,
              let month = components.month,
              let weekday = components.weekday
        else { return false }

        // DateComponents weekday: 1=Sunday..7=Saturday. Cron: 0=Sunday..6=Saturday.
        let cronWeekday = weekday - 1

        return minutes.contains(minute)
            && hours.contains(hour)
            && daysOfMonth.contains(day)
            && months.contains(month)
            && daysOfWeek.contains(cronWeekday)
    }

    /// Find the next fire date after the reference, iterating minute by minute.
    /// Caps search at 366 days.
    func nextFireDate(after ref: Date) -> Date? {
        let calendar = Calendar.current
        // Round up to next minute.
        var candidate = calendar.date(bySetting: .second, value: 0, of: ref) ?? ref
        candidate = candidate.addingTimeInterval(60) // Move to next minute.

        let maxIterations = 366 * 24 * 60 // ~527,040 minutes
        for _ in 0..<maxIterations {
            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)
            if matches(components) {
                return candidate
            }
            candidate = candidate.addingTimeInterval(60)
        }

        return nil // No match within a year.
    }
}
