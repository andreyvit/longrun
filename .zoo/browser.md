# UI verification — Longrun (native macOS app, no browser)

- There is no web UI. "Browser verification" means: build, launch the real
  app, exercise it, capture evidence. Computer-use tooling (screenshot +
  click) or `screencapture` CLI for window captures.
- Build then launch: `xcodebuild ... build` (see `.zoo/lighto.md`), then
  `open .build/dd/Build/Products/Debug/Longrun.app`. Use `open` (not the
  binary directly) so reopen events, TCC attribution, and the real GUI launch
  environment behave correctly.
- Computer-use access: the app runs from the build dir, not `/Applications`,
  so `request_access` by display name fails — use the **bundle id**
  `com.tarantsov.Longrun`.
- Quit between runs: `osascript -e 'tell application id "com.tarantsov.Longrun"
  to quit'` (runs the real teardown path), `pkill -x Longrun` only as a
  fallback (SIGTERM skips AppKit teardown → would orphan PTY children).
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
