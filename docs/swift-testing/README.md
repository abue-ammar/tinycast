# Swift Testing migration: the brief

Temporary. This folder and the pointer to it in `AGENTS.md` are deleted in the migration's last
commit. Every session, Claude Code or Codex, works from this file and [status.md](status.md) alone:
nothing carries over between sessions except what is written here, in `status.md` and in git.

## Goal

Replace the standalone `swiftc` harnesses in `Tests/` with an Xcode unit-test target, `TinycastTests`,
written in Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`): Apple's own pattern for an app.
The suites show up in Xcode's test navigator, run with `xcodebuild test`, and, for whoever installs
the SweetPad editor extension, in VS Code's Testing view. Sessions always test through
`./Scripts/run-tests.sh`, never through an editor.

The permanent docs (`AGENTS.md`, `docs/testing.md`, `docs/development.md`, `docs/architecture.md`,
`docs/standards.md`) already describe the **end state**. Until the migration ends, `status.md` is
what says which parts of that end state exist yet.

## Scope

| Group    | What it is                                                         | How it moves                                                 |
| -------- | ------------------------------------------------------------------ | ------------------------------------------------------------ |
| `pilot`  | 4 harnesses picked to prove the target, host, runner and fixtures  | converted by hand while the infrastructure is built          |
| `plain`  | harnesses that compile shipped sources and nothing of their own    | converted mechanically, following `docs/testing.md`          |
| `stub`   | harnesses that declare a stand-in for a real app type              | the stand-in clashes with the real type; needs a seam        |
| `helper` | harnesses that compile helper-only sources the app excludes        | need the helper sources compiled into a test target          |
| `bench`  | benchmarks: CLI tools with arguments, never part of the suite      | deleted, with their scripts and docs                         |
| `remove` | a harness or case that does not belong in a unit-test suite        | deleted once the user approves it (see decision 13)          |
| `skip`   | extension and Raycast harnesses                                    | not converted; they leave the repo with extensions           |

## Decisions

Fixed. A session never reopens one; if a decision proves wrong, stop and write it under
**Open problems** in `status.md` for the user to settle.

1. **Swift Testing only.** No `XCTestCase`, no `XCTAssert`, no `measure`.
2. **One target, `TinycastTests`** (`type: bundle.unit-test` in `project.yml`), hosted by the Debug
   app, sources `Tests/TinycastTests/`. Its suites `@testable import Tinycast`, so the app target sets
   `PRODUCT_MODULE_NAME: Tinycast` (Debug's product name is `Tinycast Dev`, which would otherwise name
   the module `Tinycast_Dev`).
3. **The test host does not start the app.** `TinycastLaunch.main()` detects that it is hosting tests
   and runs a bare `NSApplication` without `AppCore`: no hotkeys, menu-bar items, monitors or prefs.
4. **Layout mirrors the app.** A suite lives at `Tests/TinycastTests/<Area>/<Name>Tests.swift`, where
   `<Area>` is the feature folder (`Calculator`, `Clipboard`, …) or the top-level folder (`App`,
   `Platform`, `Palette`, `DesignSystem`, `Windows`). Shared helpers live in `Support/`, fixture files
   in `Fixtures/`.
5. **A suite keeps its harness's name.** `CalcTests` stays `CalcTests`, so every doc that names a
   harness stays true; only `Tests/<Name>.swift` paths change.
6. **`./Scripts/run-tests.sh` stays the one entry point.** It runs `xcodebuild test` for the target,
   then the remaining `skip` harnesses the old way. `./Scripts/run-tests.sh CalcTests` runs one suite
   (`-only-testing:TinycastTests/CalcTests`) or one leftover harness.
7. **Opt-in checks keep their variable.** `TINYCAST_TEST_*` gates become `.enabled(if:)`; the runner
   forwards each as `TEST_RUNNER_TINYCAST_TEST_*`, which `xcodebuild` passes to the test process.
8. **Model purity moves into `./Scripts/lint.sh`.** It runs the `Model/` import grep and fails on a hit,
   because one test module no longer proves a `Model/` file compiles on its own.
9. **Stand-ins become seams.** A `stub` harness's fake app types are deleted. The real type gains an
   injected dependency (a protocol or a closure) where the test needs to control an effect, or the
   test moves down to the pure part. Never `#if DEBUG`/`#if TESTING` branches in app code for tests.
10. **Benchmarks are deleted.** The 8 `*PerformanceTests` files, `Scripts/benchmark-dictation.sh`,
    their `run index` lines, the `--index` mode and every doc that runs them go. Performance is measured
    with Instruments and the signposts (`docs/testing.md#performance-measurement`).
11. **History survives.** Move a file with `git mv` before rewriting it.
12. **One PR** for the whole migration, on branch `tests/swift-testing`, one commit per batch.
13. **What does not belong in a unit-test suite is removed, never converted.** A harness or a case
    belongs only if it checks a result deterministically on any Mac. Candidates: it measures time or
    prints numbers instead of checking them; it depends on this Mac's state (installed apps, downloaded
    models, hardware, a live network service); it needs a person to judge the output; it drives other
    apps or the real screen; or it repeats another suite's checks. A session never deletes a candidate on
    its own: it lists it under **Removal candidates** in `status.md` with the reason, and the user
    approves or rejects it there. Approved ones are deleted in batch R2.

## How a session runs

### Start

1. `git switch tests/swift-testing && git status`. A dirty tree means the last session stopped
   mid-batch: finish that batch or `git restore` it, then continue. Never start on a dirty tree.
