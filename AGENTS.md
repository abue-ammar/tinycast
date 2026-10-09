# Tinycast

A native macOS menu-bar launcher: fuzzy app launcher, global and per-app hotkeys, a text/image
clipboard history, an inline calculator, a floating note, snippets, quicklinks, window management
and an emoji picker. It also **runs Raycast extensions** natively, in JavaScriptCore.
SwiftUI + AppKit, running as an accessory with no Dock icon (`LSUIElement`). Zero third-party
dependencies.

## Posture: modern-first, always

**Tinycast supports macOS 26 and later, with macOS 27 strongly preferred.** Swift 6+ with complete
strict concurrency is required. Prefer the latest Swift patterns and modern Apple APIs.

Prefer current APIs and language features:

- **Prefer the modern Apple API**, always. Observation over `ObservableObject`. `SMAppService` over
  login-item shims.
- **Prefer synchronous code.** Keep short UI and state operations synchronous on `@MainActor`.
  Introduce concurrency only for genuinely asynchronous operations or blocking work that must leave
  the main actor. Shared state alone does not justify `async`, a `Task`, or an actor. Preserve
  synchronous callback returns and event ordering. When concurrency is needed, prefer structured
  concurrency with clear ownership and cancellation. Strict concurrency checking enforces safety;
  it does not require making operations asynchronous.
- **Migrate, never wrap.** Adopt modern replacements directly and delete obsolete call sites. Do not
  keep wrappers that only preserve an old spelling.
- **A deprecated API is a defect**, not a warning to live with.
- **Verify API and language-feature availability** against the SDK and compiler used by the build
  and CI. Use direct availability checks where macOS 27+ APIs require them to preserve macOS 26 support.
- **No compatibility layers, legacy workarounds or obsolete patterns.** No migration scaffolding,
  support below macOS 26 or speculative fallbacks. Keep the implementation direct.

Carbon is a deliberate capability-gap dependency rather than inertia: nothing modern registers a
system-wide chord, and HIToolbox's TIS APIs remain the public input-source mechanism. Full reasoning in
[standards.md](docs/standards.md#posture).

## Where things are

| Folder                   | Holds                                                                                   |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `Tinycast/App/`          | `@main`, `AppDelegate`, `AppCore` — the composition root                                |
| `Tinycast/DesignSystem/` | shared visual primitives; `Theme.swift` is the only design-token source                 |
| `Tinycast/Platform/`     | system shims: `Permissions`, `AppPaths`, `Signposts`, `NotificationToken`, …            |
| `Tinycast/Palette/`      | the palette shell: panel, window controller, `RootPaletteView`, `PaletteScreen`         |
| `Tinycast/Windows/`      | the non-palette AppKit surfaces: `Dialog/`, `HUD/`, `About/`, `AppWindowController`     |
| `Tinycast/Features/`     | one folder per feature; larger ones split `Model/` `Service/` `UI/` `Settings/`         |
| `Tests/`                 | the standalone harnesses — one Swift file each, no XCTest target                        |
| `Scripts/`               | every executable script: test runner, data generators, packaging, linting, editor setup |

| Read it before you                                          | Doc                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------ |
| change how anything is wired or owned                       | [architecture.md](docs/architecture.md)                      |
| write Swift — naming, style, concurrency, budgets, comments | [standards.md](docs/standards.md)                            |
| claim a change is done                                      | [testing.md](docs/testing.md)                                |
| build, run or regenerate data                               | [development.md](docs/development.md)                        |
| add or restyle any view                                     | [ui.md](docs/ui.md)                                          |
| touch one feature's internals                               | [features/](docs/features/) — each opens with its invariants |
| package or ship a build                                     | [release.md](docs/release.md)                                |

## Non-negotiables

Never break these without an explicit task to do so. Anything feature-specific lives in that
feature's doc, under its own `## Invariants`.

- **`AppCore` is the sole owner.** New long-lived state goes on `AppCore`, wired in `start()` — never a
  competing singleton. Views reach a feature's **coordinator** through `@Environment`, not `AppCore`.
- **A file under `Features/*/Model/` may not import AppKit or SwiftUI**, and takes every environment
  fact — clock, filesystem, home directory, rates — as an injected parameter. The harnesses compile the
  shipped sources, so this is enforced by compilation rather than convention.
- **Swift 6 language mode: data-race violations are hard errors.** `@MainActor` is the default,
  model values shared across isolation boundaries are `Sendable`, and exclusive ownership transfer
  uses `sending`. Heavy or IO-bound work goes off-main. Prefer `@concurrent` async functions when work
  must leave the caller's actor; use `Task.detached` when an independent task is needed. Do not add a
  second actor.
- **Async results can become stale across suspension.** Before applying them, validate cancellation,
  operation identity and destination where they can change. Long-lived work has an owner and teardown;
  detached or callback-backed work owned by a caller follows that caller's cancellation.
- **Dark is the baseline, and a colour's dark branch is the literal it always was.** `Theme.Colors`
  resolves per appearance through `ramp`/`adaptive`; every dark value is the `Color.white.opacity(…)`
  the forced-dark build shipped, restated rather than re-derived. Retune a light branch freely — change
  a dark one only when the task is to change Dark. `AppAppearance` drives `NSApp.appearance`, and
  `.system` maps to `nil` so AppKit follows macOS on its own.
- **Tinycast presents its own dialogs — never `NSAlert` or a system popover.** A question
  goes through `DialogController`, a report through a HUD via `HUDPresenter`.
- **A networked feature fetches on a private `.ephemeral`, `urlCache = nil` session**, never
  `URLSession.shared`, so its own cache file stays the only copy on disk. `CurrencyRateStore` is the
  reference — copy it rather than inventing a second shape. A flag that grants a capability is never
  carried by a backup or by `settings.json`: `snippetsEnabled` is excluded from settings backups so an
  import cannot grant keystroke listening.
- **Extensions stay inside `Features/Extensions/`.** Every view, row, menu, geometry and sizing
  constant an extension needs is written and owned there — never added to `DesignSystem/`, never bolted
  onto `Theme`, and never lifted somewhere another feature can build on it. Another surface may render
  one as an opaque box — `LauncherScreen` does exactly that with `ExtensionArgumentsAccessory` — but it
  never reaches inside one. An extension renders untrusted third-party code whose shape we do not
  control, so it must never be able to force a change on a launcher surface.
  **Duplicating a view or a piece of layout maths to keep it here is the correct trade**, and the one
  place the no-duplication rule yields. What _is_ shared: `Theme`'s base tokens (spacing, radius,
  colour), `InterfaceMetrics` as the view over those same base tokens, `PopoverMenuItem` as a data
  shape, and `Platform/`. What is never shared: anything with
  "how an extension looks or moves" in it. `ExtensionActionsPanel` and `ExtensionGridGeometry` exist
  precisely because the palette's own menu and the emoji grid must stay free to change without them.
