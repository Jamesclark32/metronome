import Foundation
import MetronomeCore

/// The UI's view of the timer engine: a snapshot refreshed on every change and every tick.
@MainActor
final class AppModel: ObservableObject {
    let engine: TimerEngine
    @Published private(set) var timers: [MetronomeTimer] = []
    @Published private(set) var now = Date()
    @Published var input = ""
    @Published var error: String?

    /// Called with the timers that fired, in firing order.
    var onFire: (([MetronomeTimer]) -> Void)?
    /// Called after every refresh, to update the menu-bar title.
    var onRefresh: (() -> Void)?

    init(engine: TimerEngine) {
        self.engine = engine
        // The control socket changes the engine off the main thread.
        engine.onChange { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func tick() {
        let fired = engine.tick()
        if !fired.isEmpty { onFire?(fired) }
        refresh()
    }

    func refresh() {
        now = Date()
        timers = engine.timers(now: now)
        onRefresh?()
    }

    func submit() {
        do {
            engine.add(try QuickEntry.parse(input), source: .user)
            input = ""
            error = nil
        } catch {
            // Keep the text so it can be fixed.
            self.error = error.localizedDescription
        }
    }

    func perform(_ action: (TimerEngine) throws -> Void) {
        do {
            try action(engine)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
