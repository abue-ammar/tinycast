# Architecture

How Smallcast is wired together. See the per-subsystem docs for internals:
[palette](palette.md), [launcher](launcher.md), [calculator](calculator.md),
[clipboard](clipboard.md), [hotkeys](hotkeys.md), [extensions](extensions.md), [ui](ui.md).

## Single-owner core

`AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton that owns every long-lived
manager — `AppIndex`, `ClipboardStore`, `ClipboardManager`, `HotKeyManager`, `AppSettings`,
`FavoritesStore`, `VisibilityStore`, `CalculatorHistoryStore`, `RunningAppsMonitor`,
`ExtensionManager`, `PaletteViewModel` — plus the window controllers. `AppDelegate.applicationDidFinishLaunching` calls
`AppCore.shared.start()` and nothing else; that is the single wiring point. All palette / paste /
launch actions are methods on `AppCore` that the SwiftUI views call.

## Entry points and windows

`SmallcastApp` (`@main`) declares only a `MenuBarExtra` scene; everything else visible is driven
imperatively from AppKit.

- **Command palette** — a borderless floating `NSPanel` (`Core/PalettePanel.swift`) hosting SwiftUI
  via `NSHostingView`, managed by `PaletteWindowController`. It toggles between a compact bar and the
  full launcher by resizing the window. `PaletteWindowController` solely owns the frame (resolved once
  per show to a top-left anchor so it grows downward), and the hosting view sets `sizingOptions = []`
  so SwiftUI never drives the window size — without that the hosting view resizes the panel to fit
  content and the top edge drifts on the compact↔expanded swap. The panel auto-dismisses on
  `windowDidResignKey`.
- **Settings / About** — plain `NSWindow`s via `AuxWindowController` (in
  `Features/About/AboutView.swift`). SwiftUI `Settings` / `Window` scenes are unreliable for accessory
  apps, so this is deliberate.

The app forces `.darkAqua` appearance globally; the Liquid Glass material is tuned for a dark surface
only.

## Concurrency

The target builds in **Swift 6 language mode** (tools version 6.0, no language-mode override), so
data-race safety violations are hard errors. Almost everything is `@MainActor`; cross-actor model
types are `Sendable`. Heavy / IO work (app scan, image decode) is deliberately pushed off-main via
`Task.detached` / `nonisolated`. Keep that boundary when adding code.

House idioms for the sharp edges:

- Block-observer lifetimes go through the RAII `NotificationToken` (`Core/NotificationToken.swift`)
  instead of removal in a `deinit`.
- `ClipboardStore` uses `isolated deinit` for its SQLite teardown.
- Raw Carbon / C pointers get decoded to plain values before crossing into actor code (see
  `hotKeyCarbonEventHandler`).
- `ExtensionRuntime` (`Core/Extensions/`) is `@unchecked Sendable` around a private serial
  `DispatchQueue`: JavaScriptCore is single-threaded, and running extension code (plus its blocking
  `fs`/`exec` shims) must stay off the main actor. Only plain `Sendable` values cross the boundary —
  `RenderValue` in, `RenderTree` out, JSON strings for results. See [extensions.md](extensions.md).

## Raycast extensions

`ExtensionManager` owns the installed set and the one running command; `ExtensionRuntime` owns the
JavaScriptCore context. Extensions are prebuilt CommonJS bundles, so nothing is compiled at runtime; the
bundled `Resources/RaycastRuntime.generated.js` supplies React, a reconciler that commits a JSON render
tree, the `@raycast/api` shim and the Node/web polyfills a bare `JSContext` lacks. `ExtensionScreen`
flattens a tree into palette rows and `Features/Extensions/` draws them. Full detail:
[extensions.md](extensions.md).
