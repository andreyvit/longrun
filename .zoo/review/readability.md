Lens: solo-maintainer app revisited at long intervals — lifecycle code must
read as the state machine it is, months later, cold.

- Process state should be one explicit enum (e.g. idle / running /
  stopping / restartPending / exited(status)), not scattered booleans
  (`isRunning`, `wasKilled`, `shouldRestart`) that imply impossible
  combinations.
- Async plumbing: for each AsyncStream/Task, it must be obvious who consumes
  it, who cancels it, and when it ends. Flag tangled Task lifetimes and
  fire-and-forget tasks holding strong references.
- Vocabulary from the spec: "configuration", "run session", "launch mode" —
  flag synonym soup (job, task, runner, item) that forces mental mapping.
- Spawn path altitude: argv preparation, PTY ioctls, and model updates in one
  function is mixed abstraction — flag it.
- Comments earn their place only on constraints code can't show (signal
  semantics, PTY quirks, why the env timeout exists). Narration is a finding.
- Report: specific renames, enum consolidations, and function splits.
