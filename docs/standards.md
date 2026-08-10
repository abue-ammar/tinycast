# Engineering standards

How code in Tinycast is written. This is **guidance** — it describes what the codebase already looks
like so that new code reads like it was there all along, and a good reason to depart from it is a good
reason. What is actually checked is the bar in
[testing.md](testing.md#definition-of-done); the rules that may not be broken at all are the
Non-negotiables in [`AGENTS.md`](../AGENTS.md).

When this document and the code disagree, the code is probably right and this file is stale. Fix it.

## Posture

The rule — latest-only, prefer modern APIs, no compatibility layers, never add backwards compatibility
unasked — is stated in [`AGENTS.md`](../AGENTS.md#posture-latest-only-always). This section is the
reasoning and the concrete shape it takes.

The reason it is worth being strict about: a compatibility floor is not a one-time cost. Every shim
outlives the platform that needed it, gets copied by the next feature that sees it, and turns a
one-line call into a layer nobody dares delete. Tinycast has no external API, no plugin surface and one
supported OS, so it has nothing to be compatible *with* — which is the whole reason it stays this
small. The version-gated code this project has deleted has consistently been larger than the feature it
was gating.

In practice that means Observation and never `ObservableObject` or `@Published`; `async`/`await` and
never a completion handler or a `DispatchQueue` hop; `SMAppService` and never an `LSSharedFileList`
shim; structured concurrency and never detached bookkeeping you have to remember to cancel. When one of
these gains a successor, the migration is the change — not a wrapper preserving the old spelling.

Carbon is the one deliberate exception. The global hotkey engine uses `RegisterEventHotKey` because
nothing modern can register a system-wide chord, and `CGEventTap` cannot see a lone modifier press.
That is a capability gap, not inertia — and every raw C pointer is decoded to plain values before it
crosses into actor code.

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

A type's suffix says what it *is*. **Semantic correctness comes first**: pick the suffix that names the
responsibility honestly, and add a row here when none of them does. Do not rename a well-named type to
fit the table.

| Suffix | Means |
| --- | --- |
| `Store` | Owns persisted state and publishes it |
| `Repository` | File semantics a `Store` does not imply — conflict detection, revision checks |
| `Coordinator` | A feature's action surface, called by `AppCore` and the palette |
| `Controller` | Owns one AppKit window or surface |
| `Presenter` | Owns presentation policy across surfaces — one-at-a-time, auto-dismiss, fade |
| `Manager` | Owns a subsystem's lifecycle *and* its policy; started from `AppCore.start()` |
| `Service` | A stateless capability other types call |
| `Provider` | Supplies values on demand, owning no policy about their use |
| `Monitor` | Watches an external stream and reports changes; owns no policy |
| `Scanner` | Reads the filesystem to produce candidates |
| `Runner` | Performs one effectful operation on request |
| `Launcher` | An `NSWorkspace.open` wrapper specifically |
| `Center` | The Carbon registration layer specifically |
| `Session` | Transient state for one in-progress interaction |
| `State` | Shared observable state that persists nothing itself |
| `Catalog` | Pure static namespace over a built-in list |
| `Index` | A searchable collection, rebuilt as its inputs change |
| `Engine` | A pure evaluator: input → output |
| `Policy` | A pure decision — no state, no effects |

`Manager` is the one worth thinking twice about. It means *lifecycle plus policy*, which is a lot for one
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
- Heavy or IO-bound work goes off-main explicitly, as `nonisolated static` pure functions driven by
  `Task.detached` — the app scan, image decode, the settings-pane scan, shell execution. Keep that
  boundary; do not introduce a custom actor.
- Cross-actor model types are `Sendable`. Reach for `@unchecked Sendable` or `nonisolated(unsafe)` only
  with a written reason, and never for convenience.
- **No new `MainActor.assumeIsolated`.** It traps at runtime if the assumption is ever wrong.
- Any long-lived `Task` is stored and cancelled in `stop()` or `deinit`. An un-owned `Task` is a leak
  with extra steps.
- Block observers go through the RAII `NotificationToken` (`Platform/NotificationToken.swift`), not a
  bare `addObserver` plus removal in `deinit`.
- Every escaping closure capturing `self` uses `[weak self]`, or `[unowned self]` where the closure
  cannot outlive the owner (as in `AppCore`'s coordinator wiring).
- `DispatchQueue.main.async` is not a fix for an ordering problem. If order matters, make it explicit.
- `ClipboardStore` uses `isolated deinit` for its SQLite teardown — the idiom to copy for a resource that
  must be torn down on its actor.

Two gotchas worth knowing before they cost an afternoon:

- **`withObservationTracking`'s `onChange` is a willSet hook.** It fires *before* the write lands, so a
  re-read must be deferred into a `Task` — which is also where the tracking is re-armed, since the
  closure is one-shot. `AppCore.track` is the shape to copy.
- **A signpost interval leaks if the wrapped work throws.** The `.end` emit is skipped on the throw path
  unless it is in a `defer`. `Signposts.interval` already does this.

### Observation

28 types use `@Observable`; nothing uses `ObservableObject` or `@Published`. Migrating anything new into
this model:

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
- Release binary under **4 MB**.
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
- **Do not add an abstraction until it removes more complexity than it adds.** A protocol with one
  conformer, a generic with one instantiation and a factory for one type are all worse than the concrete
  thing.
- Preserve existing behaviour unless the task is to change it. Behaviour changes are decisions, and
  decisions get discussed.
- Delete rather than deprecate. There is no audience for a compatibility layer in an app with no API.
- Leave the codebase cleaner than you found it — but in a separate commit from the change that noticed.

## Comments

Minimal code, not annotated prose.

1. **One line.** Never two consecutive comment lines. If it needs two, it needs a named function, a named
   constant, or a type.
2. **Hard cap 100 characters**, including indentation. Longer belongs in a doc under `docs/`.
3. Comment the *why*, the gotcha, or the invariant. Never restate the code, never narrate a sequence,
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

Everything above is guidance. The mechanical bar — the harnesses, the purity grep, format and lint, a
clean build — is one list, in [testing.md](testing.md#definition-of-done), so that it cannot drift by
being written down twice. Anything not on it is a judgement call: make it, and say why in the PR if it
is not obvious.
