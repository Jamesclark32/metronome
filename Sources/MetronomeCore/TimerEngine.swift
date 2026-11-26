import Foundation

/// The set of running timers. Lives only in memory: a new engine is empty, so
/// nothing survives a quit or crash.
///
/// Thread-safe, because the control socket calls it from its own thread while
/// the UI calls it from the main thread.
public final class TimerEngine: @unchecked Sendable {
    public static let defaultSnooze: TimeInterval = 5 * 60

    private let lock = NSLock()
    private var items: [MetronomeTimer] = []
    private var nextID = 1
    private var changeHandler: (@Sendable () -> Void)?

    public init() {}

    /// Called after every change, on the thread that made it.
    public func onChange(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { changeHandler = handler }
    }

    @discardableResult
    public func add(_ spec: TimerSpec, source: TimerSource, now: Date = Date()) -> MetronomeTimer {
        let timer = mutate { () -> MetronomeTimer in
            let due: Date
            switch spec.schedule {
            case .countdown(let seconds), .interval(let seconds): due = now.addingTimeInterval(seconds)
            case .deadline(let date): due = date
            }
            let timer = MetronomeTimer(
                id: nextID, name: spec.name, schedule: spec.schedule,
                sound: spec.sound ?? .glass, source: source,
                state: .running, dueDate: due, pausedRemaining: nil)
            nextID += 1
            items.append(timer)
            return timer
        }
        return timer
    }

    /// All timers, soonest due first; done timers come before running ones.
    public func timers(now: Date = Date()) -> [MetronomeTimer] {
        lock.withLock { sorted(items, now: now) }
    }

    /// Finds a timer by id, then by exact name, then by unique name prefix, ignoring case.
    public func timer(matching target: String) throws -> MetronomeTimer {
        let all = lock.withLock { items }
        let query = target.trimmingCharacters(in: .whitespaces)
        if let id = Int(query), let match = all.first(where: { $0.id == id }) { return match }
        for matches in [
            all.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame },
            all.filter { $0.name.lowercased().hasPrefix(query.lowercased()) },
        ] {
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                let names = matches.map { "\($0.id) \($0.name)" }.joined(separator: ", ")
                throw MetronomeError("\"\(target)\" matches several timers (\(names)); use an id.")
            }
        }
        throw MetronomeError("No timer matches \"\(target)\".")
    }

    @discardableResult
    public func pause(id: Int, now: Date = Date()) throws -> MetronomeTimer {
        try update(id) { timer in
            if case .deadline = timer.schedule {
                throw MetronomeError("\(timer.name) is a deadline and cannot be paused; snooze or stop it.")
            }
            guard timer.state == .running else { throw MetronomeError("\(timer.name) is not running.") }
            timer.pausedRemaining = timer.remaining(at: now)
            timer.state = .paused
        }
    }

    @discardableResult
    public func resume(id: Int, now: Date = Date()) throws -> MetronomeTimer {
        try update(id) { timer in
            guard timer.state == .paused else { throw MetronomeError("\(timer.name) is not paused.") }
            timer.dueDate = now.addingTimeInterval(timer.pausedRemaining ?? 0)
            timer.pausedRemaining = nil
            timer.state = .running
        }
    }

    /// Puts off the next firing. A done timer starts running again and fires after `seconds`.
    @discardableResult
    public func snooze(id: Int, by seconds: TimeInterval = defaultSnooze, now: Date = Date()) throws -> MetronomeTimer {
        try update(id) { timer in
            switch timer.state {
            case .running: timer.dueDate = timer.dueDate.addingTimeInterval(seconds)
            case .paused: timer.pausedRemaining = (timer.pausedRemaining ?? 0) + seconds
            case .done:
                timer.dueDate = now.addingTimeInterval(seconds)
                timer.state = .running
            }
        }
    }

    /// Removes a timer: stops a running one or dismisses a done one.
    @discardableResult
    public func stop(id: Int) throws -> MetronomeTimer {
        try mutate {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw MetronomeError("No timer with id \(id).")
            }
            return items.remove(at: index)
        }
    }

    /// Fires every running timer that is due and returns them in firing order.
    /// One-shot timers become done; repeating timers move to their next future
    /// time and fire once even if several periods passed while the Mac slept.
    public func tick(now: Date = Date()) -> [MetronomeTimer] {
        let fired = lock.withLock { () -> [MetronomeTimer] in
            var fired: [MetronomeTimer] = []
            for index in items.indices where items[index].state == .running && items[index].dueDate <= now {
                fired.append(items[index])
                switch items[index].schedule {
                case .interval(let seconds):
                    var due = items[index].dueDate
                    while due <= now { due = due.addingTimeInterval(seconds) }
                    items[index].dueDate = due
                case .countdown, .deadline:
                    items[index].state = .done
                }
            }
            return fired.sorted { ($0.dueDate, $0.id) < ($1.dueDate, $1.id) }
        }
        if !fired.isEmpty { notifyChange() }
        return fired
    }

    // MARK: - Helpers

    private func update(_ id: Int, _ change: (inout MetronomeTimer) throws -> Void) throws -> MetronomeTimer {
        try mutate {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw MetronomeError("No timer with id \(id).")
            }
            try change(&items[index])
            return items[index]
        }
    }

    /// Runs a change under the lock, then tells the change handler outside it.
    private func mutate<T>(_ body: () throws -> T) rethrows -> T {
        let result = try lock.withLock(body)
        notifyChange()
        return result
    }

    private func notifyChange() {
        lock.withLock { changeHandler }?()
    }

    private func sorted(_ timers: [MetronomeTimer], now: Date) -> [MetronomeTimer] {
        timers.sorted { ($0.sortKey(at: now), $0.id) < ($1.sortKey(at: now), $1.id) }
    }
}
