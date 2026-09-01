# Architecture

How Tinycast is wired together. Per-feature internals live in [features/](README.md#features);
conventions for writing new code live in [standards.md](standards.md).

## The layering

Independently of the folder tree, every mature subsystem has converged on the same four layers, and the
`Tests/` harnesses are what hold them apart.

```
┌─ PURE ─────────────────────────────────────────────────────────────────────┐
│ Foundation only. No AppKit, no clock, no network, no filesystem. Every     │
│ environment fact is an injected parameter.                                 │
│ ⇒ Compiled verbatim by a harness, so it cannot drift.                      │
│                                                                            │
│ SearchRelevance · SearchScopes · LauncherRankingStore · FileSearch{Query,  │
│ Result,Scope} · Calculator/* · EmojiCatalog · EmojiGridGeometry ·          │
│ SystemAction · VolumeLevel ·                                               │
│ WindowCommand · WindowLayout · WindowActionMemory · PaletteRowIndex ·      │
│ Uninstall{Target,SearchRoot,Rules,Protection,Plan} ·                       │
│ Quicklink{,Destination,Store,Archive} · Notes/Model/* · Snippets/Model/* · │
│ ShellCommandRunner · DoubleTap{Modifier,Detector} · ClipboardStore ·       │
│ RaycastDecoder · Scrypt · AppSettingsKey · SettingsBackupCoverage          │
│ MeetingLink · MeetingEvent · UpcomingWindow · MeetingDay · MenuBarSummary  │
│ AutoJoinPolicy · EventDraft · SupportReminderSchedule                      │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ consumed by
┌─ EFFECT ─────────────────────────▼─────────────────────────────────────────┐
│ All platform I/O, one folder per feature.                                  │
│ AppIndex · SpotlightNames · FileSearchService · SettingsPaneScanner ·      │
│ IconCache · WindowMover · UninstallScanner · UninstallRunner ·             │
│ SystemActionRunner · QuicklinkLauncher · TextInjector ·             │
│ SnippetKeywordListener · NotesRepository · CurrencyRateStore · Paster ·    │
│ HotKeyCenter · HyperKeyTap · DoubleTapMonitor · RunningAppsMonitor ·       │
│ CalendarStore · MeetingLauncher · MeetingClock · CameraPreviewSession ·    │
│ SupportReminderStore                                                       │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ published through
┌─ OBSERVABLE STATE ───────────────▼─────────────────────────────────────────┐
│ 38 @MainActor @Observable stores, sessions, indices and State types        │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ rendered by
┌─ VIEW ───────────────────────────▼─────────────────────────────────────────┐
│ SwiftUI screens, views and each feature's coordinator — declarative, thin  │
└────────────────────────────────────────────────────────────────────────────┘
```

In the folder tree those become `Model/`, `Service/`, and `UI/` plus `Settings/` — observable state lives
in whichever of the two owns it.

- **`Model/` — pure.** Foundation only, plus SQLite3 or CoreGraphics where the data demands it.
  Everything from the environment is **injected**: `CalcEngine` takes `now` / `calendar` / `rates`,
  `LauncherRankingStore` takes `now` and its file URL, `WindowActionMemory` takes `now` as a parameter,
  `UninstallRules` is handed directory *names* rather than URLs, and `QuicklinkStore` is handed the home
  directory. This is the layer that **decides** things.
- **`Service/` — effects.** Stores, monitors, runners, scanners and AppKit glue. Every `AXUIElement`
  call, `CGEventTap`, `NSWorkspace.open`, `URLSession` request, `FileManager` walk and CoreAudio read
  lives here. This is the layer that **does** things.
- **`UI/` and `Settings/` — views**, plus the feature's coordinator. Declarative, thin, holding no policy.

The rule is checkable, which is the point: **a file under `Model/` may not import AppKit or SwiftUI**,
because the harnesses compile the shipped sources rather than a copy. A harness that stops compiling is
the signal that a decision leaked into the effect layer, or an effect into the decision layer.

The boundary keeps effects out of decisions: `CalcEngine.evaluate` is handed a finished
`CurrencyRates?` rather than reaching for one, which is what keeps it Foundation-only and testable.
Confirmation gates live in the coordinator, never in the runner — which is why `ShellCommandRunner`
and `SystemActionRunner` stay harness-compilable while the "are you sure?" step still cannot be bypassed.

Two things sit deliberately outside a feature folder: `Features/PaletteRowIndex.swift`, because the
palette rather than any one feature owns the flat selection index, and `DesignSystem/` + `Platform/`,
the shared primitives and system shims every feature draws on. Neither may depend on a feature.

## Single-owner core

`AppCore.shared` (`App/AppCore.swift`) is a `@MainActor` singleton owning every long-lived thing in the
app: the stores (`AppIndex`, `ClipboardStore`, `SnippetsStore`, `QuicklinkStore`, `CustomCommandStore`,
`FavoritesStore`, `VisibilityStore`, `AliasStore`, `LauncherRankingStore`, `CalculatorHistoryStore`,
`CurrencyRateStore`, `FrequentEmojiStore`, `CalendarStore`), the managers, monitors and clocks
(`ClipboardManager`,
`HotKeyManager`, `HyperKeyTap`, `RunningAppsMonitor`, `SnippetKeywordListener`), the shared state
(`AppSettings`, `PaletteState`, `FileSearchSession`, `UninstallSession`,
`QuicklinkArgumentSession`, `MeetingClock`), `NotesStore`, the twenty feature coordinators, and the
window controllers.

`AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start()` and nothing else. That is the
one wiring point, and `start()` reads as the app's whole boot sequence in one screen.

**Feature actions live on that feature's coordinator, and a view must never reach past a coordinator
into a store to mutate it.** That is the rule; `AppCore` holds only the closure wiring that connects a
hotkey to a coordinator. Views inject `AppCore` through `@Environment` and use it as the *locator* for
those coordinators — `core.quicklinkCoordinator.deleteQuicklink(…)` is the shape, and the alternative
is injecting fifteen coordinators separately for no gain. Reading a store off `AppCore` to render it is
fine too; deciding something with one is what the rule forbids. `showNotice`, `confirm`,
`reportFailure`, `showMessage` and `pickVolume` are forwarders on `AppCore` itself, so
`DialogController` and `MessageHUDController` stay single-owned.

New long-lived state belongs on `AppCore`, wired in `start()`. Do not create a competing singleton: this is a singleton, not a container.

## Entry points and windows

`TinycastApp` (`@main`) declares only two `MenuBarExtra` scenes — Tinycast's own item and the
calendar's, each inserted by one preference and independent of the other; everything else visible is
driven imperatively from AppKit.

- **Command palette** — a borderless floating `NSPanel` (`Palette/PalettePanel.swift`) hosting SwiftUI
  via `NSHostingView`, managed by `PaletteWindowController`. It toggles between a compact bar and the
  full launcher by resizing the window. The controller **solely** owns the frame, resolved once per show
  to a top-left anchor so it grows downward, and the hosting view sets `sizingOptions = []` so SwiftUI
  never drives the window size — without that the hosting view resizes the panel to fit content and the
  top edge drifts on the compact↔expanded swap. The panel auto-dismisses on `windowDidResignKey`.
  See [features/palette.md](features/palette.md).
- **Settings and Onboarding** — titled `NSWindow`s, one `Windows/AppWindowController.swift` each, owned
  by `SettingsCoordinator` and `OnboardingCoordinator`. SwiftUI `Settings` and `Window` scenes are
  unreliable for accessory apps, so this is deliberate. Their lifecycles are independent of the
  palette's in both directions.
- **Notes** — a persistent, titled, non-activating `NotesPanel` managed by `NotesWindowController`.
  The user owns its size and AppKit autosaves the frame; its literal-source TextKit 2 editor switches
  among local Markdown files and stays visible on focus loss. The displayed string is the canonical
  file source; Notes has no parser, rendered preview, or source/display mapping.
  See [features/notes.md](features/notes.md).
- **The main menu** — shaped by `TinycastApp`'s `.commands`, which rebinds ⌘Q to Close Settings. It is
  only ever on screen while a titled window is open, so it is Settings' menu bar. It must stay
  declarative.
- **Dialogs** — borderless `DialogPanel`s driven by `DialogController`, the app's only presenter for
  confirmations, failure reports and value prompts. Presentation is `async`, so nothing blocks the main
  actor, and the presenter refuses a second dialog while one is up — that, not a flag, is what stops a
  held hotkey stacking dialogs.
- **Support** — a titled `AppWindowController` window owned by `SupportCoordinator`, sized to the
  height its content measured. Every route into it — the palette's menu circle, Settings → About, the
  menu bar, the launcher, and the 30-day reminder — lands on `showSupport()`, which is what moves the
  reminder's anchor. See [features/support.md](features/support.md).
- **The camera preview** — a borderless, non-activating `CameraPreviewPanel` at `.floating`,
  managed by `CameraPreviewController` and owned by `CalendarCoordinator` the way `NotesCoordinator`
  owns its window. It gates a join and doubles as auto join's confirmation.
  See [features/calendar.md](features/calendar.md).
- **HUDs** are separate, because a dialog asks and a HUD reports: `MessageHUDController` (the pill) and
  `VolumeHUDController` (the level box), both over a shared `HUDPresenter` that owns the
  one-at-a-time, auto-dismiss and fade policy. See [ui.md](ui.md#dialogs--hud).

`NSAlert` is never used, and that is load-bearing. Appearance is a setting: `AppCore.applyAppearance()`
assigns `NSApp.appearance` from `AppSettings.appearance`, and `.system` assigns `nil` so AppKit follows
macOS by itself. Nothing else in the app sets an appearance.

## Observation

38 types are `@MainActor @Observable`. Nothing uses `ObservableObject` or `@Published`, and views read
state through `@Environment` rather than `@EnvironmentObject`.

Three things about this model are easy to get wrong:

- **`@ObservationIgnored` on memo caches** and lazily-built collaborators. Without it, reading a memo
  registers a dependency and the view re-renders on its own cache fill. `AppCore`'s coordinators are all
  `@ObservationIgnored private(set) lazy` for this reason.
- **Never annotate `@Environment` with a type** for an `@Observable` value. The macro resolves the
  keyless overload by type, and an explicit annotation changes which overload is chosen.
- **The compiler cannot see a missed injection site.** A view reading `@Environment(AppSettings.self)`
  from a hierarchy nobody injected into compiles fine and traps at runtime, so check the injection when
  adding a hosting view.

`AppCore.track` is the pattern for reacting to a settings change outside a view.
`withObservationTracking`'s `onChange` is a **willSet** hook — it fires before the write lands and is
one-shot — so the closure defers the re-read into a `Task` and re-arms the tracking there. Both halves
are required; removing the `Task` reads the old value.

## Concurrency

The target builds in **Swift 6 language mode**, so data-race violations are hard errors. Almost
everything is `@MainActor`; cross-actor model types are `Sendable`. Heavy and IO-bound work — the app
scan, image decode, the settings-pane scan, shell execution, the FX rate fetch — is pushed off-main as
`nonisolated static` functions driven by `Task.detached`. There is exactly one actor, deliberately.

House idioms for the sharp edges:

- Block-observer lifetimes go through the RAII `NotificationToken` (`Platform/NotificationToken.swift`)
  rather than removal in a `deinit`.
- `ClipboardStore` uses `isolated deinit` for its SQLite teardown.
- Raw Carbon and C pointers are decoded to plain values before crossing into actor code (see
  `hotKeyCarbonEventHandler`).
- `HealthTicker` (`Platform/HealthTicker.swift`) is the one shared timer for periodic health checks, so
  the event taps do not each own one.

## The tree

The folder layout is the layering above, made navigable — one folder per feature, each holding
everything that feature owns.

```
Tinycast/
  App/              @main, AppDelegate, AppCore — the composition root
  DesignSystem/     Theme (the token source), KeyCapChip, Tooltip, SymbolImage,
                    VisualEffectView, PopoverMenu, SettingsComponents, Scrolling/, Interaction/
  Platform/         system shims: Permissions, LaunchAtLogin, InputSourceSwitcher, ScreenTarget,
                    AppDisplayName,
                    NotificationToken, AppPaths, Signposts, HealthTicker, Memo, ActivationPolicy,
                    Images/, Compression/
  Resources/        RaycastRuntime.generated.js, the embedded extension runtime
  Palette/          the palette shell: PalettePanel, PaletteWindowController, RootPaletteView,
                    the PaletteScreen protocol, PaletteCoordinator, PaletteState, PaletteMode
  Windows/          the non-palette AppKit surfaces: AppWindowController, Dialog/, HUD/, About/
  Assets.xcassets/  the app icon and the bundled image sets some catalog symbols resolve to
  Features/
    PaletteRowIndex.swift   the flat selection index — palette-owned, so it sits at the top
    Launcher/ Clipboard/ Calculator/ Calendar/ Emoji/ FileSearch/ Notes/ Quicklinks/ Snippets/
    Uninstall/ SystemActions/ CustomCommands/ HotKeys/ Backup/ WindowManagement/ Onboarding/
    Updates/ Support/ AI/ Settings/
    Extensions/
        Model/      pure — the harness inputs
        Service/    effects — stores, monitors, runners, AppKit glue
        UI/         screens, views, and the feature's coordinator
        Settings/   the feature's own panes
    Settings/       the Settings shell only: SettingsCoordinator, the sidebar/detail/toolbar and
                    navigation types, SettingsTab, AppSettings, AppSettingsKey, and Panes/ for the
                    two panes no feature owns
Tests/              the standalone harnesses, one Swift file each
Scripts/            run-tests.sh, the two data generators, packaging, formatting, editor setup
```

A larger feature splits into all four sub-folders; a small one stays flat, as `Onboarding/` and
`WindowManagement/` do. `HotKeys/` has no `Settings/` because its Shortcuts pane is part of the Settings
shell rather than the feature.

Every `SettingsTab` maps to one `…SettingsView`, and each is a stock `Form` with
`.formStyle(.grouped)` — see [ui.md](ui.md#settings). A pane lives with its feature; only a pane no
feature owns (General, Permissions) lives in `Settings/Panes/`. The four launcher-category panes —
Applications, System Settings, System Actions, Commands — are thin wrappers over the shared
`LauncherItemsSection`.

`SettingsTab` and `SettingsSection` both identify by the case itself, never by an index. A selectable
`List` flattens section and row IDs into one namespace, so overlapping `Int` IDs make SwiftUI drop
whole sidebar groups; `Tests/settings-history-test.swift` pins the two namespaces apart.
