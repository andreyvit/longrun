# Coding — Longrun

- Swift + SwiftUI, `@Observable` macro. No Combine, no `@Published`, no
  `ObservableObject`. Concurrency via async/await; process output flows as
  `AsyncStream`.
- Layout per `_docs/arch.md`: `Models/`, `Services/` (no SwiftUI imports),
  `Views/`. AppKit only in: `@NSApplicationDelegateAdaptor`, the SwiftTerm
  `NSViewRepresentable` wrapper, activation-policy switching.
- Constructor injection at app startup; no DI frameworks, no service
  singletons.
- `Configuration` is a Codable value type; one JSON file per configuration in
  `~/Library/Application Support/Longrun/Configurations/`; app preferences in
  `UserDefaults`.
- Dependencies: SwiftTerm only (SPM). Anything new needs user approval first.
- Named constants for lifecycle numbers (5s kill grace, 1s restart delay,
  ~10k scrollback cap, notification cooldown) — one definition each.
- Comments state constraints the code can't show (signal semantics, PTY
  quirks, timeout rationale) — nothing else.
