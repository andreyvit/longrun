# Longrun — architecture

Decision: **vanilla SwiftUI with `@Observable` model objects, plus plain Swift
service objects for the real logic.** No MVVM-per-view, no TCA, no Clean
Architecture layers. This matches Apple's modern samples (Food Truck, Backyard
Birds) and the post-`@Observable` community consensus for small apps.

Guiding principle: **Longrun's interesting code is not UI.** PTY management,
process lifecycles, output scanning — none of that should know SwiftUI exists.
SwiftUI views read observable models directly; views are already the
"view model" layer.

## Platform & distribution

- **macOS 26+ only.** Latest SwiftUI, no back-compat code.
- **Not sandboxed** — the app's job is running arbitrary user binaries with the
  user's real environment; the App Sandbox only permits bundled helpers and
  jails children's file access. Same app class as Terminal.app.
- Distribution: Developer ID signing + notarization, outside the App Store
  (direct download; Homebrew cask later). Hardened Runtime on. Sparkle 2 for
  updates when distribution starts — not before.

## Process execution

- **Always under a PTY** (child is session leader, PTY is its controlling
  terminal): tools see isatty() → colors, line buffering, TUIs (ngrok!) work.
  Update the PTY size (`TIOCSWINSZ`) when the terminal view resizes.
- **Launch mode is a per-config dropdown**, extensible list:
  - `exec` (**default**) — split command into argv, posix_spawn directly with
    the cached login-shell environment (see below). Safest: no profile side
    effects on every start.
  - `$SHELL -l -c` — the user's login shell; command field is a shell one-liner.
  - `bash -l -c` — fixed bash, for shell-syntax commands independent of the
    user's exotic shell.
  - (room for more modes later)
- **Cached environment resolution:** GUI apps get launchd's anemic PATH, so at
  startup resolve the user's login-shell env once (`$SHELL -l -c env` or
  equivalent) and cache it for `exec`-mode spawns. MUST run with a hard
  timeout and a fallback to a sane default env — users exist with interactive
  menus in their shell profiles.
- **Stop semantics:** SIGTERM to the *process group*, escalate to SIGKILL after
  a grace period. Group-kill catches intermediaries (`go run`'s child binary,
  wrapper shells). On app quit, tear down all groups (via
  `@NSApplicationDelegateAdaptor`) — never orphan children.
- Regexp monitoring runs on the PTY byte stream after ANSI-escape stripping,
  line by line — independent of any terminal view being on screen.

## Terminal emulation

[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (SPM). Use its AppKit
`TerminalView` as a **renderer only**, wrapped in `NSViewRepresentable`:
`ProcessRunner` owns the PTY and feeds bytes to the view; we do NOT use
`LocalProcessTerminalView` (processes must run and be monitored with no view
on screen). Read-only: keyboard input is simply never forwarded.

## Storage

- **One JSON file per configuration** in
  `~/Library/Application Support/Longrun/Configurations/<id>.json` —
  human-readable, hand-editable, diffable.
- App-level preferences go to `NSUserDefaults` as usual.

## Layout

```
Longrun/
  LongrunApp.swift          // @main, creates AppModel, injects via .environment()
  Models/
    AppModel.swift          // @Observable: configurations list, selection
    Configuration.swift     // Codable value type: command, cwd, env, autostart, regexps
    RunSession.swift        // @Observable, one per running config: status, output buffer
  Services/                 // plain Swift, no SwiftUI imports — unit-testable
    ConfigStore.swift       // one JSON file per config in App Support
    ProcessRunner.swift     // PTY spawn, process group, kill-on-quit
    EnvResolver.swift       // cached login-shell env capture (with timeout)
    OutputMatcher.swift     // regexp scanning → events
    Notifier.swift          // UserNotifications wrapper
  Views/
    Sidebar/                // config list + status dots
    Detail/                 // tab switcher; SettingsForm; TerminalPane
    TerminalPane.swift      // NSViewRepresentable wrapping SwiftTerm's TerminalView
```

## Rules

- State lives in a few `@Observable` classes (`AppModel`, `RunSession`),
  injected via `.environment()`. Views read them directly.
- No `@Published`, no Combine. Concurrency via `async/await`; process output
  flows as an `AsyncStream` of lines/chunks.
- Services are plain Swift types, constructor-injected into models at startup.
  No DI framework, no global singletons.
- `Configuration` is a `Codable` value type; persisted as human-readable JSON
  by `ConfigStore`.
- AppKit touches are quarantined: `@NSApplicationDelegateAdaptor` for
  child-process teardown on quit; `NSViewRepresentable` for the terminal view.
  `MenuBarExtra` (if/when we add menu bar presence) is pure SwiftUI.
- Tests target `Services/` and model logic (`OutputMatcher` especially).
  No UI tests for now.
- Escape hatch: if a screen ever grows genuinely gnarly presentation logic,
  an `@Observable` view model for that one screen is fine. Don't make it a
  pattern.

## References

- [Food Truck sample](https://github.com/apple/sample-food-truck),
  [Backyard Birds sample](https://github.com/apple/sample-backyard-birds) —
  the model/store shape this follows
- ["Stop using MVVM for SwiftUI"](https://developer.apple.com/forums/thread/699003)

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — now.
- [Sparkle 2](https://sparkle-project.org) — later, when distributing.
- Everything else is system frameworks (UserNotifications, SMAppService,
  OSLog) and stdlib (Codable JSON, Swift `Regex`). Plain `.xcodeproj`,
  Swift Testing for tests.
