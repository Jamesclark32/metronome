import Foundation
import MetronomeCore

let usage = """
    Usage: metronome <command>

      add <command>              Add a timer, e.g. metronome add "5m every Check dashboards ~ping"
      list [--json]              List timers with time left, repeat interval, sound, and state
      stop <id or name>          Stop a timer, or dismiss one that is done
      pause <id or name>         Pause a countdown or interval timer
      resume <id or name>        Resume a paused timer
      snooze <id or name> [--for 10m]
                                 Put off a timer's next firing (default 5m)
      mcp                        Run the MCP server on stdin/stdout (for AI agents)
      version                    Print the version

    Timer commands: a duration (90s, 5m, 1h 20m, 1:30) or a time (@14:30, @2:30pm),
    optional "every" to repeat, optional ~sound (glass, ping, submarine, hero, purr),
    then the name. Timers added here are marked 🤖 in the menu bar.
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("metronome: \(message)\n".utf8))
    exit(code)
}

func send(_ request: ControlRequest) -> ControlResponse {
    do {
        let response = try ControlClient.send(request)
        if !response.ok { fail(response.error ?? "The request failed.") }
        return response
    } catch {
        fail(error.localizedDescription, code: 3)
    }
}

func describe(_ timer: TimerInfo) -> String {
    let marker = timer.source == .agent ? "🤖 " : ""
    let left: String
    switch timer.state {
    case .done: left = "done"
    case .paused: left = "paused, \(TimeFormat.clock(TimeInterval(timer.remainingSeconds))) left"
    case .running: left = "\(TimeFormat.clock(TimeInterval(timer.remainingSeconds))) left"
    }
    let repeats = timer.repeatSeconds.map { ", every \(TimeFormat.duration(TimeInterval($0)))" } ?? ""
    return "#\(timer.id) \(marker)\(timer.name) (\(left)\(repeats), \(timer.sound.displayName))"
}

func printTable(_ timers: [TimerInfo]) {
    guard !timers.isEmpty else {
        print("No timers.")
        return
    }
    let rows = [["ID", "NAME", "LEFT", "REPEAT", "SOUND", "STATE"]] + timers.map { timer in
        [
            "\(timer.id)",
            (timer.source == .agent ? "🤖 " : "") + timer.name,
            timer.state == .done ? "-" : TimeFormat.clock(TimeInterval(timer.remainingSeconds)),
            timer.repeatSeconds.map { "every \(TimeFormat.duration(TimeInterval($0)))" } ?? "-",
            timer.sound.displayName,
            timer.state.rawValue,
        ]
    }
    // Terminal columns: emoji such as 🤖 take two.
    func columns(_ text: String) -> Int {
        text.count + text.filter { $0.unicodeScalars.first!.properties.isEmojiPresentation }.count
    }
    let widths = (0..<rows[0].count).map { column in rows.map { columns($0[column]) }.max()! }
    for row in rows {
        let cells = zip(row, widths).map { cell, width in cell + String(repeating: " ", count: width - columns(cell)) }
        print(cells.joined(separator: "  ").trimmingCharacters(in: .whitespaces))
    }
}

/// Splits `<target> [--for <duration>]`.
func targetAndDuration(_ args: [String]) -> (String, String?) {
    var words = args
    var duration: String?
    if let flag = words.firstIndex(of: "--for") {
        guard flag + 1 < words.count else { fail("--for needs a duration, such as --for 10m.", code: 2) }
        duration = words[(flag + 1)...].joined(separator: " ")
        words = Array(words[..<flag])
    }
    let target = words.joined(separator: " ")
    if target.isEmpty { fail("Name a timer by id or name.", code: 2) }
    return (target, duration)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(2)
}
args.removeFirst()

switch command {
case "add":
    let text = args.joined(separator: " ")
    if text.isEmpty { fail("Give a timer command, such as: metronome add \"5m Check dashboards\"", code: 2) }
    print("Added " + describe(send(ControlRequest(command: .add, text: text)).timer!))
case "list", "ls":
    let timers = send(ControlRequest(command: .list)).timers ?? []
    if args.contains("--json") {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(timers), as: UTF8.self))
    } else {
        printTable(timers)
    }
case "stop", "pause", "resume", "snooze":
    let (target, duration) = targetAndDuration(args)
    if duration != nil && command != "snooze" { fail("--for only applies to snooze.", code: 2) }
    let request = ControlRequest(command: .init(rawValue: command)!, duration: duration, target: target)
    let timer = send(request).timer!
    let verb = ["stop": "Stopped", "pause": "Paused", "resume": "Resumed", "snooze": "Snoozed"][command]!
    print("\(verb) " + describe(timer))
case "mcp":
    // Connects per call, so the server starts even before the app does and
    // reports "not running" as a tool error.
    MCPServer(send: { try ControlClient.send($0) }).runStdio()
case "version", "--version", "-v":
    print("metronome \(Metronome.version)")
case "help", "--help", "-h":
    print(usage)
default:
    fail("Unknown command \"\(command)\".\n\n\(usage)", code: 2)
}
