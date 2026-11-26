import XCTest
@testable import MetronomeCore

final class URLCommandTests: XCTestCase {
    func testAddURLDecodesTheCommand() throws {
        let url = URL(string: "metronome://add?cmd=5m%20every%20Check%20dashboards%20~ping")!
        XCTAssertEqual(try URLCommand.request(from: url),
                       ControlRequest(command: .add, text: "5m every Check dashboards ~ping"))
        // A + is a literal plus in URLComponents, and @ survives encoding.
        let deadline = URL(string: "metronome://add?cmd=%4014%3A30%20Vendor")!
        XCTAssertEqual(try URLCommand.request(from: deadline).text, "@14:30 Vendor")
    }

    func testURLTimersAreAgentAdded() throws {
        let engine = TimerEngine()
        let request = try URLCommand.request(from: URL(string: "metronome://add?cmd=20m%20Rollback")!)
        XCTAssertEqual(ControlService(engine: engine).handle(request).timer?.source, .agent)
        XCTAssertEqual(engine.timers().first?.name, "Rollback")
    }

    func testRejectsOtherURLs() {
        for text in ["metronome://stop?cmd=x", "metronome://add", "metronome://add?cmd=", "https://add?cmd=5m"] {
            XCTAssertThrowsError(try URLCommand.request(from: URL(string: text)!), text)
        }
    }
}
