## Project

Tinycast is a native macOS menu-bar launcher (a minimal Raycast): fuzzy app launcher, global +
per-app hotkeys, a text/image clipboard history, an inline calculator, an emoji picker, and it **runs
Raycast extensions** natively. SwiftUI + AppKit, runs as an accessory (no Dock icon, `LSUIElement`).
Targets **macOS 26+** (Liquid Glass) and builds with the **Xcode 26** toolchain.

- **Build:** XcodeGen owns the project — `Tinycast.xcodeproj` is committed but generated from
  `project.yml`. After editing `project.yml`, run `xcodegen generate` and commit. There is **no**
  `Package.swift` / SwiftPM. Full build/test/sign/release steps: [`docs/development.md`](docs/development.md),
  [`docs/signing.md`](docs/signing.md).
- **Channels:** Debug builds are their own channel — `Tinycast Dev.app` / `com.tinycast.app.dev` — so a
  local run never shares prefs, caches, TCC grants or login item with an installed stable/beta.
  Anything newly persisted must stay keyed by `Bundle.main.bundleIdentifier`.
- **Extension runtime:** `Tinycast/Resources/RaycastRuntime.generated.js` is generated from
  `Tools/raycast-runtime/` (`pnpm install && node build.mjs`) and **committed**, so building the app
  never needs Node. See [`docs/extensions.md`](docs/extensions.md).
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
  [hotkeys](docs/hotkeys.md) · [Raycast extensions](docs/extensions.md) ·
  [UI & design system](docs/ui.md).
- **Extensions** run prebuilt Raycast bundles in a JavaScriptCore context on a private serial queue
  (`Core/Extensions/ExtensionRuntime.swift`); a bundled React reconciler commits a JSON render tree that
  `ExtensionScreen` flattens and `Features/Extensions/` draws natively.

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
- **`Core/Calculator/` (incl. `CalcDateTime`) must stay Foundation-only** — no AppKit / SwiftUI
  imports. `Tools/calc-test.swift` compiles the real engine sources. Likewise `Core/Emoji/`
  (`EmojiCatalog`, `EmojiGridGeometry`) stays AppKit/SwiftUI-free for `Tools/emoji-test.swift`.
- **`FuzzyMatch` lives in `Core/FuzzyMatch.swift`** (Foundation-only) and is shared by the launcher and
  by extension `List` filtering; `Tools/fuzz-test.swift` compiles that real source — there is no copy to
  keep in sync.
- **`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js`** — never edit it by hand.
- **`Resources/RaycastRuntime.generated.js` is emitted by `Tools/raycast-runtime/build.mjs`** — never
  edit it by hand; change `Tools/raycast-runtime/src/` and rebuild.
- **Exactly one extension command runs at a time, in its own `JSContext`.** Starting a command stops
  the previous one and discards the whole JS context (`ExtensionRuntime.shutdown()`); the next launch
  boots a fresh one. Never cancel timers globally to "clean up" instead — React's scheduler commits
  through `setTimeout`, so that wedges every later session. Host calls also carry no session id, so
  `ExtensionManager.activeExtensionName` is what namespaces storage, cache and preferences; don't add a
  second concurrent session without threading a session id through the bridge.
- **`ExtensionRuntime`'s `@unchecked Sendable` is load-bearing:** every `JSContext`/`JSValue` touch
  happens on its private serial queue, and only plain `Sendable` values (`RenderValue`, `RenderTree`,
  JSON strings) cross in or out. Keep that boundary.
- **Swift 6 language mode: data-race violations are hard errors.** Almost everything is `@MainActor`;
  cross-actor model types are `Sendable`; heavy / IO work (app scan, image decode) is pushed off-main
  via `Task.detached` / `nonisolated`. Keep that boundary. House idioms: `NotificationToken` (RAII) for
  block observers, `isolated deinit` for `ClipboardStore`'s SQLite teardown, decode raw Carbon / C
  pointers to plain values before crossing into actor code.
- **Clipboard writes stamp a private `internalType` marker** so the poller skips Tinycast's own writes.
- **Hotkeys persist under legacy `KeyboardShortcuts_<name>` UserDefaults keys** (from the removed
  KeyboardShortcuts package) so old bindings survive. See [hotkeys.md](docs/hotkeys.md).
- **`ExtensionScreen` is the only place extension row order is decided**, so the flat `selection` index
  keeps matching the visible rows (same invariant as the other palette screens).
- **Read [`docs/ui.md`](docs/ui.md) before any restyle or new view.** `Core/Theme.swift` is the single
  design-token source.

## Project Layout

- `Tinycast/Core/` — managers, stores, windows, AppKit glue (no view bodies beyond hosting).
  `Core/Calculator/` and `Core/Emoji/` are the Foundation-only engines; `Core/Extensions/` the Raycast
  extension host; `Core/Compression/Zlib.swift` gzip/zlib both directions; `Core/Theme.swift` the design
  tokens; `Core/HotKey/` the in-house hotkey stack.
- `Tinycast/Resources/` — `RaycastRuntime.generated.js`, the embedded extension runtime.
- `Tinycast/Features/` — SwiftUI views: `RootPaletteView`, `Launcher/`, `Clipboard/`, `Calculator/`,
  `Emoji/`, `Extensions/`, `Settings/`, `About/`, `Onboarding/`, plus shared `PopoverMenu`.
- `Tinycast/App/` — `@main` app + delegate.
- `Tools/` — standalone test harnesses, the emoji generator, and `raycast-runtime/` (the npm project
  that builds the embedded extension runtime).
- `.github/workflows/release.yml` — the entire release pipeline (see `docs/development.md`).

## Additional Documentation

- [`docs/architecture.md`](docs/architecture.md) — core ownership, windows, concurrency.
- [`docs/palette.md`](docs/palette.md) — palette state flow, menu-open freeze, focus restoration.
- [`docs/launcher.md`](docs/launcher.md) · [`docs/calculator.md`](docs/calculator.md) ·
  [`docs/clipboard.md`](docs/clipboard.md) · [`docs/emoji.md`](docs/emoji.md) ·
  [`docs/hotkeys.md`](docs/hotkeys.md) · [`docs/extensions.md`](docs/extensions.md) — subsystem
  internals.
- [`docs/ui.md`](docs/ui.md) — the full visual design system, tokens, scrollbars, section headers.
- [`docs/development.md`](docs/development.md) — build, test, package, release.
- [`docs/signing.md`](docs/signing.md) — signing model and Gatekeeper.
