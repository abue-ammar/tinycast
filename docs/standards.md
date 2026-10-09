# Engineering standards

How code in Tinycast is written. This is **guidance** — it describes what the codebase already looks
like so that new code reads like it was there all along, and a good reason to depart from it is a good
reason. What is actually checked is the bar in
[testing.md](testing.md#definition-of-done); the rules that may not be broken at all are the
Non-negotiables in [`AGENTS.md`](../AGENTS.md).

When this document and the code disagree, the code is probably right and this file is stale. Fix it.

## Posture

Tinycast supports macOS 26 and later, with macOS 27 strongly preferred. Swift 6+ with complete strict
concurrency is required. Prefer the latest Swift patterns and modern Apple APIs, following
[`AGENTS.md`](../AGENTS.md#posture-modern-first-always).

Verify API and language-feature availability against the SDK and compiler used by the build and CI.
Use direct availability checks where macOS 27+ APIs require them to preserve macOS 26 support. Do not
introduce compatibility layers, legacy workarounds, support below macOS 26, migration scaffolding or
speculative fallbacks.

In practice that means Observation and never `ObservableObject` or `@Published`; `SMAppService` and
never an `LSSharedFileList` shim. Adopt successors directly and delete obsolete call sites rather
than wrapping an old spelling.

**Prefer synchronous code.** Keep short UI and state operations synchronous on `@MainActor`.
Introduce concurrency only for genuinely asynchronous operations or blocking work that must leave
the main actor. Shared state alone does not justify `async`, a `Task`, or an actor. Preserve
synchronous callback returns and event ordering. When concurrency is needed, prefer structured
concurrency with clear ownership and cancellation. Strict concurrency checking enforces safety;
it does not require making operations asynchronous.

Carbon has two deliberate capability-gap uses. The global hotkey engine uses `RegisterEventHotKey`
because nothing modern can register a system-wide chord, and `CGEventTap` cannot see a lone modifier
press. `InputSourceSwitcher` uses HIToolbox's TIS APIs because they remain the public mechanism for
enumerating and selecting keyboard input sources. Neither use is inertia, and raw C pointers never
cross an asynchronous actor boundary.

## Architecture and feature organization

Full detail in [architecture.md](architecture.md); the rules a new feature has to satisfy:

- **One folder per feature** under `Tinycast/Features/<Name>/`, holding everything that feature owns —
  its model, its services, its views and its own Settings panes.
- A larger feature splits into `Model/` (pure), `Service/` (effects), `UI/` (views and the feature's
  coordinator) and `Settings/` (its panes). A small one stays flat. Split when the flat folder stops being
  scannable, not on principle.
- **`Model/` may not import AppKit or SwiftUI.** Everything from the environment is injected — the clock,
  the filesystem, the home directory, the rates table. This is the enforced rule below.
- New long-lived state belongs on `AppCore`, wired in `start()`. Do not create a second singleton.
- A Settings pane lives with its feature. Only a pane no feature owns lives in `Settings/Panes/`.
- Shared visual primitives go in `DesignSystem/`, system shims in `Platform/`. Neither may depend on a
  feature.

Feature work reaches the app through a **coordinator**, called by `AppCore` and by views via
`@Environment`. Confirmation gates live in the coordinator, never in the runner — which is what lets
`ShellCommandRunner` and `SystemActionRunner` stay harness-compilable while the "are you sure?" step
remains unbypassable.

## Naming

A type's suffix says what it _is_. **Semantic correctness comes first**: pick the suffix that names the
responsibility honestly, and add a row here when none of them does. Do not rename a well-named type to
fit the table.

| Suffix        | Means                                                                         |
| ------------- | ----------------------------------------------------------------------------- |
| `Store`       | Owns persisted state and publishes it                                         |
| `Repository`  | File semantics a `Store` does not imply — conflict detection, revision checks |
| `Coordinator` | A feature's action surface, called by `AppCore` and the palette               |
| `Controller`  | Owns one AppKit window or surface                                             |
| `Presenter`   | Owns presentation policy across surfaces — one-at-a-time, auto-dismiss, fade  |
| `Manager`     | Owns a subsystem's lifecycle _and_ its policy; started from `AppCore.start()` |
| `Service`     | A stateless capability other types call                                       |
| `Provider`    | Supplies values on demand, owning no policy about their use                   |
| `Monitor`     | Watches an external stream and reports changes; owns no policy                |
| `Scanner`     | Reads the filesystem to produce candidates                                    |
| `Runner`      | Performs one effectful operation on request                                   |
| `Launcher`    | An `NSWorkspace.open` wrapper specifically                                    |
| `Center`      | The Carbon registration layer specifically                                    |
| `Access`      | One surface's raw platform reads, shared so its walkers cannot disagree       |
| `Session`     | Transient state for one in-progress interaction                               |
| `State`       | Shared observable state that persists nothing itself                          |
| `Catalog`     | Pure static namespace over a built-in list                                    |
| `Index`       | A searchable collection, rebuilt as its inputs change                         |
| `Engine`      | A pure evaluator: input → output                                              |
| `Policy`      | A pure decision — no state, no effects                                        |

`Manager` is the one worth thinking twice about. It means _lifecycle plus policy_, which is a lot for one
type, so there are only two: `ClipboardManager` (polls, and owns the capture policy and the paste-side
handshake) and `HotKeyManager` (persists bindings, and drives Carbon registration and double-tap
dispatch). A third is fine if it genuinely owns both halves — but check first whether `Store`, `Monitor`
or `Coordinator` describes it better, because usually one of them does.

`Registry` and `ViewModel` are retired: a static table is a `Catalog`, shared app state is a `State`.
SwiftUI-layer names (`View`, `Screen`, `Card`, `Row`, `Sheet`) are a separate vocabulary and are not
governed by this table.

### Files

- One top-level type per file, named for it. A `View` file is named for its view; a namespace `enum` for
  the namespace.
- Private nested helpers are free to be named for their job — the table governs top-level types only.
- `*.generated.swift` is emitted by a script in `Scripts/` and never hand-edited.

## Swift style

Match the surrounding code. Beyond that:

- **Early returns over nesting.** A `guard` at the top beats an `if` wrapping the body.
- `let` unless mutation is needed. No abbreviations in names — `index`, not `idx`.
- Prefer a named constant or a small type to a comment explaining a literal.
- Keep types and functions to a single responsibility. If a function needs a section comment, it wants to
  be two functions.
- Views stay declarative and thin. Business logic lives in a model, a store or a coordinator — a `body`
  that decides things is the most common way this codebase gets worse.
- Prefer composition over a long `body`. Extract a subview before extracting a `@ViewBuilder` helper.
- Errors surface through `DialogController` (something the user must acknowledge) or
  `MessageHUDController` (something transient). Never a `print`, never a silent `try?` on a path the user
  cares about.
- Diagnostics go through `Logger` with a per-subsystem category, and timings through
  `Platform/Signposts.swift`. Neither is a substitute for the other.
- Delete dead code rather than commenting it out or leaving a compatibility path behind it.

## Concurrency and lifetime

Swift 6 language mode: data-race violations are hard errors, and that is the design, not an obstacle.

- **`@MainActor` is the default.** Almost everything has UI coupling or identity; assume main actor
  unless there is a reason.
- Heavy or IO-bound work goes off-main explicitly. Prefer `@concurrent` async functions when work must
  leave the caller's actor; use `Task.detached` when an independent task is needed. `async` or
  `nonisolated` alone does not guarantee off-main execution; check the actual isolation and compiler
  settings. Keep pure work separate from UI state and do not introduce a custom actor.
- Use `Sendable` for model values shared across isolation boundaries and `sending` for exclusive
  ownership transfer. Reach for `@unchecked Sendable` or `nonisolated(unsafe)` only with a written
  reason, and never for convenience.
- **No new `MainActor.assumeIsolated`.** It traps at runtime if the assumption is ever wrong.
- Long-lived service tasks are stored and cancelled in `stop()` or `deinit`; SwiftUI `.task` follows
  the view lifetime. Every long-lived task has an owner and teardown.
- Cancellation is cooperative. Propagate it to detached or callback-backed work owned by the caller;
  do not swallow `CancellationError` as an ordinary failure or cancel shared work for one waiter.
- An `await` permits state to change. Before applying a result that can become obsolete, revalidate
  cancellation, operation identity and destination after suspension and at the mutation boundary.
- A continuation completes exactly once across success, failure and cancellation. Handle cancellation
  without leaving a waiter suspended, resuming twice or leaking owned producer work.
- Block observers go through the RAII `NotificationToken` (`Platform/NotificationToken.swift`), not a
  bare `addObserver` plus removal in `deinit`.
- A child process is started with `runObservingExit()` (`Platform/ProcessExit.swift`) and awaited
  through the `ProcessExit` it returns, never `waitUntilExit()`: that spins the calling thread's run
  loop, which on a GCD thread can miss the exit and block forever.
- Use `[weak self]` where a closure or task would form a cycle or retain its owner beyond the intended
  lifetime. Strong capture is valid for intentional bounded work; `[unowned self]` needs a guaranteed
  lifetime. Unwrapping weak `self` before a long suspension still retains it until the work finishes.
- `DispatchQueue.main.async` is not a fix for an ordering problem. If order matters, make it explicit.
- `ClipboardStore` uses `isolated deinit` for its SQLite teardown — the idiom to copy for a resource that
  must be torn down on its actor.

Two gotchas worth knowing before they cost an afternoon:

- **`withObservationTracking`'s `onChange` is a willSet hook.** It fires _before_ the write lands, so a
  re-read must be deferred into a `Task` — which is also where the tracking is re-armed, since the
  closure is one-shot. `AppCore.track` is the shape to copy.
- **A signpost interval leaks if the wrapped work throws.** The `.end` emit is skipped on the throw path
  unless it is in a `defer`. `Signposts.interval` already does this.

### Observation

Use `@Observable` for UI state rather than `ObservableObject` or `@Published`:

- `@ObservationIgnored` on memo caches and lazily-built collaborators. Without it, reading a memo
  registers a dependency and the view re-renders on its own cache fill.
- Never write a type annotation on `@Environment` for an `@Observable` type — the macro resolves the
  keyless overload by type, and an annotation changes which overload is chosen.
- **The compiler is blind to a missed injection site.** A view reading `@Environment(AppSettings.self)`
  from a hierarchy nobody injected into compiles and traps at runtime, so check the injection when adding
  a new hosting view.
- `swiftc -parse` does not expand macros. Use `-typecheck` when checking an `@Observable` type standalone.

## Performance and memory

Budgets, not aspirations:

- **Resident memory under 100 MB, always.** No feature is worth going over. Memory returns to baseline
  after the palette closes.
- Launch is the thing the app protects most. Work added to `AppCore.start()` or to an initialiser is the
  most expensive place to put it; defer it into a `Task` or do it on first use.
- The palette must feel instant. Anything on the summon path is resolved once per show, never per render.
- Zero leaks and no retain cycles. Ownership is a tree with `AppCore` at the root.

Beyond that:

- **Measure before optimising, and measure before caching.** The app already caches what should be
  cached; a new cache needs a number, not an intuition. [testing.md](testing.md) has the recipes.
- Avoid repeated work and needless allocation in loops that run per keystroke or per row.
- Prefer a cheaper data structure to a cache over an expensive one.
- Do not add an abstraction to make something faster later.

## Simplicity and maintainability

The bar the whole codebase is held to, and the reason it stays legible:

- Prefer the simplest correct solution. Clever is a cost paid by whoever reads it next.
- **Do not add an abstraction until it removes more complexity than it adds.** Protocols, generics and
  factories need a present purpose, such as an injected effect boundary or shared behaviour. A single
  conformer or use alone is not a defect; an abstraction that only forwards needs no extra layer.
- Preserve existing behaviour unless the task is to change it. Behaviour changes are decisions, and
  decisions get discussed.
- Delete rather than deprecate. There is no audience for a compatibility layer in an app with no API.
- Leave the codebase cleaner than you found it — but in a separate commit from the change that noticed.

## Comments

Minimal code, not annotated prose.

1. **One line.** Never two consecutive comment lines. If it needs two, it needs a named function, a named
   constant, or a type.
2. **Hard cap 100 characters**, including indentation. Longer belongs in a doc under `docs/`.
3. Comment the _why_, the gotcha, or the invariant. Never restate the code, never narrate a sequence,
   never argue a decision at length in-line.
4. **Prefer deleting a comment to updating it.**
5. Never add a comment explaining a change you just made. The diff is not the audience.
6. A `///` doc comment on a public type or method follows the same rules. It is not a licence to stack
   lines.

None of this is linted, by choice. A rule that fires after the
comment is written buys a second edit; these are cheap to get right on the first pass instead.

## Accessibility

Every custom control carries a label and the traits that describe it. The palette is an entirely custom
control surface, so nothing comes for free — a row, a keycap chip, a footer pill and a dialog button all
need saying explicitly. Adding it as the view is written costs a line; retrofitting it costs a rewrite.

## What is actually checked

Everything above is guidance. The mechanical bar — the harnesses, the purity grep, lint and a
clean build — is one list, in [testing.md](testing.md#definition-of-done), so that it cannot drift by
being written down twice. Anything not on it is a judgement call: make it, and say why in the PR if it
is not obvious.
