Lens: can failures be noticed and diagnosed in an app that deliberately runs
invisible (menu-bar-only or fully hidden) and babysits other programs?

- Every lifecycle transition (spawn, exit + code/signal, restart, kill
  escalation) must hit OSLog with config name and pid. No `print()`. Flag
  swallowed errors around `posix_spawn`, PTY ioctls, and signal calls.
- Crash loops: restart=Always with fixed 1s delay can spin at 1Hz. Verify exit
  reason and restart count are at least logged, ideally visible in status UI.
- The unexpected-exit notification path must work with zero windows — that is
  its entire job; flag any dependency on a view or window existing.
- When env capture times out and the fallback env is used, that fact must be
  observable (log minimum) — otherwise PATH bugs are undiagnosable.
- Teardown: quit must log group kills. An orphaned child is the unrecoverable
  failure for this app — flag any spawn path not enrolled in quit teardown.
- Report: missing logs at transitions, error paths that vanish, process states
  the sidebar/menu cannot represent.
