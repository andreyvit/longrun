Lens: small codebase where process state and lifecycle logic can easily get
re-derived in sidebar, menu bar, notifications, and the engine separately.

- Status derivation (running / stopped / exited-with-error) must exist once —
  in RunSession — and be consumed by sidebar dots, menu bar items, and
  notification triggers. Flag re-computation from raw fields.
- ANSI stripping and line assembly: one implementation, shared by
  OutputMatcher and anything else reading the PTY stream.
- Kill/teardown sequence (group SIGTERM → grace → SIGKILL) lives once in
  ProcessRunner; flag a second copy on the quit path or stop path.
- Config JSON encode/decode only in ConfigStore; flag ad-hoc Codable use of
  Configuration elsewhere.
- Lifecycle constants (5s grace, 1s restart delay, scrollback cap, cooldown)
  are named once — repeated literals are findings.
- Report: concrete consolidations with the file/symbol to merge into.
