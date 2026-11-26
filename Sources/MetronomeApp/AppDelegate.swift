import AppKit
import Carbon.HIToolbox
import MetronomeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shortcut = "⌃⌥T"

    // A fresh, empty engine on every launch: nothing is restored.
    let model = AppModel(engine: TimerEngine())
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: HotKey?
    private var ticker: Timer?
    private let sounds = SoundQueue(player: SystemSoundPlayer())
    private let notifier = Notifier()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "metronome", accessibilityDescription: "Metronome")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient

        model.onRefresh = { [weak self] in self?.updateTitle() }
        notifier.start()
        model.onFire = { [weak self] fired in
            self?.sounds.enqueue(fired.map(\.sound))
            self?.notifier.post(fired)
        }
        hotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in
            self?.showPopover()
        }

        let ticker = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.model.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)  // keep ticking while the popover tracks events
        self.ticker = ticker
        // Fire anything that came due while the Mac slept.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick() }
        }
        model.refresh()
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
            return
        }
        // A new view each time so the entry field takes focus again.
        let host = NSHostingController(rootView: PopoverView(model: model, shortcut: Self.shortcut))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Shows the soonest timer's name and time left next to the icon.
    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        guard let next = model.timers.first else {
            button.title = ""
            return
        }
        var name = (next.source == .agent ? "🤖 " : "") + next.name
        if name.count > 24 { name = String(name.prefix(23)) + "…" }
        let time: String
        switch next.state {
        case .done: time = "done"
        case .paused: time = "⏸ " + TimeFormat.clock(next.remaining(at: model.now))
        case .running: time = TimeFormat.clock(next.remaining(at: model.now))
        }
        let title = " \(name) \(time)"
        if button.title != title { button.title = title }
    }
}
