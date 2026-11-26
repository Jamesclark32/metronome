import Foundation

/// Parses one-line timer commands such as:
///
///     5m every Check dashboards ~ping
///     @14:30 Vendor callback ~submarine
///     1h 20m Rollback decision
///
/// The command starts with a duration (`90s`, `5m`, `1h 20m`, `1h20m`, `1:30` = 1 min 30 s,
/// `1:30:00` = 1 h 30 min) or a wall-clock time (`@14:30`, `@2:30pm`, `@9am`), optionally with
/// `every` before or after the duration. `~sound` may appear anywhere. The rest is the name.
public enum QuickEntry {
    public static let example = "5m every Check dashboards ~ping"

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) throws -> TimerSpec {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens.isEmpty {
            throw MetronomeError("Type a duration like 5m or a time like @14:30, then a name.")
        }

        var sound: Sound?
        tokens = try tokens.filter { token in
            guard token.hasPrefix("~") else { return true }
            let name = String(token.dropFirst())
            guard let match = Sound(name: name) else {
                let choices = Sound.allCases.map(\.rawValue).joined(separator: ", ")
                throw MetronomeError("Unknown sound ~\(name). Choose one of: \(choices).")
            }
            sound = match
            return false
        }

        var seconds: TimeInterval = 0
        var sawDuration = false
        var repeats = false
        var deadline: Date?
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.lowercased() == "every" {
                repeats = true
            } else if token.hasPrefix("@") {
                var clock = String(token.dropFirst())
                if clock.isEmpty, index + 1 < tokens.count {
                    index += 1
                    clock = tokens[index]
                }
                deadline = try nextOccurrence(of: clock, after: now, calendar: calendar)
            } else if let duration = parseDuration(token) {
                seconds += duration
                sawDuration = true
            } else {
                break
            }
            index += 1
        }
        let name = tokens[index...].joined(separator: " ")

        if let deadline {
            if sawDuration { throw MetronomeError("Use a duration or an @time, not both.") }
            if repeats { throw MetronomeError("every needs a duration, such as 5m every Check dashboards.") }
            return TimerSpec(name: name.isEmpty ? "Deadline" : name, schedule: .deadline(deadline), sound: sound)
        }
        guard sawDuration else {
            throw MetronomeError("Start with a duration (5m, 1h 20m, 1:30) or a time (@14:30).")
        }
        guard seconds > 0 else { throw MetronomeError("The duration must be more than zero.") }
        return TimerSpec(
            name: name.isEmpty ? "Timer" : name,
            schedule: repeats ? .interval(seconds) : .countdown(seconds),
            sound: sound)
    }

    /// Builds a timer from separate fields, as the MCP `add_timer` tool sends them.
    /// Give either `duration` (with `every` to repeat) or `at`.
    public static func spec(
        name: String?, duration: String?, every: Bool, at: String?, sound: String?,
        now: Date = Date(), calendar: Calendar = .current
    ) throws -> TimerSpec {
        var soundValue: Sound?
        if let sound, !sound.isEmpty {
            let name = sound.hasPrefix("~") ? String(sound.dropFirst()) : sound
            guard let match = Sound(name: name) else {
                let choices = Sound.allCases.map(\.rawValue).joined(separator: ", ")
                throw MetronomeError("Unknown sound \(sound). Choose one of: \(choices).")
            }
            soundValue = match
        }
        let name = name?.trimmingCharacters(in: .whitespaces) ?? ""
        let duration = duration?.trimmingCharacters(in: .whitespaces) ?? ""
        let at = at?.trimmingCharacters(in: .whitespaces) ?? ""

        if !at.isEmpty {
            if !duration.isEmpty { throw MetronomeError("Use a duration or an at time, not both.") }
            if every { throw MetronomeError("every needs a duration, not an at time.") }
            let clock = at.hasPrefix("@") ? String(at.dropFirst()) : at
            let date = try nextOccurrence(of: clock, after: now, calendar: calendar)
            return TimerSpec(name: name.isEmpty ? "Deadline" : name, schedule: .deadline(date), sound: soundValue)
        }
        guard !duration.isEmpty else { throw MetronomeError("Give a duration such as 5m, or an at time such as 14:30.") }
        guard let seconds = parseDurationPhrase(duration) else {
            throw MetronomeError("Can't read the duration \"\(duration)\"; use 90s, 5m, 1h 20m, or 1:30.")
        }
        guard seconds > 0 else { throw MetronomeError("The duration must be more than zero.") }
        return TimerSpec(
            name: name.isEmpty ? "Timer" : name,
            schedule: every ? .interval(seconds) : .countdown(seconds),
            sound: soundValue)
    }

    /// One or more duration tokens, such as `1h 20m`; nil when any token is not a duration.
    public static func parseDurationPhrase(_ text: String) -> TimeInterval? {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return nil }
        var total: TimeInterval = 0
        for token in tokens {
            guard let seconds = parseDuration(String(token)) else { return nil }
            total += seconds
        }
        return total
    }

    /// `90s`, `5m`, `1h`, `1h20m`, `1:30` (m:ss), `1:30:00` (h:mm:ss); nil when not a duration.
    static func parseDuration(_ token: String) -> TimeInterval? {
        let token = token.lowercased()
        if token.contains(":") {
            let parts = token.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count),
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
                  parts.dropFirst().allSatisfy({ $0.count == 2 && Int($0)! < 60 })
            else { return nil }
            return parts.reduce(0) { $0 * 60 + TimeInterval(Int($1)!) }
        }
        var total: TimeInterval = 0
        var digits = ""
        var units: [Character] = []
        for char in token {
            if char.isASCIIDigit {
                digits.append(char)
            } else if let scale = ["h": 3600.0, "m": 60.0, "s": 1.0][String(char)] {
                guard !digits.isEmpty, !units.contains(char) else { return nil }
                total += TimeInterval(Int(digits)!) * scale
                units.append(char)
                digits = ""
            } else {
                return nil
            }
        }
        return units.isEmpty || !digits.isEmpty ? nil : total
    }

    /// The next time the clock shows `clock` (`14:30`, `2:30pm`, `9am`), strictly after `now`.
    static func nextOccurrence(of clock: String, after now: Date, calendar: Calendar) throws -> Date {
        let invalid = MetronomeError("Can't read the time @\(clock); use 24-hour 14:30 or 2:30pm.")
        var text = clock.lowercased()
        var meridiem: String?
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            meridiem = suffix
            text.removeLast(2)
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isASCIIDigit) }),
              var hour = Int(parts[0])
        else { throw invalid }
        let minute = parts.count == 2 ? Int(parts[1])! : 0
        if parts.count == 2 && parts[1].count != 2 { throw invalid }
        if let meridiem {
            guard (1...12).contains(hour) else { throw invalid }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        } else if parts.count == 1 {
            throw invalid  // "@9" is ambiguous; ask for 9:00 or 9am.
        }
        guard (0...23).contains(hour), (0...59).contains(minute),
              let date = calendar.nextDate(
                after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                matchingPolicy: .nextTime)
        else { throw invalid }
        return date
    }
}

/// Short human-readable times for the menu bar, popover, and CLI.
public enum TimeFormat {
    /// A countdown such as `4:59` or `1:02:03`, rounded up so it reads 0:00 only when due.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// A length such as `90s`, `5m`, or `1h 20m`.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let parts = [(total / 3600, "h"), (total / 60 % 60, "m"), (total % 60, "s")]
            .filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
