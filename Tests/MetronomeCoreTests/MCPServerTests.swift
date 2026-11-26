import XCTest
@testable import MetronomeCore

final class MCPServerTests: XCTestCase {
    let engine = TimerEngine()
    lazy var server = MCPServer { [engine] in ControlService(engine: engine).handle($0) }

    func call(_ message: [String: Any]) throws -> [String: Any] {
        let line = try JSONSerialization.data(withJSONObject: message)
        let reply = try XCTUnwrap(server.handle(line: line))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }

    func tool(_ name: String, _ arguments: [String: Any] = [:]) throws -> (text: String, isError: Bool) {
        let reply = try call(["jsonrpc": "2.0", "id": 9, "method": "tools/call",
                              "params": ["name": name, "arguments": arguments]])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return (content[0]["text"] as? String ?? "", result["isError"] as? Bool ?? false)
    }

    func testHandshake() throws {
        let initialize = try call(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                   "params": ["protocolVersion": "2025-03-26", "capabilities": [:],
                                              "clientInfo": ["name": "test", "version": "1"]]])
        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])

        XCTAssertNil(server.handle(line: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)))

        let list = try call(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String },
                       ["add_timer", "list_timers", "stop_timer", "pause_timer", "resume_timer", "snooze_timer"])
    }

    func testToolsDriveTheEngineAsAgent() throws {
        XCTAssertFalse(try tool("add_timer", ["command": "5m every Check dashboards ~ping"]).isError)
        XCTAssertFalse(try tool("add_timer", ["name": "Rollback", "duration": "20m", "sound": "hero"]).isError)
        XCTAssertTrue(engine.timers().allSatisfy { $0.source == .agent })

        let listed = try tool("list_timers")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(listed.text.utf8)) as? [String: Any])
        let timers = try XCTUnwrap(json["timers"] as? [[String: Any]])
        XCTAssertEqual(timers.map { $0["name"] as? String }, ["Check dashboards", "Rollback"])
        XCTAssertEqual(timers[0]["repeat_seconds"] as? Int, 300)
        XCTAssertEqual(timers[0]["sound"] as? String, "ping")
        XCTAssertNotNil(timers[0]["next_fire"] as? String)
        XCTAssertEqual(timers[1]["remaining"] as? String, "20:00")

        XCTAssertFalse(try tool("pause_timer", ["timer": "rollback"]).isError)
        XCTAssertEqual(engine.timers().last?.state, .paused)
        XCTAssertFalse(try tool("resume_timer", ["timer": "Rollback"]).isError)
        XCTAssertFalse(try tool("snooze_timer", ["timer": "check", "duration": "10m"]).isError)
        XCTAssertFalse(try tool("stop_timer", ["timer": 1]).isError, "numeric ids work too")
        XCTAssertEqual(engine.timers().map(\.name), ["Rollback"])
    }

    func testErrorsAreToolErrors() throws {
        let bad = try tool("add_timer", ["command": "5x nope"])
        XCTAssertTrue(bad.isError)
        XCTAssertTrue(bad.text.contains("Start with a duration"))
        XCTAssertTrue(try tool("stop_timer", ["timer": "missing"]).isError)

        let offline = MCPServer { _ in throw MetronomeError(ControlClient.notRunning) }
        let line = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "list_timers", "arguments": [:]],
        ])
        let reply = String(decoding: try XCTUnwrap(offline.handle(line: line)), as: UTF8.self)
        XCTAssertTrue(reply.contains("not running"))
        XCTAssertTrue(reply.contains(#""isError":true"#))
    }

    func testUnknownMethodAndParseError() throws {
        let unknown = try call(["jsonrpc": "2.0", "id": 4, "method": "resources/list"])
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        let garbage = try XCTUnwrap(server.handle(line: Data("{".utf8)))
        XCTAssertTrue(String(decoding: garbage, as: UTF8.self).contains("-32700"))
    }
}
