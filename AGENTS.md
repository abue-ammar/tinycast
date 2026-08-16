# Tinycast

A native macOS menu-bar launcher — a minimal Raycast: fuzzy app launcher, global and per-app hotkeys, a
text/image clipboard history, an inline calculator, a floating note, snippets, quicklinks, window
management and an emoji picker. It also **runs Raycast extensions** natively, in JavaScriptCore.
SwiftUI + AppKit, running as an accessory with no Dock icon (`LSUIElement`). Zero third-party
dependencies.

## Posture: latest-only, always

**Tinycast targets one macOS — the current stable release — and nothing else.** macOS 26+, the Xcode 26
toolchain, Swift 6 language mode. There is no compatibility floor to defend, no shim layer and no
deprecation debt, and that is the single largest reason the codebase stays as small as it does.

Write code as if the platform released yesterday:

- **Prefer the modern Apple API**, always. Observation over `ObservableObject`. Swift Concurrency over
  `DispatchQueue` or completion handlers. `SMAppService` over login-item shims. Structured concurrency
  over detached bookkeeping.
- **Migrate, never wrap.** When an API gains a modern replacement, adopt it and delete the old call
  site. A wrapper that preserves an old spelling is the thing this project has spent the most effort
  removing.
- **A deprecated API is a defect**, not a warning to live with.
- **No compatibility layers, no legacy workarounds, no older architectural patterns.** Delete rather
  than deprecate; raising the minimum macOS *deletes* the code that supported the old one.
- **Never introduce backwards compatibility unless explicitly asked for it.** No version flags, no
  migration scaffolding, no "just in case" fallbacks. The two migrations that exist are scheduled for
  deletion; nothing new may depend on them.

Carbon is the one deliberate exception, and it is a capability gap rather than inertia: nothing modern
registers a system-wide chord. Full reasoning in [standards.md](docs/standards.md#posture).

## Where things are

| Folder | Holds |
| --- | --- |
| `Tinycast/App/` | `@main`, `AppDelegate`, `AppCore` — the composition root |
| `Tinycast/DesignSystem/` | shared visual primitives; `Theme.swift` is the only design-token source |
| `Tinycast/Platform/` | system shims: `Permissions`, `AppPaths`, `Signposts`, `NotificationToken`, … |
| `Tinycast/Palette/` | the palette shell: panel, window controller, `RootPaletteView`, `PaletteScreen` |
| `Tinycast/Windows/` | the non-palette AppKit surfaces: `Dialog/`, `HUD/`, `About/`, `AppWindowController` |
| `Tinycast/Features/` | one folder per feature; larger ones split `Model/` `Service/` `UI/` `Settings/` |
| `Tests/` | the standalone harnesses — one Swift file each, no XCTest target |
| `Scripts/` | every executable script: test runner, data generators, packaging, linting, editor setup |

| Read it before you | Doc |
| --- | --- |
| change how anything is wired or owned | [architecture.md](docs/architecture.md) |
| write Swift — naming, style, concurrency, budgets, comments | [standards.md](docs/standards.md) |
| claim a change is done | [testing.md](docs/testing.md) |
| build, run or regenerate data | [development.md](docs/development.md) |
| add or restyle any view | [ui.md](docs/ui.md) |
| touch one feature's internals | [features/](docs/features/) — each opens with its invariants |
| package or ship a build | [release.md](docs/release.md) |

## Non-negotiables

Never break these without an explicit task to do so. Anything feature-specific lives in that
feature's doc, under its own `## Invariants`.

- **`AppCore` is the sole owner.** New long-lived state goes on `AppCore`, wired in `start()` — never a
  competing singleton. Views reach a feature's **coordinator** through `@Environment`, not `AppCore`.
- **A file under `Features/*/Model/` may not import AppKit or SwiftUI**, and takes every environment
  fact — clock, filesystem, home directory, rates — as an injected parameter. The harnesses compile the
  shipped sources, so this is enforced by compilation rather than convention.
- **Swift 6 language mode: data-race violations are hard errors.** `@MainActor` is the default,
  cross-actor model types are `Sendable`, and heavy or IO-bound work goes off-main as `nonisolated`
  functions driven by `Task.detached`. Do not add a second actor.
- **The app is locked to `.darkAqua` globally.** The Liquid Glass material is tuned for a deep dark
  surface; light mode is not a switch, it is a second design.
- **Tinycast presents its own dialogs — never `NSAlert`, `NSSlider` or a system popover.** A question
  goes through `DialogController`, a report through a HUD via `HUDPresenter`.
- **A networked feature fetches on a private `.ephemeral`, `urlCache = nil` session**, never
  `URLSession.shared`, so its own cache file stays the only copy on disk. `CurrencyRateStore` is the
  reference — copy it rather than inventing a second shape. A flag that grants a capability is never
  carried by a backup: `snippetsEnabled` is excluded from settings backups so an import cannot grant
  keystroke listening.
- **Extensions stay inside `Features/Extensions/`.** Every view, row, menu, geometry and sizing
  constant an extension needs is written and owned there — never added to `DesignSystem/`, never bolted
  onto `Theme`, and never shared with another feature. An extension renders untrusted third-party code
  whose shape we do not control, so it must never be able to force a change on a launcher surface.
  **Duplicating a view or a piece of layout maths to keep it here is the correct trade**, and the one
  place the no-duplication rule yields. What *is* shared: `Theme`'s base tokens (spacing, radius,
  colour), `PopoverMenuItem` as a data shape, and `Platform/`. What is never shared: anything with
  "how an extension looks or moves" in it. `ExtensionActionsPanel` and `ExtensionGridGeometry` exist
  precisely because the palette's own menu and the emoji grid must stay free to change without them.
- **`AppEntry.Kind` is the only thing that says what an entry is.** One case per launcher section, per
  `VisibilityStore` category and per Settings pane — never re-derive a category by sniffing an entry ID.
- **Generated files are never hand-edited.** `EmojiData.generated.swift` comes from
  `node Scripts/gen-emoji.js`, `CurrencyData.generated.swift` from `node Scripts/gen-currencies.js`, and
  `Resources/RaycastRuntime.generated.js` from `Scripts/raycast-runtime/build.mjs` — the runtime is
  committed so building the app never needs Node.
- **`DesignSystem/Scrolling/EdgeDissolve.swift` and `ThinScrollbar.swift` are off-limits.** Both are
  tuned by eye against the palette's floating bars, so any edit is a visual regression. Needing to touch
  one to fix a scroll bug means the real fix belongs elsewhere.

## Conventions worth knowing up front

- **A type's suffix says what it *is*** — `Store`, `Coordinator`, `Controller`, `Manager`, `Engine`,
  `Policy` and the rest each name a specific responsibility. **Semantic correctness always wins over
  suffix consistency:** pick the suffix that describes the type honestly, add a new one when none fits,
  and never rename a well-named type just to match the table.
  Full table: [standards.md#naming](docs/standards.md#naming).
- **Comments are rare, one line, and explain the *why*** — the gotcha or invariant, never the what.
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
