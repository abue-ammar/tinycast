## Project

Tinycast is a native macOS menu-bar launcher (a minimal Raycast): fuzzy app launcher, global +
per-app hotkeys, a text/image clipboard history, an inline calculator, and an emoji picker. SwiftUI +
AppKit, runs as an accessory (no Dock icon, `LSUIElement`). Targets **macOS 26+** (Liquid Glass) and
builds with the **Xcode 26** toolchain.

- **Build:** XcodeGen owns the project — `Tinycast.xcodeproj` is committed but generated from
  `project.yml`. After editing `project.yml`, run `xcodegen generate` and commit. There is **no**
  `Package.swift` / SwiftPM. Full build/test/sign/release steps: [`docs/development.md`](docs/development.md),
  [`docs/signing.md`](docs/signing.md).
- **Channels:** Debug builds are their own channel — `Tinycast Dev.app` / `com.tinycast.app.dev` — so a
  local run never shares prefs, caches, TCC grants or login item with an installed stable/beta.
  Anything newly persisted must stay keyed by `Bundle.main.bundleIdentifier`.
- **Tests:** no XCTest target — standalone `swiftc` harnesses in `Tools/` (see Critical Invariants and
  `docs/development.md`).

## Project Philosophy

- Production-quality, as if written by a senior macOS engineer.
- Prefer simple, maintainable solutions over clever ones; preserve existing behavior unless the task
  changes it.
- Keep SwiftUI views declarative and lightweight; business logic lives in models / managers.
- Respect Swift 6 actor isolation; keep expensive work off the main actor.
- Remove dead code rather than adding compatibility layers. Leave the codebase cleaner than you found
  it.
- **Comments are single-line** — no stacked / multi-line blocks. Only comment the non-obvious (a
  _why_, a gotcha, a load-bearing invariant); never restate the code.

## Architecture

Full detail: [`docs/architecture.md`](docs/architecture.md).

