import XCTest
@testable import MetronomeCore

final class TimerEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testNewEngineIsEmpty() {
        XCTAssertTrue(TimerEngine().timers().isEmpty)
    }

    func testCountdownFiresOnceThenIsDoneUntilStopped() throws {
        let engine = TimerEngine()
        let timer = engine.add(TimerSpec(name: "Rollback", schedule: .countdown(60)), source: .user, now: t0)

        XCTAssertEqual(engine.tick(now: at(59.9)), [])
        XCTAssertEqual(engine.tick(now: at(60)).map(\.id), [timer.id])
        XCTAssertEqual(engine.timers(now: at(61)).first?.state, .done)
        XCTAssertEqual(engine.tick(now: at(500)), [], "a done timer does not fire again")

        try engine.stop(id: timer.id)
        XCTAssertTrue(engine.timers().isEmpty)
    }

    func testIntervalReschedulesFromItsDueTimeAndFiresOnceAfterSleep() {
        let engine = TimerEngine()
        engine.add(TimerSpec(name: "Dashboards", schedule: .interval(300)), source: .user, now: t0)

        XCTAssertEqual(engine.tick(now: at(302)).count, 1)
        // Next due is 600, measured from the due time, not from when tick ran.
        XCTAssertEqual(engine.timers()[0].dueDate, at(600))
        XCTAssertEqual(engine.timers()[0].state, .running)

        // The Mac slept past three periods: one firing, then the next future slot.
        XCTAssertEqual(engine.tick(now: at(1_550)).count, 1)
        XCTAssertEqual(engine.timers()[0].dueDate, at(1_800))
    }

    func testDeadlineIsAbsolute() {
        let engine = TimerEngine()
        let deadline = at(3_600)
        engine.add(TimerSpec(name: "Vendor", schedule: .deadline(deadline)), source: .user, now: t0)
        XCTAssertEqual(engine.timers()[0].remaining(at: at(3_000)), 600)
        XCTAssertEqual(engine.tick(now: at(3_599)), [])
        XCTAssertEqual(engine.tick(now: at(3_700)).count, 1)
    }

    func testPauseFreezesRemainingAndResumeContinues() throws {
        let engine = TimerEngine()
        let timer = engine.add(TimerSpec(name: "Tea", schedule: .countdown(100)), source: .user, now: t0)

        try engine.pause(id: timer.id, now: at(30))
        XCTAssertEqual(engine.timers()[0].remaining(at: at(1_000)), 70)
        XCTAssertNil(engine.timers()[0].nextFire)
        XCTAssertEqual(engine.tick(now: at(1_000)), [], "paused timers do not fire")

        try engine.resume(id: timer.id, now: at(1_000))
        XCTAssertEqual(engine.timers()[0].dueDate, at(1_070))
        XCTAssertThrowsError(try engine.resume(id: timer.id, now: at(1_001)))
    }

    func testDeadlinesCannotBePaused() {
        let engine = TimerEngine()
        let timer = engine.add(TimerSpec(name: "Vendor", schedule: .deadline(at(60))), source: .user, now: t0)
        XCTAssertThrowsError(try engine.pause(id: timer.id, now: t0))
    }

    func testSnoozePostponesRunningAndRearmsDone() throws {
        let engine = TimerEngine()
        let timer = engine.add(TimerSpec(name: "Tea", schedule: .countdown(60)), source: .user, now: t0)

        try engine.snooze(id: timer.id, by: 120, now: at(10))
        XCTAssertEqual(engine.timers()[0].dueDate, at(180))

        XCTAssertEqual(engine.tick(now: at(180)).count, 1)
        try engine.snooze(id: timer.id, by: 300, now: at(200))
        XCTAssertEqual(engine.timers()[0].state, .running)
        XCTAssertEqual(engine.timers()[0].dueDate, at(500))
    }

    func testTimersAreOrderedByNextDueWithDoneFirst() throws {
        let engine = TimerEngine()
        let late = engine.add(TimerSpec(name: "Late", schedule: .countdown(900)), source: .user, now: t0)
        let paused = engine.add(TimerSpec(name: "Paused", schedule: .countdown(400)), source: .user, now: t0)
        let soon = engine.add(TimerSpec(name: "Soon", schedule: .interval(300)), source: .agent, now: t0)
        let done = engine.add(TimerSpec(name: "Done", schedule: .countdown(5)), source: .user, now: t0)
        try engine.pause(id: paused.id, now: t0)  // 400s left, so due at 410 when viewed at t0+10
        _ = engine.tick(now: at(10))

        XCTAssertEqual(engine.timers(now: at(10)).map(\.id), [done.id, soon.id, paused.id, late.id])
        XCTAssertEqual(engine.timers(now: at(10)).first(where: { $0.id == soon.id })?.source, .agent)
    }

    func testSimultaneousFiringsAreReturnedInDueOrder() {
        let engine = TimerEngine()
        let second = engine.add(TimerSpec(name: "B", schedule: .countdown(20)), source: .user, now: t0)
        let first = engine.add(TimerSpec(name: "A", schedule: .countdown(10)), source: .user, now: t0)
        XCTAssertEqual(engine.tick(now: at(30)).map(\.id), [first.id, second.id])
    }

    func testMatchingByIdNameAndPrefix() throws {
        let engine = TimerEngine()
        let dash = engine.add(TimerSpec(name: "Check dashboards", schedule: .interval(300)), source: .user, now: t0)
        engine.add(TimerSpec(name: "Check status", schedule: .interval(300)), source: .user, now: t0)
        let rollback = engine.add(TimerSpec(name: "Rollback", schedule: .countdown(60)), source: .user, now: t0)

        XCTAssertEqual(try engine.timer(matching: "\(rollback.id)").id, rollback.id)
        XCTAssertEqual(try engine.timer(matching: "check DASHBOARDS").id, dash.id)
        XCTAssertEqual(try engine.timer(matching: "roll").id, rollback.id)
        XCTAssertThrowsError(try engine.timer(matching: "check"), "ambiguous prefix")
        XCTAssertThrowsError(try engine.timer(matching: "nope"))
    }
}
