# Architecture

How Tinycast is wired together. See the per-subsystem docs for internals:
[palette](palette.md), [launcher](launcher.md), [calculator](calculator.md),
[clipboard](clipboard.md), [custom commands](custom-commands.md), [snippets](snippets.md),
[hotkeys](hotkeys.md), [ui](ui.md).

## Single-owner core

`AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton that owns every long-lived
manager — `AppIndex`, `ClipboardStore`, `ClipboardManager`, `SnippetsStore`,
`SnippetKeywordListener`, `SnippetTextInjector`, `HotKeyManager`, `AppSettings`, `FavoritesStore`,
`VisibilityStore`, `LauncherRankingStore`, `CustomCommandStore`, `CalculatorHistoryStore`,
`CurrencyRateStore`, `RunningAppsMonitor`, `PaletteViewModel` — plus the window controllers.
`AppDelegate.applicationDidFinishLaunching` calls
`AppCore.shared.start()` and nothing else; that is the single wiring point. All palette / paste /
launch actions are methods on `AppCore` that the SwiftUI views call.

## Entry points and windows

`TinycastApp` (`@main`) declares only a `MenuBarExtra` scene; everything else visible is driven
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

## Snippets

`SnippetRepository` is a Foundation-only `Sendable` value that owns all snippet disk access under
`~/Library/Application Support/<bundle-id>/Snippets/`, keeping stable, beta and dev isolated. The
model, Markdown codec, template engine, repository, keyword buffer, event classification and listener
lifecycle policy compile in the standalone harness without AppKit. `SnippetsStore` is the `@MainActor`
publisher/coordinator: initialization is cheap, repository work runs off-main, and a debounced
generation-ordered watcher reloads external edits and rearms after directory replacement. A stored
snippet is identified by its source file path, so editing frontmatter never invalidates selection or
launcher identity. `AppCore` projects every successful store snapshot into `AppIndex` and
`SnippetKeywordListener`; neither consumer reads or parses snippet files independently. The store
runs only while the feature switch is on — snippets ship off — so an untouched feature costs no
load, no watcher and no tap.

The feature switch doubles as keyword-expansion consent: it is an explicit opt-in confirmed in
Settings and excluded from settings backups. When an enabled feature comes back at startup, the
listener waits until Accessibility is granted — the only permission it needs, since its tap is
listen-only — then its health check installs the tap without prompting. Permission prompts
originate only from the enabling gesture in Settings, never from startup, the listener, callbacks or the
health check. The listener owns only matching and tap lifecycle; `AppCore` owns template expansion and
argument prompts, while `SnippetTextInjector` owns target activation, keyword deletion, text delivery,
temporary pasteboard restoration and cursor placement. See [snippets.md](snippets.md) for storage,
frontmatter, templates, conflicts, permissions and delivery invariants.

## Concurrency

The target builds in **Swift 6 language mode** (tools version 6.0, no language-mode override), so
data-race safety violations are hard errors. Almost everything is `@MainActor`; cross-actor model
types are `Sendable`. Heavy / IO work (app scan, image decode, the FX rate fetch) is deliberately
pushed off-main via `Task.detached` / `nonisolated`. Keep that boundary when adding code.

House idioms for the sharp edges:

- Block-observer lifetimes go through the RAII `NotificationToken` (`Core/NotificationToken.swift`)
  instead of removal in a `deinit`.
- `ClipboardStore` uses `isolated deinit` for its SQLite teardown.
- Raw Carbon / C pointers get decoded to plain values before crossing into actor code (see
  `hotKeyCarbonEventHandler`).
