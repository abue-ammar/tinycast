# Natural Commands improvement gates

Base: `origin/main` at `43b9b34` (2026-09-24). Scope: automatic TypeSafe fallback for an empty
local search, selectable launcher choices, stale request cancellation, and bounded command IDs.

- [x] A local search result, short query, disabled setting, or missing key prevents the TypeSafe request.
- [x] A response publishes up to three launcher choices and executes no command. Selecting one opens
  the existing confirmation; cancel keeps the choices available.
- [x] Pending results cannot present stale choices after the query, palette, feature switch, key, or
  visible command catalog changes. A confirmed command is checked again before execution.
- [x] Every built-in window command has a fixed description; the request remains limited to visible
  built-in command IDs and `no_match`.
- [x] A 23-case English and Indonesian corpus and a names-only comparison runner are available.
- [ ] Live TypeSafe accuracy and confidence cutoff are calibrated against the corpus. The evaluator
  needs the user's Keychain access approval; the current 0.70 cutoff remains provisional against
  the pinned `jev-1.13.0` model.
- [x] `./Scripts/run-tests.sh natural-command-test` passes after this behavior change.
- [x] `TINYCAST_TEST_JOBS=1 ./Scripts/run-tests.sh` passes all 78 harnesses after this behavior change.
- [x] `./Scripts/lint.sh` and a Debug build pass after this behavior change.
- [ ] `./Scripts/run-tests.sh` passes at the default parallelism. The extension helper's timed
  settlement failed under full CPU load; it passed in isolation and in the serial suite. The
  installed-AI concurrency harness also failed with two workers and passed in isolation and serially.
