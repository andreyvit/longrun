# AGENTS.md

**Longrun** — macOS app that keeps long-running CLI tools (dev servers, ssh
tunnels, ngrok) running in the background, with per-tool output view and
regexp-triggered notifications.

Docs (source of truth — update them when decisions are made):

- [_docs/spec.md](_docs/spec.md) — product spec: behavior, UI, open questions
- [_docs/arch.md](_docs/arch.md) — architecture: vanilla SwiftUI + @Observable
  models + plain Swift services; layout and rules

## Status

Brand new project, no code yet. Name: **Longrun** (directory may still be named
`rerun`).

## Conventions

- Platform: macOS 26+ only, native Swift, SwiftUI, not sandboxed (see arch.md).
- Keep the docs informal but current: when an open question in spec.md gets
  answered, move it into the spec body.
