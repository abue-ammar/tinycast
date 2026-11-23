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
│ SearchRelevance · LauncherMatch · EntryNaming · ScriptRomanization ·       │
│ LauncherOrder · LauncherSuggestions · LauncherRankingStore · SearchScopes · │
│ FileSearch{Query,Result,Scope} ·                                           │
│ Calculator/* · EmojiCatalog · EmojiGridGeometry · SystemAction ·            │
│ VolumeLevel ·                                                              │
│ WindowCommand · WindowPlacementEngine · WindowActionMemory · WindowLayout/* ·      │
│ CustomWindowSize{,Store} · Room/* ·                                        │
│ PaletteRowIndex ·                                                          │
│ Uninstall{Target,SearchRoot,Rules,Protection,Plan} ·                       │
│ Quicklink{,Destination,Store,Archive} · AppleShortcut · Notes/Model/* ·    │
│ Snippets/Model/* ·                                                         │
│ ShellCommandRunner · DoubleTap{Modifier,Detector} · ClipboardStore ·       │
│ RaycastDecoder · Scrypt · AppSettingsKey · SettingsBackupCoverage          │
│ SettingsFile{JSON,Key,Value,Format,Binding,Issue,Identity} ·               │
│ HotKeySpelling · WindowManagementFileFormat ·                              │
│ MeetingLink · MeetingEvent · UpcomingWindow · MeetingDay · MenuBarSummary  │
│ AutoJoinPolicy · EventDraft · SupportReminderSchedule ·                    │
│ MenuSearch{Item,Shortcut,Query,TreeNode,SnapshotPolicy,Target} ·           │
│ WindowSwitch{Entry,Order,Query}                                            │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ consumed by
┌─ EFFECT ─────────────────────────▼─────────────────────────────────────────┐
│ All platform I/O, one folder per feature.                                  │
│ AppIndex · FileIndexer · SettingsPaneScanner ·                             │
│ AXWindowAccess · AXScreens · WindowInventory · WindowLayoutRunner ·        │
│ RoomWindowSweep · RoomRunner ·                                             │
│ IconCache · WindowMover · UninstallScanner · UninstallRunner ·             │
│ SystemActionRunner · QuicklinkLauncher · TextInjector ·             │
│ SnippetKeywordListener · NotesRepository · CurrencyRateStore · Paster ·    │
│ HotKeyCenter · HyperKeyTap · KeyboardRemapper · ModifierTapMonitor ·       │
│ SecureInputMonitor · RunningAppsMonitor ·                                  │
│ CalendarStore · MeetingLauncher · MeetingClock · CameraSession ·           │
│ SupportReminderStore · AXMenuAccess · WindowZOrder · WindowSwitchSweep ·   │
│ AppleShortcutRunner · SettingsFileRepository · SettingsFileMonitor ·       │
│ WindowManagementSettingsFile                                               │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ published through
┌─ OBSERVABLE STATE ───────────────▼─────────────────────────────────────────┐
│ 39 @MainActor @Observable stores, sessions, indices and State types        │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ rendered by
┌─ VIEW ───────────────────────────▼─────────────────────────────────────────┐
│ SwiftUI screens, views and each feature's coordinator: declarative, thin   │
└────────────────────────────────────────────────────────────────────────────┘
```

In the folder tree those become `Model/`, `Service/`, and `UI/` plus `Settings/`; observable state lives
in whichever of the two owns it.

- **`Model/`: pure.** Foundation only, plus SQLite3 or CoreGraphics where the data demands it.
  Everything from the environment is **injected**: `CalcEngine` takes `now` / `calendar` / `rates`,
  `LauncherRankingStore` takes `now` and its file URL, `WindowActionMemory` takes `now` as a parameter,
  `UninstallRules` is handed directory _names_ rather than URLs, and `QuicklinkStore` is handed the home
  directory. This is the layer that **decides** things.
- **`Service/`: effects.** Stores, monitors, runners, scanners and AppKit glue. Every `AXUIElement`
  call, `CGEventTap`, `NSWorkspace.open`, `URLSession` request, `FileManager` walk and CoreAudio read
  lives here. This is the layer that **does** things.
- **`UI/` and `Settings/`: views**, plus the feature's coordinator. Declarative, thin, holding no policy.

The rule is checkable, which is the point: **a file under `Model/` may not import AppKit or SwiftUI**,
because the harnesses compile the shipped sources rather than a copy. A harness that stops compiling is
the signal that a decision leaked into the effect layer, or an effect into the decision layer.

The boundary keeps effects out of decisions: `CalcEngine.evaluate` is handed a finished
`CurrencyRates?` rather than reaching for one, which is what keeps it Foundation-only and testable.
Confirmation gates live in the coordinator, never in the runner, which is why `ShellCommandRunner`
and `SystemActionRunner` stay harness-compilable while the "are you sure?" step still cannot be bypassed.

Two things sit deliberately outside a feature folder: `Features/PaletteRowIndex.swift`, because the
palette rather than any one feature owns the flat selection index, and `DesignSystem/` + `Platform/`,
the shared primitives and system shims every feature draws on. Neither may depend on a feature.

## Single-owner core

`AppCore.shared` (`App/AppCore.swift`) is a `@MainActor` singleton owning every long-lived thing in the
app: the stores (`AppIndex`, `ClipboardStore`, `SnippetsStore`, `QuicklinkStore`, `CustomCommandStore`,
`FavoritesStore`, `VisibilityStore`, `AliasStore`, `LauncherRankingStore`, `CalculatorHistoryStore`,
`CurrencyRateStore`, `FrequentEmojiStore`, `CalendarStore`), the managers, monitors and clocks
(`ClipboardManager`, the opt-in `ClipboardTextIndexer`, the opt-in `SettingsFileRepository`, the
`SettingsBindingSet` it shares with iCloud Sync,
`HotKeyManager`, `HyperKeyManager`, `RunningAppsMonitor`,
`SnippetKeywordListener`), the shared state
(`AppSettings`, `PaletteState`, `FileSearchSession`, `MenuSearchSession`, `UninstallSession`,
`MeetingClock`), `NotesStore`, the twenty-two feature coordinators (`CloudSyncCoordinator` owns the
opt-in iCloud Sync session) and the
window controllers.

`AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start(launchedByUser:)` and nothing
else; the delegate only reads the launch Apple Event to tell a plain open from a login-item or URL
launch. That is the one wiring point, and `start` reads as the app's whole boot sequence in one screen.

**Feature actions live on that feature's coordinator, and a view must never reach past a coordinator
into a store to mutate it.** That is the rule; `AppCore` holds only the closure wiring that connects a
hotkey to a coordinator. Views inject `AppCore` through `@Environment` and use it as the _locator_ for
those coordinators: `core.quicklinkCoordinator.deleteQuicklink(…)` is the shape, and the alternative
is injecting fifteen coordinators separately for no gain. Reading a store off `AppCore` to render it is
fine too; deciding something with one is what the rule forbids. `showNotice`, `confirm`,
`reportFailure`, `showMessage` and `pickVolume` are forwarders on `AppCore` itself, so
`DialogController` and `MessageHUDController` stay single-owned.

New long-lived state belongs on `AppCore`, wired in `load()` when Settings' own process needs it too,
otherwise in `start()`. Do not create a competing singleton: this is a singleton, not a container.

`start(launchedByUser:)` is the main app's boot: `load()` (preferences applied, stores read, hotkey bindings
loaded, nothing registered, tapped or polled), then everything that runs an engine. `startSettings()` is
the Settings process's: `load()` plus its line to the main app. Neither role checks the other's at run
time; the split is the boundary.

Clipboard text recognition runs outside the process. `AppCore` owns the indexer;
the stateless `ClipboardTextWorker` runs one bundled `ClipboardTextHelper` per item, from
`Contents/Helpers`, and reaps it before returning. Vision's and PDFKit's allocations therefore belong
to a process that exits, and the helper (which has no database, clipboard or settings access) is
handed an input path and answers with bounded text down a pipe. Its `thumbnail` mode writes the
clipboard's downscaled image copies, so a full-size decode stays out of the app unless that fails.

Dictation similarly runs its model adapters in a bundled helper, with bounded in-memory audio and
text over pipes. The coordinator keeps microphone capture, UI and insertion in Tinycast; the model
store starts the helper on demand and reaps it after the selected idle delay or a model switch.
`AppCore` owns the audio ducker and starts volume recovery on every launch, even when Dictation is off.

## Entry points and windows

`TinycastLaunch` (`@main`) pins the interface language, then runs `TinycastApp`, which declares
only two `MenuBarExtra` scenes: Tinycast's own item and the
calendar's, each inserted by one preference and independent of the other; everything else visible is
driven imperatively from AppKit. Extension menu extras are dynamic `NSStatusItem`s owned entirely by
`Features/Extensions/`, through `ExtensionManager`, with no scene or lifecycle wiring in the core.

- **Command palette**: a borderless floating `NSPanel` (`Palette/PalettePanel.swift`) hosting SwiftUI
  via `NSHostingView`, managed by `PaletteWindowController`. It toggles between a compact bar and the
  full launcher by resizing the window. The controller **solely** owns the frame, resolved once per show
  to a top-left anchor so it grows downward, and the hosting view sets `sizingOptions = []` so SwiftUI
  never drives the window size; without that the hosting view resizes the panel to fit content and the
  top edge drifts on the compact↔expanded swap. The panel auto-dismisses on `windowDidResignKey`,
  unless a modal panel holds key.
  See [features/palette.md](features/palette.md).
- **Settings**: runs in its own process, so its memory leaves when the window closes. See
  [The Settings process](#the-settings-process).
- **Onboarding**: a titled `NSWindow` in `Windows/AppWindowController.swift`, owned by
  `OnboardingCoordinator`. SwiftUI `Window` scenes are unreliable for accessory apps, so this is
  deliberate. Its lifecycle is independent of the palette's in both directions, and it stays accessory
  rather than registering Dock ownership, so completing it can open the palette without an
  activation-policy change stealing focus.
- **Notes**: a persistent, titled, non-activating `NotesPanel` managed by `NotesWindowController`.
  Its height fits the note up to 860pt and AppKit autosaves the frame; its TextKit 2 editor renders
  Markdown over the literal source, switches among local Markdown files and stays visible on focus
  loss. The displayed string is the canonical file source; there is no source/display mapping.
  See [features/notes.md](features/notes.md).
- **AI Chat**: a titled `AppWindowController` window owned by `AIChatCoordinator`: an
  `NSSplitViewController` with a collapsible sidebar of saved chats beside the open conversation, as
  Settings is built. The conversation lives on `AppCore.aiChats`, not the window, so closing it cancels
  nothing. Quick AI is the same feature's palette screen. See [features/ai.md](features/ai.md).
- **The main menu**: shaped by `TinycastApp`'s `.commands`, which rebinds ⌘Q to Close Window for the AI
  Chat window. It is only ever on screen while a titled window is open, so it is those windows' menu
  bar. It must stay declarative. Settings' process declares its own, in `SettingsApp`.
- **Dialogs**: borderless `DialogPanel`s driven by `DialogController`, the app's only presenter for
  confirmations, failure reports and value prompts outside Settings, whose panes ask with SwiftUI's
  sheet-style `confirmationDialog` or `alert`. Presentation is `async`, so nothing blocks the main
  actor, and the presenter refuses a second dialog while one is up; that, not a flag, is what stops a
  held hotkey stacking dialogs.
- **Support**: a titled `AppWindowController` window owned by `SupportCoordinator`, sized to the
  height its content measured. Every route into it (the palette's menu circle, Settings → About, the
  menu bar, the launcher, and the 30-day reminder) lands on `showSupport()`, which is what moves the
  reminder's anchor. See [features/support.md](features/support.md).
- **The camera surfaces**: a borderless, non-activating `CameraPanel` at `.floating`, in two
  shapes over one `CameraSession`: `CameraPreviewController`, owned by `CalendarCoordinator`, gates a
  join and doubles as auto join's confirmation; `CameraCoordinator`, owned by `AppCore`, is the
  standalone `Open Camera` command. See [features/camera.md](features/camera.md) and
  [features/calendar.md](features/calendar.md).
- **HUDs** are separate, because a dialog asks and a HUD reports: `MessageHUDController` (the pill) and
  `VolumeHUDController` (the level box), both over a shared `HUDPresenter` that owns the
  one-at-a-time, auto-dismiss and fade policy. See [ui.md](ui.md#dialogs--hud).

`NSAlert` is never used, and that is load-bearing. Appearance is a setting: `AppCore.applyAppearance()`
assigns `NSApp.appearance` from `AppSettings.appearance`, and `.system` assigns `nil` so AppKit follows
macOS by itself. Nothing else in the app sets an appearance. Animations take the same shape:
`AppCore.applyMotion()` projects `AppSettings.animationsEnabled` into `Motion.isEnabled` and re-points
every live `AnimatedPanel` (see [ui.md](ui.md#non-negotiable-invariants)), and `AppCore.applyIconStyle()`
projects `AppSettings.iconStyle` into `IconCache.style` (see [ui.md](ui.md#icon-pack)).

## Processes

Tinycast is the main app and the processes it starts, and each of those links to the main app alone.

| Process               | Runs                                                              | Lives                                  |
| --------------------- | ----------------------------------------------------------------- | -------------------------------------- |
| Main app              | every engine and every long-lived store                           | launch to quit                         |
| Settings              | this executable again, `--role=settings`                          | while its window is open               |
| `ClipboardTextHelper` | text recognition and the thumbnail for one clipboard item         | one item                               |
| `FileIndexHelper`     | the File Search crawl                                             | one crawl                              |
| Tinycast Dictation    | the dictation model adapters, as a helper app with its own bundle | until the idle delay or a model switch |

Three rules decide where new work runs:

- **A role is Tinycast.** A `ProcessRole` runs this executable, so it holds Tinycast's privacy grants,
  Keychain items, preferences and `AppPaths`, and only Tinycast's own code runs in one. Code from anyone
  else, an extension's above all, never runs as a role, so it never holds Tinycast's identity. How
  extensions run is not decided yet.
- **The main app is the hub.** Only it runs engines. Another process asks it for work and mirrors what it
  knows, and never talks to a third: Settings sends extension changes to the main app rather than running
  them.
- **A process lives as long as its work.** On macOS 27 a long-lived process keeps the pages its freed
  memory used, so work with a large passing peak gets a process that exits when the work ends. A headless
  Swift process also costs about 4 MB before it does anything, so always-on work joins a process that is
  already running rather than starting one of its own.

`ProcessLink.spawn` starts any executable with a typed link on its stdin and stdout, and
`App/ProcessLink+Role.swift` starts this one as a role. A role speaks this build's `Codable` types, so
both ends must be one build: `Platform/LaunchedExecutable.swift` pins the executable's file identity at
launch, and a role never starts once an update or a rebuild has replaced it; Settings then offers a
relaunch. Code built apart from Tinycast, such as an extension, declares the Tinycast API version it
supports instead.

## The Settings process

Opening Settings starts a second instance of this same executable, `--role=settings`
(`App/ProcessRole.swift`), and closing the window ends it. Process lists show it as Tinycast (Settings)
for as long as the window is open; LaunchServices has no public way to name one process apart from its
bundle, so `Platform/ProcessDisplayName.swift` sets that name through its SPI, and a macOS without it
keeps plain Tinycast. On macOS 27, malloc keeps freed small blocks dirty, so a view tree
torn down in the main app would never return its pages; a process that exits returns all of them. The
same binary means one identity: preferences, Keychain items, privacy grants and `AppPaths` are shared,
and nothing is copied.

- **Lifecycle.** `SettingsCoordinator` keeps its API. In the main app it fronts a
  `SettingsProcessController`, which spawns the child with `ProcessLink.spawn` (stdin and stdout pipes,
  `Platform/ProcessLink.swift`, framed by `Platform/PipeFraming.swift`) and serves it. In the child it
  fronts the `SettingsWindowController`. The child's `SettingsApp` carries the menus, sets `.regular`
  before any window exists, and ends on the window's close or on the main app's end of stream. On
  close, Settings sends pending edits and waits asynchronously for the main app to acknowledge them.
  It exits after one second if the peer stalls. The main app reopens Settings when an outstanding
  show request reaches a closing process.
- **Focus.** macOS lets only the app the user just addressed bring another forward, so the child asks
  (`.activate`) once its window is up and the main app calls `activate(from:)`.
- **State.** The main app owns shortcut writes, deletion of launcher items and their cross-store
  references, and backup work. Settings asks for those changes and reads the resulting state through
  the mirror. The live clipboard database opens only in the main app. For other preferences,
  `App/SharedStateMirror.swift` sends
  Settings' pending defaults edits to the main app, which orders them with its own edits and
  acknowledges the resulting values. Dictionary edits merge by entry. Scalar values and encoded
  collections are atomic. Settings reapplies later unacknowledged edits when a value arrives, so a
  pane keeps the user's latest input while the main app catches up. Each process writes the
  resulting values into its defaults before its stores reload, since cfprefsd delivers writes late.
  Quicklinks, chat presets, custom quick actions, the login item and the learning stores (ranking,
  frequent emoji, calculator history) are domains, re-read whole; the ranking's write settles before the
  peer is told. A store a pane writes outside defaults must be a `SharedDomain`, or the main app writes
  its stale copy back; `AppCore` binds every case in a switch, so a new one fails to build until both
  roles can re-read it.
  Every `reload()` assigns only what differs, so side effects still run from the main app's `track` sinks,
  and `AppSettings.reload()` switches over every `AppSettingsKey`, so a new key fails to build until it
  is adopted.
- **Work only the main app can do** goes as a `SettingsAction`: the palette editors, rooms, running a
  layout, iCloud Sync, the file index, dictation models, the settings file, updates and Support. MCP
  edits, authentication, backup operations and extension changes use the same request and reply
  lifecycle. Losing the connection finishes all pending requests. What only the main app
  knows comes back as `MainAppStatus`, rebuilt under observation and sent when it changes. Panes reach
  both through `MainAppLink` in the environment.
- **Shortcut recording** pauses the main app's engines through `HotKeyManager.isRecordingInSettings`; the
  child's own `HotKeyManager` is loaded but never activated, so it registers nothing.
- **Extensions** never run in Settings. `ExtensionLibrary` reads the catalog from disk and mirrors the
  rest. The main app answers extension library requests. Native extension execution can have its own
  process and permission model without changing how Settings talks to the main app.

## Observation

39 types are `@MainActor @Observable`. Nothing uses `ObservableObject` or `@Published`, and views read
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
`withObservationTracking`'s `onChange` is a **willSet** hook (it fires before the write lands and is
one-shot), so the closure defers the re-read into a `Task` and re-arms the tracking there. Both halves
are required; removing the `Task` reads the old value.

## Concurrency

The target builds in **Swift 6 language mode**, so data-race violations are hard errors. Almost
everything is `@MainActor`; cross-actor model types are `Sendable`. Heavy and IO-bound work (the app
scan, image decode, the settings-pane scan, shell execution, the FX rate fetch) is pushed off-main as
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

The folder layout is the layering above, made navigable: one folder per feature, each holding
everything that feature owns.

```
Tinycast/
  App/              @main, AppDelegate, AppCore (the composition root), ProcessRole, SettingsApp,
                    SharedStateMirror
  DesignSystem/     Theme (the token source), KeyCapChip, Tooltip, SymbolImage,
                    GlassEffectView, PopoverMenu, SettingsComponents, Scrolling/, Interaction/
  Platform/         system shims: Permissions, LaunchAtLogin, InputSourceSwitcher, ScreenTarget,
                    AppDisplayName,
                    NotificationToken, AppPaths, Signposts, HealthTicker, Memo, ActivationPolicy,
                    PipeFraming, ProcessLink, ProcessDisplayName, LaunchedExecutable,
                    Images/, Compression/
  Resources/        RaycastRuntime.generated.js, the embedded extension runtime
  Palette/          the palette shell: PalettePanel, PaletteWindowController, RootPaletteView,
                    the PaletteScreen protocol, PaletteCoordinator, PaletteState, PaletteMode
  Windows/          the non-palette AppKit surfaces: AppWindowController, Dialog/, HUD/, About/
  Assets.xcassets/  the app icon and the bundled image sets some catalog symbols resolve to
  Migrations/       one-shot repairs, each deleted after one stable release (migrations.md)
  Features/
    PaletteRowIndex.swift   the flat selection index, palette-owned, so it sits at the top
    Launcher/ Clipboard/ Calculator/ Calendar/ Emoji/ FileSearch/ MenuSearch/ Notes/
    Quicklinks/ Snippets/ Uninstall/ SystemActions/ CustomCommands/ HotKeys/ Backup/
    WindowManagement/ Onboarding/ Updates/ Support/ AI/ Settings/
    Extensions/
        Model/      pure: the harness inputs
        Service/    effects: stores, monitors, runners, AppKit glue
        UI/         screens, views, and the feature's coordinator
        Settings/   the feature's own panes
    Settings/       the Settings shell only: SettingsCoordinator, its window and process controllers,
                    the main app link, the root/sidebar/detail views, the chrome,
                    navigation types, SettingsTab, AppSettings, AppSettingsKey, the settings file
                    (Model/, Service/, SettingsFileSchema), and Panes/ for the two panes no feature
                    owns
Tests/              the standalone harnesses, one Swift file each
Scripts/            run-tests.sh, the two data generators, packaging, formatting, editor setup
```

A larger feature splits into all four sub-folders; a small one stays flat, as `Onboarding/` does. `HotKeys/` has no `Settings/` because its Shortcuts pane is part of the Settings
shell rather than the feature.

Every `SettingsTab` maps to one `…SettingsView`, and each is a stock `Form` with
`.formStyle(.grouped)` (see [ui.md](ui.md#settings)). A pane lives with its feature; only a pane no
feature owns (General, Permissions) lives in `Settings/Panes/`. The four launcher-category panes
(Applications, System Settings, System Actions, Commands) are thin wrappers over the shared
`LauncherItemsSection`; Apple Shortcuts pairs its feature switch with the same `LauncherItemsList`.

`SettingsTab` and `SettingsSection` both identify by the case itself, never by an index. A selectable
`List` flattens section and row IDs into one namespace, so overlapping `Int` IDs make SwiftUI drop
whole sidebar groups; `Tests/SettingsHistoryTests.swift` pins the two namespaces apart.
