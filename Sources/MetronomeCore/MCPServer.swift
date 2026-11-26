import Foundation

/// A Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0).
/// Each tool call becomes a control request sent to the running app.
public final class MCPServer {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let send: (ControlRequest) throws -> ControlResponse

    /// `send` delivers a request to the app; `metronome mcp` passes `ControlClient.send`.
    public init(send: @escaping (ControlRequest) throws -> ControlResponse) {
        self.send = send
    }

    /// Handles one JSON-RPC message and returns the reply line, or nil for notifications.
    public func handle(line: Data) -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        // Requests carry an id; notifications such as notifications/initialized do not.
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        let result: [String: Any]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            result = [
                "protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "metronome", "version": Metronome.version],
                "instructions": """
                    Metronome is a macOS menu-bar timer app. Use these tools to start reminders \
                    (countdowns, repeating intervals, wall-clock deadlines) that play a sound and \
                    post a notification. Timers you add are marked with 🤖. The app must be running.
                    """,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.tools]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            result = callTool(name, arguments)
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    // MARK: - Tools

    private static var timerArgument: [String: Any] {
        ["type": "string", "description": "The timer's id (from list_timers) or name; a unique name prefix works too."]
    }

    static var tools: [[String: Any]] { [
        [
            "name": "add_timer",
            "description": """
                Start a timer. Either pass `command`, a one-line Metronome command such as \
                "5m every Check dashboards ~ping", "@14:30 Vendor callback", or "20m Rollback decision"; \
                or pass `name` plus `duration` (optionally with `every: true` to repeat) or `at`.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "One-line command: duration or @time, optional 'every', optional ~sound, then the name."],
                    "name": ["type": "string", "description": "What the reminder is for."],
                    "duration": ["type": "string", "description": "Length such as 90s, 5m, 1h 20m, or 1:30 (m:ss)."],
                    "every": ["type": "boolean", "description": "Repeat every `duration` until stopped."],
                    "at": ["type": "string", "description": "Wall-clock time such as 14:30 or 2:30pm (the next time it occurs)."],
                    "sound": ["type": "string", "enum": Sound.allCases.map(\.rawValue), "description": "Omit to rotate through sounds."],
                ],
            ],
        ],
        [
            "name": "list_timers",
            "description": "List every timer with its name, time remaining, next fire time, repeat interval, sound, state, and whether an agent added it.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "stop_timer",
            "description": "Stop a timer, or dismiss one that is done.",
            "inputSchema": ["type": "object", "properties": ["timer": timerArgument], "required": ["timer"]],
        ],
        [
            "name": "pause_timer",
            "description": "Pause a countdown or repeating timer. Deadlines cannot be paused.",
            "inputSchema": ["type": "object", "properties": ["timer": timerArgument], "required": ["timer"]],
        ],
        [
            "name": "resume_timer",
            "description": "Resume a paused timer.",
            "inputSchema": ["type": "object", "properties": ["timer": timerArgument], "required": ["timer"]],
        ],
        [
            "name": "snooze_timer",
            "description": "Put off a timer's next firing. A done timer starts again.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "timer": timerArgument,
                    "duration": ["type": "string", "description": "How long, such as 5m (the default) or 1h."],
                ],
                "required": ["timer"],
            ],
        ],
    ] }

    private func callTool(_ name: String, _ args: [String: Any]) -> [String: Any] {
        let request: ControlRequest
        let target = args["timer"].map { "\($0)" }
        switch name {
        case "add_timer":
            if let command = args["command"] as? String, !command.trimmingCharacters(in: .whitespaces).isEmpty {
                request = ControlRequest(command: .add, text: command)
            } else {
                request = ControlRequest(
                    command: .add, name: args["name"] as? String, duration: args["duration"] as? String,
                    every: args["every"] as? Bool, at: args["at"] as? String, sound: args["sound"] as? String)
            }
        case "list_timers": request = ControlRequest(command: .list)
        case "stop_timer": request = ControlRequest(command: .stop, target: target)
        case "pause_timer": request = ControlRequest(command: .pause, target: target)
        case "resume_timer": request = ControlRequest(command: .resume, target: target)
        case "snooze_timer": request = ControlRequest(command: .snooze, duration: args["duration"] as? String, target: target)
        default: return toolResult("Unknown tool \(name).", isError: true)
        }

        let response: ControlResponse
        do {
            response = try send(request)
        } catch {
            return toolResult(error.localizedDescription, isError: true)
        }
        guard response.ok else { return toolResult(response.error ?? "The request failed.", isError: true) }

        if let timers = response.timers {
            return toolResult(Self.json(["timers": timers.map(Self.describe)]), isError: false)
        }
        let verb = ["add_timer": "Added", "stop_timer": "Stopped", "pause_timer": "Paused",
                    "resume_timer": "Resumed", "snooze_timer": "Snoozed"][name] ?? "Done"
        let timer = response.timer.map(Self.describe) ?? [:]
        return toolResult("\(verb) timer.\n" + Self.json(timer), isError: false)
    }

    /// A timer as agents see it, with times both in seconds and as text.
    static func describe(_ timer: TimerInfo) -> [String: Any] {
        var info: [String: Any] = [
            "id": timer.id,
            "name": timer.name,
            "kind": timer.kind,
            "state": timer.state.rawValue,
            "source": timer.source.rawValue,
            "sound": timer.sound.rawValue,
            "remaining_seconds": timer.remainingSeconds,
            "remaining": timer.state == .done ? "done" : TimeFormat.clock(TimeInterval(timer.remainingSeconds)),
            "next_fire": timer.nextFire.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "repeat_seconds": timer.repeatSeconds ?? NSNull(),
        ]
        if let seconds = timer.repeatSeconds { info["repeat"] = "every " + TimeFormat.duration(TimeInterval(seconds)) }
        return info
    }

    private func toolResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static func json(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
    }

    /// Reads JSON-RPC lines from stdin and answers on stdout until stdin closes.
    public func runStdio() {
        let output = FileHandle.standardOutput
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let reply = handle(line: Data(line.utf8))
            else { continue }
            output.write(reply + Data("\n".utf8))
        }
    }
}
