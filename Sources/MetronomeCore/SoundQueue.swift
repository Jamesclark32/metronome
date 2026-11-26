/// Plays one sound and calls `completion` on the main actor when it ends.
@MainActor
public protocol SoundPlaying: AnyObject {
    func play(_ sound: Sound, completion: @escaping @MainActor () -> Void)
}

/// Plays timer sounds one after another, in the order they were queued, so
/// timers that fire together never play over each other.
@MainActor
public final class SoundQueue {
    private let player: SoundPlaying
    private var pending: [Sound] = []
    private var isPlaying = false

    public init(player: SoundPlaying) {
        self.player = player
    }

    public func enqueue(_ sounds: [Sound]) {
        pending += sounds
        playNext()
    }

    private func playNext() {
        guard !isPlaying, !pending.isEmpty else { return }
        isPlaying = true
        player.play(pending.removeFirst()) { [weak self] in
            self?.isPlaying = false
            self?.playNext()
        }
    }
}
