Lens: `_docs/arch.md` draws hard boundaries; this repo's modularity question
is whether the process engine truly runs headless.

- `Services/` imports no SwiftUI; AppKit appears only in the delegate adaptor,
  the terminal NSViewRepresentable, and activation-policy switching. Grep it.
- ProcessRunner + OutputMatcher + Notifier must be fully operable with zero
  views: monitoring, restarts, and notifications for a config whose window/tab
  was never opened. Flag any view-instantiation dependency.
- State ownership: AppModel owns the config list and selection; each
  RunSession owns one process's runtime state; views own nothing durable.
  Flag view-local state that models would need to know.
- TerminalPane receives bytes and renders — flag process control, matching,
  or persistence leaking into the view layer.
- Emergent behavior that must be explicit code (and tested), not coincidence:
  restart policy × manual stop, quit during restart delay, env cache used
  after the user changed their shell profile.
- Report: boundary violations with file:line, and the owning type a moved
  responsibility should land in.
