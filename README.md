# Metronome

A macOS menu-bar app for timely reminders during a busy incident. Start several overlapping
timers in a second: one-shot countdowns, repeating intervals, and wall-clock deadlines. Each
plays its own sound, and other apps and AI agents can add, list, and stop timers too.

Nothing persists: Metronome starts empty on every launch, and quitting clears all timers.

## Install

Metronome runs on **Apple silicon Macs with macOS 13 Ventura or later**. Intel Macs are not
supported.

1. Download `Metronome-<version>.zip` from the
   [latest release](https://github.com/Jamesclark32/metronome/releases/latest). Optionally,
   check it against the `.sha256` file next to it:

   ```sh
   shasum -a 256 -c Metronome-<version>.zip.sha256
   ```

2. Unzip it, move `Metronome.app` to `/Applications`, and clear the download quarantine:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Metronome.app
   open /Applications/Metronome.app
   ```

3. Optionally, put the `metronome` command on your `PATH`:

   ```sh
   sudo ln -sf /Applications/Metronome.app/Contents/Helpers/metronome /usr/local/bin/metronome
   ```

**About the signature:** releases are ad-hoc signed, not signed with an Apple Developer ID or
notarized. macOS therefore refuses to open a downloaded copy ("Apple could not verify…") until
you remove the quarantine attribute as in step 2. You can also click **Open Anyway** in System
Settings → Privacy & Security after the first attempt. The app has no network access and does
not need any special permissions. It only asks to post notifications.

To uninstall, quit Metronome and delete `/Applications/Metronome.app`, the `metronome` link if
you made one, and `~/Library/Application Support/Metronome`.

## Quick entry

Press **⌃⌥T** (Control-Option-T) anywhere, or click the menu-bar icon, then type one line and
press Return:

```
5m every Check dashboards ~ping
15m every Status update ~hero
@14:30 Vendor callback ~submarine
20m Rollback decision
```

| Part | Examples | Meaning |
| --- | --- | --- |
| Duration | `90s`, `5m`, `1h 20m`, `1h20m`, `1:30` (1 min 30 s), `1:30:00` | Fires once after this long |
| `every` | `5m every …` or `every 5m …` | Repeats until stopped |
| `@time` | `@14:30`, `@2:30pm`, `@9am` | Fires at the next time the clock shows this |
| `~sound` | `~glass`, `~ping`, `~submarine`, `~hero`, `~purr` | Leave it out to rotate, so concurrent timers sound different |
| Name | everything else | Shown in the menu bar and the notification |

The popover lists timers soonest first, with pause, snooze (5 minutes), stop, and dismiss
buttons. The menu bar shows the soonest timer's name and time left. Timers added by other apps
or agents are marked 🤖.

When several timers fire at once, their sounds play one after another, never over each other.
Each firing also posts a notification with the timer's name. Notifications are silent, so the
timer's own sound is the only one you hear. Allow notifications for Metronome when macOS asks,
or later in System Settings → Notifications → Metronome.

## Command line

The `metronome` command talks to the running app over a Unix socket that only your user can
open (`~/Library/Application Support/Metronome/control.sock`):

```sh
metronome add "5m every Check dashboards ~ping"
metronome list            # ID, name, time left, repeat, sound, state
metronome list --json     # adds next fire time, for scripts
metronome pause rollback  # by id, name, or unique name prefix
metronome resume rollback
metronome snooze "check dashboards" --for 10m
metronome stop 3
```

It exits with status 3 and says so when Metronome is not running.

## URL scheme

```sh
open "metronome://add?cmd=5m%20every%20Check%20dashboards"
```

The `cmd` value uses the same syntax as quick entry. If the command is invalid, the popover
opens with the text filled in and the error shown.

## MCP server for AI agents

`metronome mcp` is a stdio [MCP](https://modelcontextprotocol.io/) server that controls the
running app. Its tools:

- `add_timer`: a `command` string, or `name` plus `duration` (with `every`) or `at`, and an
  optional `sound`
- `list_timers`: each timer's name, time remaining, next fire time, repeat interval, sound,
  and state
- `stop_timer`, `pause_timer`, `resume_timer`, `snooze_timer`: by `timer` id or name

The examples below use the full path inside the app, because apps such as Claude Desktop do
not see your shell's `PATH`.

**Amp**: run

```sh
amp mcp add metronome -- /Applications/Metronome.app/Contents/Helpers/metronome mcp
```

or add this to `amp.mcpServers` in `~/.config/amp/settings.json`:

```json
"amp.mcpServers": {
  "metronome": {
    "command": "/Applications/Metronome.app/Contents/Helpers/metronome",
    "args": ["mcp"]
  }
}
```

**Claude Desktop**: add this to `~/Library/Application Support/Claude/claude_desktop_config.json`
and restart Claude:

```json
{
  "mcpServers": {
    "metronome": {
      "command": "/Applications/Metronome.app/Contents/Helpers/metronome",
      "args": ["mcp"]
    }
  }
}
```

## Building from source

Requires Xcode 16 or later (Swift 6) on macOS 13 or later.

```sh
swift build && swift test
scripts/package-app.sh    # ad-hoc signed build/Metronome.app
```

## Releasing

Push a version tag, such as `git tag v0.1.0 && git push origin v0.1.0`. The Release workflow
tests the build, packages `Metronome.app` with the version from the tag and the `metronome`
command inside the bundle, and attaches `Metronome-<version>.zip` and its `.sha256` to a new
GitHub release.

## License

MIT
