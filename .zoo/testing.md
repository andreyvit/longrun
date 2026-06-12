# Testing — Longrun

- Swift Testing (not XCTest) for unit tests. Targets: `Services/` and model
  logic — `OutputMatcher`, `EnvResolver`, `ConfigStore`, restart-policy
  decisions. No UI tests in MVP; UI is verified by running the app
  (see browser.md).
- Process-engine tests use real tiny child processes (`/bin/echo`,
  `/bin/sleep`, small shell scripts) instead of mocks — PTY behavior is the
  product; don't fake what a real process proves cheaply.
- Determinism rules: tests must never depend on the developer's login shell or
  profile — `EnvResolver` tests use a fixture shell/script. Inject clocks or
  delays for restart-delay and cooldown logic; no real-time sleeps to assert
  timing.
- Watch for PTY buffering races in assertions: read until expected content
  with a deadline, never assert on a single read.
- Test command: TBD — no Xcode project yet. Once scaffolded, record the
  `xcodebuild test` invocation (scheme, destination) here.
