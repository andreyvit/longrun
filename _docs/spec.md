# Longrun — spec (informal)

A small macOS app that keeps long-running CLI tools alive so I don't have to keep a
Terminal tab open for each of them. Typical residents: `go run ...` (lifebase),
`ssh -MN` master connections, `ngrok`.

## Core idea

- **Sidebar (left):** list of *configurations*. Each configuration is one command
  to keep running. Sidebar shows a status indicator per item (running / stopped /
  exited with error). Add, rename, delete, drag to reorder.
- **Right pane:** for the selected configuration, two tabs:
  - **Terminal** — live output of the process. Embeds SwiftTerm (ANSI colors,
    scrollback). Output-only; no input needed, at least initially.
  - **Settings** — how to run it: command, working directory, environment
    variables, launch mode (direct exec by default, or via the user's shell /
    bash — per-config dropdown), auto-start, restart policy, notification rules.
- **Menu bar icon** (on by default): a menu listing each configuration with its
  status, plus Show Window, About, and Quit.
- **Closing the window does not quit** — processes keep running in the
  background; that's the point. Quit (menu bar or Cmd-Q) tears everything down.

## Behaviors

- **Auto-run on app start** (per-configuration toggle). Launch the app, everything
  comes up — no starting each tool by hand.
- **Manual start/stop/restart** per configuration.
- **Restart policy** per configuration: dropdown, **Always** (default) or
  **Never**; more policies later. Always = relaunch 1 second after any exit
  (regardless of exit code). Manual stop never triggers a restart.
- **Output monitoring with notifications:** per-configuration list of regexps,
  matched against ANSI-stripped output lines; on match, post a macOS
  notification showing the matched line. Simple per-rule cooldown so a
  match-every-line regexp doesn't spam.
- **Exited-unexpectedly notification:** built-in, per-configuration toggle,
  default ON. A dead tunnel is the #1 event this app exists to catch.
- **Launch at login** checkbox (SMAppService).
- **App-level appearance toggles:** "show Dock icon" and "show menu bar icon"
  checkboxes; any combination is allowed. In menu-bar-only mode the app does
  not show the window on launch — it appears when invoked from the menu. With
  both off the app runs fully invisible; launching it again (Finder/Spotlight)
  brings up the window.
- Processes die with the app, never orphaned — process groups, cleanup on quit.

## MVP scope

In:

1. Sidebar + config CRUD (add, rename, delete, reorder) with status dots.
2. Settings tab: name, command, launch mode, working dir, env overrides,
   auto-start, restart policy, notification rules.
3. Process engine: PTY spawn, cached login-shell env (timeout + fallback),
   group SIGTERM → 5s grace → SIGKILL (fixed), teardown on quit, PTY resize.
4. Terminal tab: SwiftTerm read-only, capped scrollback (~10k lines),
   stick-to-bottom unless scrolled up, selection + copy.
5. Notifications: regexp rules + built-in unexpected-exit, per-rule cooldown.
6. Restart policy: Always (default, 1s delay) / Never.
7. Menu bar icon with per-config status menu; Show Window / About / Quit.
8. Dock icon + menu bar icon toggles; background running; launch at login.
9. Persistence: JSON per config in App Support; UI state in UserDefaults.

Out (later):

- Terminal input; scrollback search; log persistence/export.
- CLI companion, URL scheme, anything remote.
- iCloud sync; import/export UI (configs are JSON files — use Finder).
- Start-order dependencies between configurations.
- Per-config signal/grace-period tuning; restart backoff configuration
  (fixed 1s delay in MVP — revisit if crash loops get annoying).
- Sparkle, signing/notarization pipeline, real app icon, localization,
  onboarding.

## Decisions

(Details in [arch.md](arch.md).)

- macOS 26+, not sandboxed, Developer ID + notarization (no App Store).
- Children run under a PTY; SwiftTerm renders output (read-only).
- Launch mode per config: direct exec (default, with cached login-shell env),
  or via the user's shell / bash as a one-liner.
- Storage: one JSON file per configuration in App Support; app preferences in
  NSUserDefaults.
- Restart policy starts minimal: Always (1s fixed delay) / Never; richer
  policies (on-crash-only, backoff) deliberately deferred.
- Scrollback capped at ~10k lines, not persisted.
- Dock-icon toggle implemented via activation policy switching
  (.regular/.accessory); window close keeps the app alive.
