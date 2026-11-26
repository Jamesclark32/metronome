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
    private var controlServer: ControlServer?

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
        startControlServer()
        model.refresh()
    }

    /// Lets the `metronome` CLI and MCP server add, list, and change timers.
    private func startControlServer() {
        let service = ControlService(engine: model.engine)
        let server = ControlServer { service.handle(json: $0) }
        do {
            try server.start()
            controlServer = server
        } catch {
            model.error = "The metronome CLI can't connect: \(error.localizedDescription)"
        }
    }

    /// metronome://add?cmd=… adds an agent timer. A bad command opens the popover
    /// with the text filled in and the error shown, so it can be fixed.
    func application(_ application: NSApplication, open urls: [URL]) {
        let service = ControlService(engine: model.engine)
        for url in urls {
            do {
                let request = try URLCommand.request(from: url)
                let response = service.handle(request)
                if !response.ok {
                    model.input = request.text ?? ""
                    throw MetronomeError(response.error ?? "The URL command failed.")
                }
            } catch {
                model.error = error.localizedDescription
                showPopover()
            }
        }
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