- **`AppEntry.Kind` is the only thing that says what an entry is.** One case per launcher section and
  per `VisibilityStore` category — never re-derive a category by sniffing an entry ID. Which _pane_
  lists a command is a separate fact, and `SettingsTab.ownedCommands` is the only place that states it.
- **Generated files are never hand-edited.** `EmojiData.generated.swift` and
  `Resources/EmojiKeywords/` come from `node Scripts/gen-emoji.js`, `CurrencyData.generated.swift` from `node Scripts/gen-currencies.js`,
  `CountryZoneData.generated.swift` from `node Scripts/gen-countries.js`, and
  `Resources/RaycastRuntime.generated.js` from `Scripts/raycast-runtime/build.mjs` — the runtime is
  committed so building the app never needs Node.
- **`DesignSystem/Scrolling/EdgeDissolve.swift` and `ThinScrollbar.swift` are off-limits.** Both are
  tuned by eye against the palette's floating bars, so any edit is a visual regression. Needing to touch
  one to fix a scroll bug means the real fix belongs elsewhere.

## Conventions worth knowing up front

- **A new preference also gets a `SettingsFileKey`** and its binding in `SettingsFileSchema`, so the
  opt-in `settings.json` mirror carries it; the exhaustive switch fails the build until it is bound.
  See [settings-file.md](docs/features/settings-file.md).
- **A type's suffix says what it _is_** — `Store`, `Coordinator`, `Controller`, `Manager`, `Engine`,
  `Policy` and the rest each name a specific responsibility. **Semantic correctness always wins over
  suffix consistency:** pick the suffix that describes the type honestly, add a new one when none fits,
  and never rename a well-named type just to match the table.
  Full table: [standards.md#naming](docs/standards.md#naming).
- **Comments are rare, one line, and explain the _why_** — the gotcha or invariant, never the what.
  **Never two in a row, never extended into a block**: if one line can't carry it, name a function,
  constant or type instead. Cap 100 characters, delete rather than update, and never comment a change
  you just made. Nothing lints this; get it right the first time.
  Full rules: [standards.md#comments](docs/standards.md#comments).
- **Debug builds are their own channel** — `Tinycast Dev.app` / `com.tinycast.app.dev` — so a local run
  never shares prefs, caches, TCC grants or the login item with an installed copy. Anything newly
  persisted must stay keyed by `Bundle.main.bundleIdentifier`.
- **XcodeGen owns the project.** `Tinycast.xcodeproj` is committed but generated from `project.yml`;
  after editing it, run `xcodegen generate` and commit both. No SwiftPM, and never `Bundle.module`.

## Before you finish

Each item is explained in [testing.md](docs/testing.md#definition-of-done).

- `./Scripts/run-tests.sh` passes.
- The Debug build compiles with **no new warnings**.
- `./Scripts/lint.sh` is clean.
- `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing.
- Any doc your change made wrong is fixed in the same commit.
