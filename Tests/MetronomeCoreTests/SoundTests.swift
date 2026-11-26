import XCTest
@testable import MetronomeCore

@MainActor
final class FakePlayer: SoundPlaying {
    var started: [Sound] = []
    var finishCurrent: (@MainActor () -> Void)?

    func play(_ sound: Sound, completion: @escaping @MainActor () -> Void) {
        XCTAssertNil(finishCurrent, "a sound started while another was playing")
        started.append(sound)
        finishCurrent = completion
    }

    func finish() {
        let completion = finishCurrent
        finishCurrent = nil
        completion?()
    }
}

@MainActor
final class SoundQueueTests: XCTestCase {
    func testSoundsPlayOneAfterAnotherInFiringOrder() {
        let player = FakePlayer()
        let queue = SoundQueue(player: player)

        queue.enqueue([.hero, .glass, .hero])
        XCTAssertEqual(player.started, [.hero], "only the first plays until it ends")

        queue.enqueue([.purr])  // fired while the first is still playing
        XCTAssertEqual(player.started, [.hero])

        for _ in 0..<4 { player.finish() }
        XCTAssertEqual(player.started, [.hero, .glass, .hero, .purr])
    }

    func testQueueRestartsAfterGoingIdle() {
        let player = FakePlayer()
        let queue = SoundQueue(player: player)
        queue.enqueue([.ping])
        player.finish()
        queue.enqueue([.submarine])
        XCTAssertEqual(player.started, [.ping, .submarine])
    }
}

final class SoundRotationTests: XCTestCase {
    func add(_ engine: TimerEngine, sound: Sound? = nil) -> MetronomeTimer {
        engine.add(TimerSpec(name: "T", schedule: .interval(60), sound: sound), source: .user)
    }

    func testUnspecifiedSoundsRotateThroughAllFive() {
        let engine = TimerEngine()
        XCTAssertEqual((0..<5).map { _ in add(engine).sound }, [.glass, .ping, .submarine, .hero, .purr])
        XCTAssertEqual(add(engine).sound, .glass, "wraps once all five are in use")
    }

    func testRotationSkipsSoundsAlreadyInUse() throws {
        let engine = TimerEngine()
        _ = add(engine, sound: .glass)
        _ = add(engine, sound: .submarine)
        XCTAssertEqual(add(engine).sound, .ping)
        XCTAssertEqual(add(engine).sound, .hero)

        // A sound becomes free again when its timer stops.
        let glass = try engine.timer(matching: "1")
        try engine.stop(id: glass.id)
        XCTAssertEqual(add(engine).sound, .purr)
        XCTAssertEqual(add(engine).sound, .glass)
    }

    func testSoundNames() {
        XCTAssertEqual(Sound(name: "Submarine"), .submarine)
        XCTAssertEqual(Sound.hero.displayName, "Hero")
        XCTAssertNil(Sound(name: "Basso"))
    }
}
