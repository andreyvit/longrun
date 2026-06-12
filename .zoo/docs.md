# Docs — Longrun

- Durable docs live in `_docs/`: `spec.md` (product, informal tone) and
  `arch.md` (architecture + decisions). When a decision lands or scope
  changes, update them in the same task — answered questions move into the
  body, they don't linger as "open".
- Agent instructions: `AGENTS.md` (`CLAUDE.md` just points at it). Keep its
  platform/conventions lines current.
- `README.md` is the public face: short pitch + doc links. Keep the status
  line honest while the app isn't usable yet.
- Terminology: a "configuration" is one command to keep running — not a
  task, job, or service. The per-process runtime object is a "run session".
- No docs site, no doc validation commands.
