Lens: unsandboxed app that spawns processes with the user's full environment.
The user is the only principal — web threats don't apply; local hygiene does.

- Config JSON can hold secrets in env overrides. Verify files are written with
  user-only permissions; env values never appear in logs, notifications, or
  error messages (names are fine, values are not).
- The cached login-shell environment can contain tokens — memory only, never
  persisted to disk. Flag any serialization of the resolved env.
- Launch-mode integrity: `exec` mode must never silently route through a
  shell; shell interpretation happens only in the explicit shell modes. Flag
  string-concatenated shell commands built from config fields in exec paths.
- No networking exists in MVP — any added network call is a finding requiring
  user approval, full stop.
- Hardened Runtime stays clean: any new entitlement must be justified in
  `_docs/arch.md` or rejected.
- Report: leak paths (logs/notifications/files), shell-injection-shaped
  construction, entitlement or networking creep.
