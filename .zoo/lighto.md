# Lighto overrides — Longrun

- Ticket tooling: none. Tasks originate in chat; task files under `.spec/`,
  research under `.tasks/` (Lighto defaults).
- Tier-0 scripted check: none yet — no Xcode project exists. The scaffold
  task must record the `xcodebuild build` + test command here once the
  project and scheme exist.
- `.gitignore` does not exist yet; the first task must create it and ignore
  `.spec/`, `.tasks/`, and Xcode noise (`xcuserdata/`, `DerivedData/`).
