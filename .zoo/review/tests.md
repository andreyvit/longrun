Lens: UI is untested in MVP, so the services must carry the proof — tests are
the spec for the process engine.

- OutputMatcher: table-driven Swift Testing cases covering ANSI stripping,
  lines split across chunk boundaries, multiple rules, and cooldown windows
  (with an injected clock — no real sleeps).
- ProcessRunner: real child processes (small scripts, `/bin/sleep`,
  `/bin/echo`) proving spawn, exit-code capture, group kill including
  grandchildren, and zero orphans after teardown. Read-until-deadline
  assertions, never single-read.
- Restart policy: distinct tests for unexpected exit (restarts), manual stop
  (does not), and quit during the pending 1s delay (cancels). These are the
  bugs this app will actually have.
- EnvResolver: fixture shell script, never the developer's real profile;
  timeout path and fallback env explicitly covered.
- ConfigStore: round-trip plus tolerance of hand-edited JSON (unknown keys,
  missing optionals) — hand-editability is a spec promise, so it needs a test.
- Report: missing scenarios by name, flaky timing patterns (real sleeps,
  single reads), and tests that mock what a real process would prove.
