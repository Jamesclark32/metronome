import Foundation

/// One request to the app over the control socket, sent as a single line of JSON.
public struct ControlRequest: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable {
        case add, list, stop, pause, resume, snooze
    }

    public var command: Command
    /// add: a quick-entry command such as `5m every Check dashboards ~ping`.
    public var text: String?
    /// add, structured form, used when `text` is nil.
    public var name: String?
    /// add: a duration such as `5m` or `1h 20m`. snooze: how long (default 5m).
    public var duration: String?
    public var every: Bool?
    /// add: a wall-clock time such as `14:30` or `2:30pm`.
    public var at: String?
    public var sound: String?
    /// stop, pause, resume, snooze: a timer id or name.
    public var target: String?

    public init(
        command: Command, text: String? = nil, name: String? = nil, duration: String? = nil,
        every: Bool? = nil, at: String? = nil, sound: String? = nil, target: String? = nil
    ) {
        self.command = command
        self.text = text
        self.name = name
        self.duration = duration
        self.every = every
        self.at = at
        self.sound = sound
        self.target = target
    }
}

/// A timer as reported to the CLI and MCP clients.
public struct TimerInfo: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    /// countdown, interval, or deadline.
    public var kind: String
    public var state: TimerState
    public var source: TimerSource
    public var sound: Sound
    public var remainingSeconds: Int
    /// When it fires next; nil while paused or done.
    public var nextFire: Date?
    public var repeatSeconds: Int?

    public init(_ timer: MetronomeTimer, now: Date) {
        id = timer.id
        name = timer.name
        switch timer.schedule {
        case .countdown: kind = "countdown"
        case .interval: kind = "interval"
        case .deadline: kind = "deadline"
        }
        state = timer.state
        source = timer.source
        sound = timer.sound
        remainingSeconds = Int(timer.remaining(at: now).rounded(.up))
        nextFire = timer.nextFire
        repeatSeconds = timer.repeatInterval.map { Int($0) }
    }
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?
    /// The timer that was added or changed.
    public var timer: TimerInfo?
    /// list: every timer, soonest due first.
    public var timers: [TimerInfo]?

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, error: message)
    }

    public init(ok: Bool, error: String? = nil, timer: TimerInfo? = nil, timers: [TimerInfo]? = nil) {
        self.ok = ok
        self.error = error
        self.timer = timer
        self.timers = timers
    }
}

public enum ControlJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Carries out control requests against the engine. Everything added this way
/// is marked as agent-added: it came from another app, not from the popover.
public struct ControlService: Sendable {
    public let engine: TimerEngine

    public init(engine: TimerEngine) {
        self.engine = engine
    }

    public func handle(_ request: ControlRequest, now: Date = Date()) -> ControlResponse {
        do {
            switch request.command {
            case .add:
                let spec: TimerSpec
                if let text = request.text {
                    spec = try QuickEntry.parse(text, now: now)
                } else {
                    spec = try QuickEntry.spec(
                        name: request.name, duration: request.duration, every: request.every ?? false,
                        at: request.at, sound: request.sound, now: now)
                }
                return changed(engine.add(spec, source: .agent, now: now), now)
            case .list:
                return ControlResponse(ok: true, timers: engine.timers(now: now).map { TimerInfo($0, now: now) })
            case .stop:
                return changed(try engine.stop(id: target(request).id), now)
            case .pause:
                return changed(try engine.pause(id: target(request).id, now: now), now)
            case .resume:
                return changed(try engine.resume(id: target(request).id, now: now), now)
            case .snooze:
                var seconds = TimerEngine.defaultSnooze
                if let duration = request.duration {
                    guard let parsed = QuickEntry.parseDurationPhrase(duration), parsed > 0 else {
                        throw MetronomeError("Can't read the snooze length \"\(duration)\"; use 5m or 1h 20m.")
                    }
                    seconds = parsed
                }
                return changed(try engine.snooze(id: target(request).id, by: seconds, now: now), now)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Decodes one JSON request and encodes its response.
    public func handle(json: Data) -> Data {
        let response: ControlResponse
        if let request = try? ControlJSON.decoder.decode(ControlRequest.self, from: json) {
            response = handle(request)
        } else {
            response = .failure("Invalid request.")
        }
        return (try? ControlJSON.encoder.encode(response)) ?? Data(#"{"ok":false}"#.utf8)
    }

    private func target(_ request: ControlRequest) throws -> MetronomeTimer {
        guard let target = request.target, !target.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MetronomeError("Name a timer by id or name.")
        }
        return try engine.timer(matching: target)
    }

    private func changed(_ timer: MetronomeTimer, _ now: Date) -> ControlResponse {
        ControlResponse(ok: true, timer: TimerInfo(timer, now: now))
    }
}