- **Single-owner core.** `AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton owning
  every long-lived manager and the window controllers.
  `AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start()` and nothing else — that
  is the one wiring point. Palette / paste / launch actions are methods on `AppCore` that views call.
- **Mostly AppKit windows.** `TinycastApp` (`@main`) declares only a `MenuBarExtra` scene. The command
  palette is a borderless floating `NSPanel` hosting SwiftUI; Settings/About are plain `NSWindow`s via
  `AuxWindowController`. SwiftUI `Settings` / `Window` scenes are deliberately avoided (unreliable for
  accessory apps).
- **Subsystems:** [palette](docs/palette.md) · [launcher & fuzzy match](docs/launcher.md) ·
  [calculator](docs/calculator.md) · [clipboard](docs/clipboard.md) · [emoji](docs/emoji.md) ·
  [snippets](docs/snippets.md) · [hotkeys](docs/hotkeys.md) · [UI & design system](docs/ui.md).

## Critical Invariants

Never break these without an explicit task to do so.

- **`AppCore` is the sole owner.** New long-lived state belongs on `AppCore`, wired in `start()`; don't
  create competing singletons or wire managers elsewhere.
- **`PaletteWindowController` solely owns the palette frame.** The hosting view sets
  `sizingOptions = []` so SwiftUI never drives the window size — otherwise the top edge drifts on the
  compact↔expanded swap.
- **The app is locked to `.darkAqua` globally.** The Liquid Glass material is tuned for a dark surface
  only; do not add light-mode styling.
- **The flat `selection` index must match the visible row order exactly**, including the inline
  calculator card at index 0 when present. Selection is the single source of truth for highlight /
  activation.
- **While a footer menu is open the palette search field never resigns first responder** — input is
  frozen instead (resigning shifts the text a point or two). See [palette.md](docs/palette.md).
- **Focus restoration is load-bearing.** Paste targets the recorded `previousApp` and requires the
  Accessibility permission (`Permissions.ensureAccessibility()`). See [palette.md](docs/palette.md).
- **`Core/Calculator/` (incl. `CalcDateTime`) must stay Foundation-only *and pure*** — no AppKit /
  SwiftUI imports, no clock or network reads. `Tools/calc-test.swift` compiles the real engine
  sources. Both externally-sourced inputs are injected: the clock via `now`/`calendar`, the FX table
  via `rates` (`CurrencyRateStore` owns the fetch). Likewise `Core/Emoji/`
  (`EmojiCatalog`, `EmojiGridGeometry`) stays AppKit/SwiftUI-free for `Tools/emoji-test.swift`, and
  `Core/ClipboardStore.swift` must keep to Foundation + SQLite3 with no other app source, so
  `Tools/clipboard-test.swift` can compile it standalone. `Core/LauncherRankingStore.swift` is the
  same deal for `Tools/ranking-test.swift` — Foundation only, with the clock injected via `now` and
  the store path via `fileURL`, as is `Core/SearchScopes.swift` for `Tools/scopes-test.swift`.
  `Core/CustomCommand.swift` and `Core/ShellCommandRunner.swift` must likewise stay free of AppKit /
  SwiftUI (Foundation plus Combine for `ObservableObject` and Darwin for `mkstemp`) so
  `Tools/custom-command-test.swift` can compile them standalone — which is why the custom-command
  confirmation gate lives in `AppCore` and not in the runner. All of `Core/Snippets/` compiles into
  `Tools/snippets-test.swift` (the harness globs the directory), so the model, Markdown serializer,
  template engine, repository and keyword policies stay Foundation-only, and the AppKit files there
  keep their dependencies to what the harness can stub. `Core/SystemCommand.swift` is also
  Foundation-only for `Tools/system-command-test.swift`; platform effects belong in
  `SystemCommandRunner`, while confirmation and failure UI remain in `AppCore`.
- **`Tools/fuzz-test.swift` holds a COPY of `FuzzyMatch`** from `Core/AppIndex.swift`. Change the
  scoring in one, mirror it in the other, or the test is meaningless.
- **`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js` and
  `CurrencyData.generated.swift` by `node Tools/gen-currencies.js`** — never edit either by hand.
  Currency names, signs and uncontested nouns are generated (Frankfurter × CLDR); the only
  hand-maintained currency data is `CalcCurrency.contested`, the nouns several currencies share
  (`dollars`, `pounds`). Don't add slang or synonyms there — no source of truth, so they rot.
- **Every networked feature ships off and is consent-gated.** Tinycast is offline by default; a
  feature that reaches the network must be opt-in behind a Settings toggle whose dialog names the
  provider, the cadence and what leaves the machine, and its owning store must re-check consent at
  every entry point — including on both sides of the `await` around the request, since consent can
  be withdrawn mid-flight. Consent flags live on the owning store, never in `AppSettings`
  (`SettingsBackup` mirrors that type, and an import must not grant network access). Model the gate
  so the *safe* state is the default: `CalcEngine.evaluate`'s `currency:` parameter defaults to
  `.off`, so forgetting to pass one disables the feature rather than enabling it. Fetch on a private
  **cacheless** `URLSession` (`.ephemeral`, `urlCache = nil`), never `URLSession.shared` — a cacheable
  response would leave a second copy in the on-disk `URLCache` that opting out doesn't delete.
  `CurrencyRateStore` is the reference implementation — follow it rather than inventing a second shape.
- **Snippets are channel-isolated and path-identified.** Persist them under
  `~/Library/Application Support/<bundle-id>/Snippets/`; `StoredSnippet.ID` is the standardized source
  path, and external rename is delete + create. The feature ships off and its enable switch doubles as
  keyword-expansion consent: `snippetsEnabled` is excluded from settings backups, and Accessibility —
  the only permission, since the listen-only tap needs nothing more — may be requested only from that
  explicit Settings gesture, never from startup, callbacks, watchers or health checks.
  See [snippets.md](docs/snippets.md).
- **Swift 6 language mode: data-race violations are hard errors.** Almost everything is `@MainActor`;
  cross-actor model types are `Sendable`; heavy / IO work (app scan, image decode) is pushed off-main
  via `Task.detached` / `nonisolated`. Keep that boundary. House idioms: `NotificationToken` (RAII) for
  block observers, `isolated deinit` for `ClipboardStore`'s SQLite teardown, decode raw Carbon / C
  pointers to plain values before crossing into actor code.
- **Clipboard writes stamp a private `internalType` marker** so the poller skips Tinycast's own writes.
- **Hotkeys persist under legacy `KeyboardShortcuts_<name>` UserDefaults keys** (from the removed
  KeyboardShortcuts package) so old bindings survive. See [hotkeys.md](docs/hotkeys.md).
- **Tinycast presents its own dialogs, never `NSAlert` / `NSSlider` / system popovers.** Every
  confirmation, failure report, value prompt and transient readout goes through
  `ModalWindowController` (owned by `AppCore`; reachable elsewhere via `AppCore.showNotice` /
  `askConfirmation`). Presentation is `async`, so there is no nested run loop, and the presenter
  refuses a second dialog while one is up that, not a flag, is what stops a held hotkey stacking
  dialogs. **↵ belongs to Cancel on every destructive dialog.** See
  [ui.md](docs/ui.md#modals--hud).
- **Read [`docs/ui.md`](docs/ui.md) before any restyle or new view.** `Core/Theme.swift` is the single
  design-token source.
- **`Core/EdgeDissolve.swift` and `Core/ThinScrollbar.swift` are off-limits.** Both are tuned by eye
  against the palette's floating bars, so any edit is a visual regression. Do not touch them to fix a
  scroll bug, and never as a side effect of a restyle or refactor — needing to is the signal that the
  real fix belongs elsewhere (a scroll target, an inset, an intent). Edit either one only under an
  explicit task to change that look.

## Project Layout

- `Tinycast/Core/` — managers, stores, windows, AppKit glue (no view bodies beyond hosting).
  `Core/Calculator/` and `Core/Emoji/` are Foundation-only engines; `Core/Snippets/` is a
  standalone-harness input in full; `Core/Theme.swift` is the design-token source;
  `Core/HotKey/` is the in-house hotkey stack.
- `Tinycast/Features/` — SwiftUI views: `RootPaletteView`, `Launcher/`, `Clipboard/`, `Calculator/`,
  `Emoji/`, `Settings/`, `About/`, `Onboarding/`, plus shared `PopoverMenu`.
- `Tinycast/App/` — `@main` app + delegate.
- `Tools/` — standalone test harnesses and the emoji generator.
- `.github/workflows/release.yml` — the entire release pipeline (see `docs/development.md`).

## Additional Documentation

- [`docs/architecture.md`](docs/architecture.md) — core ownership, windows, concurrency.
- [`docs/palette.md`](docs/palette.md) — palette state flow, menu-open freeze, focus restoration.
- [`docs/launcher.md`](docs/launcher.md) · [`docs/calculator.md`](docs/calculator.md) ·
  [`docs/clipboard.md`](docs/clipboard.md) · [`docs/emoji.md`](docs/emoji.md) ·
  [`docs/snippets.md`](docs/snippets.md) · [`docs/hotkeys.md`](docs/hotkeys.md) — subsystem internals.
- [`docs/ui.md`](docs/ui.md) — the full visual design system, tokens, scrollbars, section headers.
- [`docs/development.md`](docs/development.md) — build, test, package, release.
- [`docs/signing.md`](docs/signing.md) — signing model and Gatekeeper.
