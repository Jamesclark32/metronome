import Foundation

/// Turns `metronome://add?cmd=5m%20every%20Check%20dashboards` into a control request,
/// so URLs go through the same parser as the CLI and are marked as agent-added.
public enum URLCommand {
    public static let scheme = "metronome"

    public static func request(from url: URL) throws -> ControlRequest {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme
        else { throw MetronomeError("Not a metronome:// URL.") }
        // metronome://add?… has host "add"; metronome:add?… has path "add".
        let action = (components.host ?? components.path).lowercased()
        guard action == "add" else {
            throw MetronomeError("Unknown metronome:// action \"\(action)\"; use metronome://add?cmd=….")
        }
        guard let command = components.queryItems?.first(where: { $0.name == "cmd" })?.value,
              !command.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw MetronomeError("metronome://add needs a cmd, such as metronome://add?cmd=5m%20Tea.") }
        return ControlRequest(command: .add, text: command)
    }
}
