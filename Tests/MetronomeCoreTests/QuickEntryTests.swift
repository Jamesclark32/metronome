import XCTest
@testable import MetronomeCore

final class QuickEntryTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    /// Thursday 2026-11-26 10:15:00 in Chicago.
    lazy var now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10, minute: 15))!

    func parse(_ text: String) throws -> TimerSpec {
        try QuickEntry.parse(text, now: now, calendar: calendar)
    }

    func clock(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 26 + dayOffset, hour: hour, minute: minute))!
    }

    func testExamplesFromTheIssue() throws {
        XCTAssertEqual(try parse("5m every Check dashboards ~ping"),
                       TimerSpec(name: "Check dashboards", schedule: .interval(300), sound: .ping))
        XCTAssertEqual(try parse("15m every Status update ~hero"),
                       TimerSpec(name: "Status update", schedule: .interval(900), sound: .hero))
        XCTAssertEqual(try parse("@14:30 Vendor callback ~submarine"),
                       TimerSpec(name: "Vendor callback", schedule: .deadline(clock(14, 30)), sound: .submarine))
        XCTAssertEqual(try parse("20m Rollback decision"),
                       TimerSpec(name: "Rollback decision", schedule: .countdown(1_200)))
    }

    func testDurationForms() throws {
        XCTAssertEqual(try parse("90s Tea").schedule, .countdown(90))
        XCTAssertEqual(try parse("1h 20m Tea").schedule, .countdown(4_800))
        XCTAssertEqual(try parse("1h20m Tea").schedule, .countdown(4_800))
        XCTAssertEqual(try parse("1:30 Tea").schedule, .countdown(90), "m:ss")
        XCTAssertEqual(try parse("1:30:00 Tea").schedule, .countdown(5_400), "h:mm:ss")
        XCTAssertEqual(try parse("every 5m Tea").schedule, .interval(300), "every before the duration")
    }

    func testNameKeepsLaterNumbersAndKeywords() throws {
        let spec = try parse("10m Check every 5m job on 3 hosts ~Glass")
        XCTAssertEqual(spec.name, "Check every 5m job on 3 hosts")
        XCTAssertEqual(spec.schedule, .countdown(600))
        XCTAssertEqual(spec.sound, .glass)
    }

    func testMissingNameGetsDefault() throws {
        XCTAssertEqual(try parse("5m").name, "Timer")
    }

    func testDeadlineTimes() throws {
        XCTAssertEqual(try parse("@2:30pm Call").schedule, .deadline(clock(14, 30)))
        XCTAssertEqual(try parse("@ 11am Call").schedule, .deadline(clock(11, 0)))
        XCTAssertEqual(try parse("@12am Call").schedule, .deadline(clock(0, 0, dayOffset: 1)))
        // 10:15 has passed today's 9:00 and is exactly now, so both mean tomorrow.
        XCTAssertEqual(try parse("@9:00 Standup").schedule, .deadline(clock(9, 0, dayOffset: 1)))
        XCTAssertEqual(try parse("@10:15 Now").schedule, .deadline(clock(10, 15, dayOffset: 1)))
    }

    func testInvalidInputs() {
        for text in [
            "", "   ", "Check dashboards", "5x Tea", "0m Tea", "5m ~bell Tea",
            "@25:00 Late", "@14:3 Odd", "@13pm Odd", "@9 Ambiguous", "@14:30 every Call",
            "5m @14:30 Both", "every Tea", "1:75 Tea", "5m5m Tea",
        ] {
            XCTAssertThrowsError(try parse(text), "\"\(text)\" should be rejected")
        }
    }

    func testErrorMessagesExplainTheFix() {
        XCTAssertThrowsError(try parse("5m ~bell Tea")) { error in
            XCTAssertTrue(error.localizedDescription.contains("glass, ping, submarine, hero, purr"))
        }
    }

    func testTimeFormat() {
        XCTAssertEqual(TimeFormat.clock(299.2), "5:00")
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(3_723), "1:02:03")
        XCTAssertEqual(TimeFormat.duration(4_800), "1h 20m")
        XCTAssertEqual(TimeFormat.duration(90), "1m 30s")
    }
}
