# Planning — Longrun

- Longrun is a macOS 26+ SwiftUI app that keeps CLI tools (dev servers, ssh
  tunnels, ngrok) running. `_docs/spec.md` is the product source of truth;
  `_docs/arch.md` the technical one. Plans must cite them, and update them
  when a decision is made or scope changes.
- MVP scope is locked in spec.md ("MVP scope" section). Check new work against
  the Out list before planning it; Out-list items need a proposal, not a plan.
- Architecture boundaries (arch.md): `Services/` is plain Swift with no SwiftUI
  imports; `@Observable` models; SwiftTerm is a renderer only — the process
  engine must run headless (monitoring, restarts, notifications with no view).
- High-risk areas to plan explicitly, not hand-wave: process group teardown
  (no orphans, ever), restart policy vs manual stop, crash loops at the fixed
  1s restart delay, login-shell env capture (hard timeout + fallback), ANSI
  stripping before regexp matching, activation-policy switching.
- Single-user desktop app: no backend, no network services, no auth. Plans
  introducing networking are scope creep.
- Greenfield: no Xcode project exists yet (June 2026). Verify actual project
  state before planning against assumed files or schemes.
