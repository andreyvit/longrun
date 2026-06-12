# Longrun — spec (informal)

A small macOS app that keeps long-running CLI tools alive so I don't have to keep a
Terminal tab open for each of them. Typical residents: `go run ...` (lifebase),
`ssh -MN` master connections, `ngrok`.

## Core idea

- **Sidebar (left):** list of *configurations*. Each configuration is one command
  to keep running. Sidebar shows a status indicator per item (running / stopped /
  exited with error).
- **Right pane:** for the selected configuration, two tabs:
  - **Terminal** — live output of the process. Embeds something terminal-like
    (ANSI colors, scrollback). Output-only; no input needed, at least initially.
  - **Settings** — how to run it: command, arguments, working directory,
    environment variables, launch mode (direct exec by default, or via the
    user's shell / bash — per-config dropdown), plus the behaviors below.

## Behaviors

- **Auto-run on app start** (per-configuration toggle). Launch the app, everything
  comes up — no starting each tool by hand.
- **Manual start/stop/restart** per configuration.
- **Output monitoring with notifications:** per-configuration list of regexps;
  when a line of output matches, post a macOS notification. (E.g. "tunnel
  disconnected", "panic:", "listening on".)
- Processes should die with the app (or at least never be orphaned) — run them in
  a process group / use a PTY and clean up on quit.

## Decisions

(Details in [arch.md](arch.md).)

- macOS 26+, not sandboxed, Developer ID + notarization (no App Store).
- Children run under a PTY; SwiftTerm renders output (read-only).
- Launch mode per config: direct exec (default, with cached login-shell env),
  or via the user's shell / bash as a one-liner.
- Storage: one JSON file per configuration in App Support; app preferences in
  NSUserDefaults.

## Open questions

- Restart policy: auto-restart on crash? With backoff? Per-config setting?
- Menu bar presence — show aggregate status / quick start-stop from a menu bar
  item? Run as a menu-bar-only app?
- Scrollback limits, and whether to persist logs to disk.
- Notification dedup/throttling (a regexp matching every line shouldn't spam).
- Input support in the terminal later (some tools ask y/n once in a while)?
