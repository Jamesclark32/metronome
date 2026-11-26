import Foundation

/// The built-in macOS system sounds a timer can play.
public enum Sound: String, CaseIterable, Codable, Sendable {
    case glass, ping, submarine, hero, purr

    public var displayName: String { rawValue.capitalized }

    /// Matches a sound name case-insensitively, such as "Ping" or "ping".
    public init?(name: String) {
        self.init(rawValue: name.lowercased())
    }
}

/// When a timer fires.
public enum Schedule: Equatable, Sendable {
    /// Fires once, this many seconds after it starts.
    case countdown(TimeInterval)
    /// Fires every this many seconds until stopped.
    case interval(TimeInterval)
    /// Fires once at a wall-clock time.
    case deadline(Date)
}

public enum TimerState: String, Codable, Sendable {
    case running, paused, done
}

/// Who started a timer: the person at the keyboard, or another app or agent.
public enum TimerSource: String, Codable, Sendable {
    case user, agent
}

/// What to start: the result of parsing a command such as `5m every Check dashboards ~ping`.
public struct TimerSpec: Equatable, Sendable {
    public var name: String
    public var schedule: Schedule
    /// nil picks the next sound in rotation.
    public var sound: Sound?

    public init(name: String, schedule: Schedule, sound: Sound? = nil) {
        self.name = name
        self.schedule = schedule
        self.sound = sound
    }
}

public struct MetronomeTimer: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let schedule: Schedule
    public let sound: Sound
    public let source: TimerSource
    public internal(set) var state: TimerState
    /// The absolute time a running timer fires next, or the time a done timer fired.
    /// Absolute so the display stays right after the Mac sleeps.
    public internal(set) var dueDate: Date
    /// Time left when paused.
    public internal(set) var pausedRemaining: TimeInterval?

    /// Seconds until the timer fires; frozen while paused, zero once done.
    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running: return max(0, dueDate.timeIntervalSince(now))
        case .paused: return pausedRemaining ?? 0
        case .done: return 0
        }
    }

    /// When the timer fires next, or nil while paused or done.
    public var nextFire: Date? { state == .running ? dueDate : nil }

    /// The repeat period of an interval timer.
    public var repeatInterval: TimeInterval? {
        if case .interval(let seconds) = schedule { return seconds }
        return nil
    }

    /// Sort key for "next due": done timers first, then by when they will fire.
    func sortKey(at now: Date) -> Date {
        state == .paused ? now.addingTimeInterval(remaining(at: now)) : dueDate
    }
}

public struct MetronomeError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
