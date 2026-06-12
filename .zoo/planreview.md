# Plan review — Longrun

- Enforce `_docs/arch.md` boundaries: no SwiftUI in `Services/`, SwiftTerm as
  renderer only (no `LocalProcessTerminalView`), AppKit only in sanctioned
  spots (delegate adaptor, terminal NSViewRepresentable, activation policy).
- Any plan touching process lifecycle must spell out signal semantics
  (group SIGTERM → 5s grace → SIGKILL), quit teardown, and how restart policy
  interacts with manual stop and with quit-during-restart-delay.
- Reject silent scope creep into spec.md's "Out (later)" list — route to a
  proposal per `.zoo/proposals.md`.
- macOS 26+ only: availability checks and back-compat shims in a plan are a
  smell, not diligence.
- Persistence plans must keep one human-readable JSON file per configuration;
  hand-edited files must not be destroyed by load/save cycles.
- New dependencies beyond SwiftTerm (and later Sparkle) require explicit user
  approval in the plan.