2. Read `AGENTS.md`, this file, `status.md`, and `docs/testing.md#writing-a-suite`.
3. Check the tracker against the truth: every harness still listed in `run-tests.sh` is unconverted.

   ```sh
   grep -oE '^run( [a-z-]+)* [A-Za-z+]+Tests' Scripts/run-tests.sh | awk '{print $NF}' | sort
   ```

   If that list and `status.md` disagree, fix `status.md` first and say so in the commit.
4. Take the batch `status.md` marks **next**, and only that batch.

### Work

For each harness in the batch:

1. If the harness, or one of its cases, matches decision 13, do not convert that part: add it to
   **Removal candidates** in `status.md` and go on with the rest.
2. Run the old harness once and note that it passes: `./Scripts/run-tests.sh <Name>`.
3. Count its checks: the calls to its `expect…`/`check…` helpers, cases in its tables included.
4. `git mv Tests/<Name>.swift Tests/TinycastTests/<Area>/<Name>.swift` (part files too), then rewrite
   it by `docs/testing.md#writing-a-suite`.
5. Delete its `run` line from `Scripts/run-tests.sh`.
6. Run the suite: `./Scripts/run-tests.sh <Name>`. It must pass with **every** old check present:
   same inputs, same expected values, none dropped, none loosened. A table becomes
   `@Test(arguments:)`, not fewer cases.
7. Fix every doc that names the old path or calls it a harness: `grep -rn '<Name>' docs AGENTS.md`.
   In `docs/features/ai.md`, "harness" can also mean an AI coding CLI; leave those alone.

### End

1. `xcodegen generate` if files moved. `./Scripts/run-tests.sh` (the whole suite) and
   `./Scripts/lint.sh` both pass.
2. Update `status.md`: tick the batch's rows, set its status to `done` with the commit, mark the next
   batch **next**, add any decision, removal candidate or open problem.
3. One commit for the batch, tracker included: `Migrate <batch title> to Swift Testing`. No push.
4. If the session ends early, commit what passes, leave the rest unticked, and write where it stopped
   under **Open problems**.

## Who does what, and in which mode

`status.md`'s phase table gives each batch a tool and a mode.

| Batches              | Tool        | Mode  | Why                                                       |
| -------------------- | ----------- | ----- | --------------------------------------------------------- |
| P1, H, S1–S6         | Claude Code | plan  | design choices and app code changes: approve them first   |
| T                    | Claude Code | build | reads and writes only `status.md`                         |
| R1, R2, B1–B12       | Codex       | build | mechanical and fully specified here                       |
| F                    | Claude Code | build | checks and deletions                                      |
| review of last batch | the other   | build | a cheap second read; it reports and changes nothing       |

**Plan mode** (Claude Code: Shift+Tab until it shows _plan mode_) makes the session read and propose
before it touches anything. Read the plan, correct it, then accept it to let the session build. Use it
wherever the table says so: a wrong seam in app code costs far more to undo than to read.

**Build mode** is the default. For Claude Code, accepting edits automatically (Shift+Tab to
_accept edits_) keeps a mechanical batch moving; commands still ask. For Codex, the default
approval mode is right.

Either tool may take any batch when the other is out of quota; a Codex batch done by Claude Code uses
build mode too. Only one tool works on the branch at a time.

## What to say to a fresh session

Start each batch in a new session (`/clear` in Claude Code, a new `codex` run). Both tools read
`AGENTS.md` on their own, and its pointer sends them here, so one prompt serves every batch and both
tools. Neither tool picks a mode by itself; the prompt makes the session honour the batch's mode:

```text
Continue the Swift Testing migration. Follow docs/swift-testing/README.md exactly: take the batch
status.md marks next. If its mode is plan, read what you need, present a plan, and change no file
until I approve it. Then convert it, run the tests, update status.md, and commit. Stop and write
under Open problems instead of guessing.
```

For a plan batch in Claude Code you can also switch to plan mode first (Shift+Tab), which enforces
the read-only step instead of trusting the prompt to hold it.

To review the batch the other tool just committed:

```text
Review the last commit of the Swift Testing migration against docs/swift-testing/README.md and
docs/testing.md#writing-a-suite: every old check kept with the same values, isolation rules followed,
docs updated. Report problems; change nothing.
```

After a session that added **Removal candidates** or **Open problems**, answer them in `status.md`
before starting the next one: tick `approved` or write `keep`, or write the decision. A session never
starts a batch while an open problem it depends on is unanswered.

### Claude Code

- Run `claude` at the repo root, on the branch.
- Use the strongest model your plan allows for the plan-mode batches; Sonnet is enough for build-mode
  batches.

### Codex

- Run `codex` at the repo root, on the branch.
- `xcodebuild test` launches the host app and writes `build/DerivedData`. If the sandbox refuses
  that, approve the command rather than working around it; never skip running the suite.

### Keeping a session cheap

- Pass `-quiet` to `xcodebuild` and read only failures; a full build log fills the context.
- Read a harness once, write the suite once; don't re-read files you just wrote.
- Run one suite while iterating and the whole suite once, at the end.

## Definition of done for the migration

- `status.md` shows every batch done, and every removal candidate approved and deleted or kept.
- `run-tests.sh` lists only `skip` harnesses; `--index` and `run index` are gone.
- `./Scripts/run-tests.sh`, `./Scripts/lint.sh` and a Debug build with no new warnings all pass.
- The tests appear in Xcode's test navigator, and in VS Code's Testing view with SweetPad.
- Last commit: delete `docs/swift-testing/` and the `AGENTS.md` pointer.
