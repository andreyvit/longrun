Lens: this app's reason to exist is being simpler than tmux + launchd. Push
hard — simplicity is the headline review, not a nitpick pass.

- Measure every abstraction against the nine MVP bullets in `_docs/spec.md`.
  Protocols with one conformer, generic "engine" layers, config-migration
  frameworks for v1 JSON, coordinator/router layers for one window with two
  tabs — all findings.
- Restart policy is two cases (Always/Never). A Strategy pattern, policy
  registry, or plugin point for it is overdesign; mark richer policy machinery
  `[user approval needed]`.
- Prefer derived state over stored state: a status enum computed from the
  process handle beats three stored flags synchronized by hope.
- Large blocks that are hard to trust (the spawn path is the likely offender)
  should decompose along real seams — env, PTY, lifecycle — not into
  ceremony.
- Challenge the whole approach when a more direct design exists; say so
  explicitly and mark redesigns beyond the current task `[user approval
  needed]`.
- Report: the simpler alternative, concretely — what to delete, what replaces
  it, and what becomes easier to explain.
