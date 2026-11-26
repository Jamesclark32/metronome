import AppKit
import MetronomeCore
import os
import UserNotifications

private let log = Logger(subsystem: "com.jamesclark32.metronome", category: "alerts")

/// Plays the built-in macOS system sounds from /System/Library/Sounds; nothing is bundled.
@MainActor
final class SystemSoundPlayer: NSObject, SoundPlaying, NSSoundDelegate {
    private var current: NSSound?
    private var completion: (@MainActor () -> Void)?

    func play(_ sound: Sound, completion: @escaping @MainActor () -> Void) {
        let path = "/System/Library/Sounds/\(sound.displayName).aiff"
        guard let nsSound = NSSound(contentsOfFile: path, byReference: true) else {
            completion()
            return
        }
        nsSound.delegate = self
        log.info("sound start \(sound.displayName, privacy: .public)")
        current = nsSound
        self.completion = completion
        if !nsSound.play() { finish() }
    }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        MainActor.assumeIsolated { finish() }
    }

    private func finish() {
        let completion = self.completion
        self.completion = nil
        if let current { log.info("sound end \(current.duration, privacy: .public)s") }
        current = nil
        completion?()
    }
}

/// Posts a visible notification per fired timer. Notifications carry no sound;
/// the sound queue plays each timer's sound instead, one at a time.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// UNUserNotificationCenter needs an app bundle; it is unavailable under `swift run`.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()

    func start() {
        center?.delegate = self
        center?.requestAuthorization(options: [.alert]) { granted, error in
            log.info("notifications allowed: \(granted, privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
        }
    }

    func post(_ timers: [MetronomeTimer]) {
        for timer in timers {
            let content = UNMutableNotificationContent()
            content.title = (timer.source == .agent ? "🤖 " : "") + timer.name
            switch timer.schedule {
            case .interval(let seconds): content.body = "Every \(TimeFormat.duration(seconds)) · next in \(TimeFormat.duration(seconds))"
            case .countdown(let seconds): content.body = "\(TimeFormat.duration(seconds)) is up"
            case .deadline(let date): content.body = "It's \(date.formatted(date: .omitted, time: .shortened))"
            }
            content.sound = nil
            center?.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Show banners even while Metronome's popover is open, still without sound.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
