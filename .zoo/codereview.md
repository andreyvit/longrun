# Code review — Longrun

- Highest-risk area is process lifecycle. Verify: group kill catches
  intermediaries (`go run` children, wrapper shells); teardown runs on every
  quit path; manual stop never triggers the restart policy; quit during the
  1s restart delay cancels the pending restart; no spawn path escapes
  teardown bookkeeping.
- Env capture must enforce a hard timeout with a sane fallback env and never
  block app startup — interactive shell profiles exist in the wild.
- Regexp monitoring runs on ANSI-stripped lines and must work with no
  terminal view on screen. Flag any matcher wiring that hangs off the view.
- Memory: scrollback capped (~10k lines); look for unbounded buffers in
  RunSession or the output stream plumbing.
- Notifications: per-rule cooldown actually throttles; unexpected-exit
  notification fires on crashes only — not manual stop, not app quit.
- Boundaries: `Services/` has no SwiftUI import; SwiftTerm is fed bytes, never
  owns the process.
- macOS 26+: `if #available` and similar back-compat is dead weight — flag it.
