import Darwin
import XCTest
@testable import MetronomeCore

final class ControlServiceTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testAddFromTextIsMarkedAgent() throws {
        let service = ControlService(engine: TimerEngine())
        let response = service.handle(ControlRequest(command: .add, text: "5m every Check dashboards ~ping"), now: t0)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.timer?.name, "Check dashboards")
        XCTAssertEqual(response.timer?.source, .agent)
        XCTAssertEqual(response.timer?.repeatSeconds, 300)
        XCTAssertEqual(response.timer?.sound, .ping)
    }

    func testStructuredAdd() {
        let service = ControlService(engine: TimerEngine())
        let response = service.handle(
            ControlRequest(command: .add, name: "Status update", duration: "1h 20m", every: true, sound: "Hero"), now: t0)
        XCTAssertEqual(response.timer?.kind, "interval")
        XCTAssertEqual(response.timer?.remainingSeconds, 4_800)
        XCTAssertEqual(response.timer?.sound, .hero)

        let bad = service.handle(ControlRequest(command: .add, name: "x", duration: "5m", at: "14:30"), now: t0)
        XCTAssertFalse(bad.ok)
        XCTAssertNotNil(bad.error)
    }

    func testListReportsRemainingNextFireAndState() throws {
        let engine = TimerEngine()
        let service = ControlService(engine: engine)
        engine.add(TimerSpec(name: "Rollback", schedule: .countdown(1_200)), source: .user, now: t0)
        _ = service.handle(ControlRequest(command: .add, text: "90s Tea"), now: t0)
        _ = service.handle(ControlRequest(command: .pause, target: "rollback"), now: t0.addingTimeInterval(200))

        let timers = try XCTUnwrap(service.handle(ControlRequest(command: .list), now: t0.addingTimeInterval(30)).timers)
        XCTAssertEqual(timers.map(\.name), ["Tea", "Rollback"])
        XCTAssertEqual(timers[0].remainingSeconds, 60)
        XCTAssertEqual(timers[0].nextFire, t0.addingTimeInterval(90))
        XCTAssertEqual(timers[1].state, .paused)
        XCTAssertEqual(timers[1].remainingSeconds, 1_000)
        XCTAssertNil(timers[1].nextFire)
        XCTAssertEqual(timers[1].source, .user)
    }

    func testStopSnoozeAndErrors() {
        let engine = TimerEngine()
        let service = ControlService(engine: engine)
        _ = service.handle(ControlRequest(command: .add, text: "10m Rollback"), now: t0)

        let snoozed = service.handle(ControlRequest(command: .snooze, duration: "2m", target: "Rollback"), now: t0)
        XCTAssertEqual(snoozed.timer?.remainingSeconds, 720)
        XCTAssertFalse(service.handle(ControlRequest(command: .snooze, duration: "soon", target: "1"), now: t0).ok)
        XCTAssertFalse(service.handle(ControlRequest(command: .stop, target: "nope"), now: t0).ok)
        XCTAssertTrue(service.handle(ControlRequest(command: .stop, target: "1"), now: t0).ok)
        XCTAssertTrue(engine.timers().isEmpty)
    }

    func testInvalidJSON() throws {
        let reply = ControlService(engine: TimerEngine()).handle(json: Data("not json".utf8))
        let response = try ControlJSON.decoder.decode(ControlResponse.self, from: reply)
        XCTAssertFalse(response.ok)
    }
}

final class ControlSocketTests: XCTestCase {
    func testRoundTripOverAUserOnlySocket() throws {
        let directory = "/tmp/mtr-\(getpid())-\(Int.random(in: 0..<1_000_000))"
        let path = directory + "/control.sock"
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let engine = TimerEngine()
        let service = ControlService(engine: engine)
        try ControlServer(path: path) { service.handle(json: $0) }.start()

        var info = stat()
        XCTAssertEqual(stat(path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600, "socket is readable only by its owner")
        XCTAssertEqual(stat(directory, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o700)

        let added = try ControlClient.send(ControlRequest(command: .add, text: "5m every Check dashboards"), path: path)
        XCTAssertEqual(added.timer?.source, .agent)
        let listed = try ControlClient.send(ControlRequest(command: .list), path: path)
        XCTAssertEqual(listed.timers?.map(\.name), ["Check dashboards"])
        XCTAssertEqual(engine.timers().first?.source, .agent)
    }

    func testClearErrorWhenAppIsNotRunning() {
        XCTAssertThrowsError(try ControlClient.send(ControlRequest(command: .list), path: "/tmp/no-such-metronome.sock")) {
            XCTAssertEqual($0.localizedDescription, ControlClient.notRunning)
        }
    }
}
