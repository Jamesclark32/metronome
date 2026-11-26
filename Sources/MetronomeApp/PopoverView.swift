import AppKit
import MetronomeCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    let shortcut: String
    @FocusState private var entryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(QuickEntry.example, text: $model.input)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($entryFocused)
                .onSubmit { model.submit() }
            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            if model.timers.isEmpty {
                Text("No timers. Type one above and press Return.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.timers) { timer in
                        TimerRow(timer: timer, now: model.now, model: model)
                    }
                }
            }

            Divider()
            HStack {
                Text("\(shortcut) opens Metronome · 90s, 1h 20m, @14:30, every, ~hero")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 400)
        .onAppear { entryFocused = true }
    }
}

struct TimerRow: View {
    let timer: MetronomeTimer
    let now: Date
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text((timer.source == .agent ? "🤖 " : "") + timer.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Text(remaining)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundColor(timer.state == .done ? .orange : timer.state == .paused ? .secondary : .primary)

            if timer.state == .done {
                iconButton("zzz", help: "Snooze 5 minutes") { try $0.snooze(id: timer.id) }
                iconButton("checkmark.circle", help: "Dismiss") { try $0.stop(id: timer.id) }
            } else {
                if case .deadline = timer.schedule {
                    // Deadlines are wall-clock times; they snooze but do not pause.
                } else if timer.state == .paused {
                    iconButton("play.fill", help: "Resume") { try $0.resume(id: timer.id) }
                } else {
                    iconButton("pause.fill", help: "Pause") { try $0.pause(id: timer.id) }
                }
                iconButton("zzz", help: "Snooze 5 minutes") { try $0.snooze(id: timer.id) }
                iconButton("xmark.circle", help: "Stop") { try $0.stop(id: timer.id) }
            }
        }
    }

    private var remaining: String {
        switch timer.state {
        case .done: return "done"
        case .paused: return "⏸ " + TimeFormat.clock(timer.remaining(at: now))
        case .running: return TimeFormat.clock(timer.remaining(at: now))
        }
    }

    private var detail: String {
        var parts: [String] = []
        switch timer.schedule {
        case .interval(let seconds): parts.append("every \(TimeFormat.duration(seconds))")
        case .countdown(let seconds): parts.append(TimeFormat.duration(seconds))
        case .deadline(let date): parts.append("at " + date.formatted(date: .omitted, time: .shortened))
        }
        parts.append(timer.sound.displayName)
        return parts.joined(separator: " · ")
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping (TimerEngine) throws -> Void) -> some View {
        Button { model.perform(action) } label: {
            Image(systemName: symbol).frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
