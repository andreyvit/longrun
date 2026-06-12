# UI verification — Longrun (native macOS app, no browser)

- There is no web UI. "Browser verification" means: build, launch the real
  app, exercise it, capture evidence. Computer-use tooling (screenshot +
  click) or `screencapture` CLI for window captures.
- Launch command: TBD until the Xcode project exists — record the
  `xcodebuild build` + `open` (or derived-data path) invocation here once
  scaffolded.
- Verify with real processes, not fakes: a script that prints colors and
  progress (`\r`), one that sleeps forever (test stop/kill), one that exits
  nonzero (test crash status + restart policy + exit notification), and
  something TUI-ish (ngrok-style cursor addressing) for the terminal pane.
- First run on a machine: grant Notification Center permission manually when
  prompted, or notification scenarios will silently no-op.
- Menu-bar and Dock-icon toggle scenarios change activation policy at runtime
  — verify both directions, plus window-close-keeps-running and reopen-shows-
  window (relaunch the app while it's running).
- Kill-cleanliness check after any process-engine change: quit the app, then
  `ps` for orphaned children (pgrep the test scripts) — zero survivors.
