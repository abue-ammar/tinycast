# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the user's search scopes, and dedups by bundle ID (the
earliest scope wins).

## Search scopes

`SearchScopes` (`Core/SearchScopes.swift`) owns the paths; the list is user-editable in General
Settings and persisted as `AppSettings.searchScopes`. A scope is either a directory or a single `.app`
bundle, stored tilde-abbreviated so the UI reads cleanly and a settings backup stays portable.

Enumeration is **flat** — one `contentsOfDirectory` per scope, no recursion. A nested folder such as
`/Applications/Adobe` is indexed by adding it as its own scope, which keeps the list honest: what it
shows is exactly what is scanned. (A one-level nested walk was measured against the flat list over the
real default set: same 96 apps, same ~0.5 ms once `Bundle()` metadata reads are counted.)

The defaults cover `/Applications` and `/System/Applications` plus their `Utilities` folders,
`/System/Library/CoreServices/Applications`, the cryptex apps under
`/System/Volumes/Preboot/Cryptexes/App/System/Applications` (this is the only place Safari really
lives — `/Applications/Safari.app` is a symlink flagged hidden, so `.skipsHiddenFiles` never sees it),
`~/Applications`, and `/System/Library/CoreServices/Finder.app`.

Finder ships as an individual bundle scope rather than by adding `/System/Library/CoreServices`, which
holds ~120 background-agent bundles. There is no reliable way to filter those: `LSUIElement`,
`LSBackgroundOnly` and "declares no icon" each also exclude legitimately launchable apps — Raycast,
Stats, Tinycast itself, Mission Control, Siri, Time Machine, Screenshot, System Information, Font
Book. Don't reintroduce such a heuristic.

`AppIndex.start(settings:)` observes `$searchScopes`, so an edit re-indexes immediately; overlapping
refreshes collapse into a single trailing scan.

`FuzzyMatch.score` is a tiered scorer: exact → prefix → substring / word-start → subsequence with
consecutive / word-boundary bonuses. `LauncherRankingStore` then adds a bounded, query-specific
frecency boost (frequency plus decaying recency). The boost can reorder results within a relevance
tier but cannot make a weaker match kind beat a stronger one. Matching strips invisible Unicode
format scalars first, since app metadata can contain bidi/zero-width markers before the visible name.

Selecting a launcher result records every prefix of the submitted query, so choosing WhatsApp for
`wha` also teaches `w` and `wh`. Direct hotkeys and empty-query favorites do not affect learned
ranking. Learned data stays on device in `launcher-ranking.json`; a result that has learned ranking
offers a per-item reset in its Actions menu, and users can clear all learned ranking in General
Settings.

Rankings are memoized one query deep and keyed by the ranking store's revision, so a launch or reset
invalidates the cached order. `rank` resolves the whole learned table for a query up front via
`boosts(query:)` — one fold and one clock read per pass, not per candidate.

## System commands

`SystemCommandCatalog` is a Foundation-only inventory of the macOS actions Tinycast exposes. Its
stable entry IDs, labels, symbols and confirmation policy are covered by
`Tools/system-command-test.swift`; platform side effects live separately in `SystemCommandRunner`.
`AppCore.runSystemCommand` remains the one execution funnel, hiding the floating palette before any
confirmation or value dialog and surfacing permission-aware failures.

System commands occupy their own launcher and Shortcuts Settings category. The empty-query publication
order is applications, System Settings, snippets, system commands, window commands, custom commands,
then built-in commands; the sectioned view filters in that same order so the visible rows remain
identical to the flat selection index.
Search, favorites, visibility and learned ranking work through the normal `AppEntry` path. Dedicated
global hotkeys are deliberately out of scope.

Public AppKit, CoreAudio and workspace APIs are preferred. Commands without a stable public macOS API
use fixed system tools, Apple Events, Accessibility, or a dynamically resolved Bluetooth power API.
Those routes run only on explicit activation. Automation, Accessibility or Bluetooth permission is
requested at first use, and denial produces an alert linking to the relevant System Settings pane.
Tinycast remains locked to dark appearance even when Toggle System Appearance changes macOS.

Restart, Shut Down, Log Out, Empty Trash and Quit All Applications confirm before execution: ↵ runs
the action, Escape cancels. Every dialog is Tinycast's own: confirmations, failure reports and the Set
Volume slider all render through `ModalWindowController` rather than an `NSAlert`
(see [ui.md](ui.md#modals--hud)). Volume and mute commands also show Tinycast's transient volume HUD,
since macOS only draws its own for real media keys.

A command whose effect is invisible reports back through a pill (`HUDWindowController`, the same one
Custom Commands and Snippets confirm through) rather than finishing silently:
`SystemCommandRunner.run` returns a `SystemCommandFeedback` naming the state it landed in
(`Trash Emptied`, `Hidden Files Shown`, `Dark Appearance`, `Bluetooth Off`, `3 Disks Ejected`), and
`AppCore` shows it with a `ModalKind` derived from the feedback's `isNoOp` flag: `.success` when
something actually changed, `.info` when there was nothing to do, shown as the pill's leading status
dot rather than a per-command icon, since the message already names the state. Commands that are
their own confirmation, such as Show Desktop, Hide Others,
Quit All and the power actions, return nothing. Volume and mute are the one case that stays on the
palette's own square HUD, since that one has an actual level to show, not just a message.

**Nothing-to-do is an outcome, not a failure.** Empty Trash asks Finder for `count items of trash`
first and reports `Trash Is Already Empty`, because Finder raises an error when told to empty an empty
Trash. The count deliberately goes through Finder instead of reading `~/.Trash` directly: that folder
is TCC-protected, so an unprivileged read fails in a way indistinguishable from "empty", which would
silently skip a real empty. Eject All Disks, Dismiss Notifications and Unhide All Apps report the same
way when there is nothing to act on. Volume and mute fall back to the output's preferred stereo channels when the device exposes
no master element (common on HDMI), and Toggle Mute parks the level at zero when there is no mute
control at all. Multi-disk ejection excludes internal and network volumes, treats a sibling volume
that the same physical eject already unmounted as done, and reports remaining failures together.
Preference-backed toggles refuse to write when the current value can't be read, and notification
dismissal matches Accessibility subroles rather than English labels.

## Window commands

`WindowCommandCatalog` supplies the 29 window actions as a static slice, published as a whole by
`AppIndex.setWindowCommandsVisible(_:)` and shown under a "Window Management" section. Unlike system
commands they **do** carry dedicated global hotkeys (`AppEntry.hotKeyAction` returns
`.windowCommand(id:)`), so launcher rows render keycaps for them. Their per-command shortcut and
visibility controls live only in Settings › Window Management, not in Settings › Shortcuts — the same
call already made for snippets. The feature ships off. See
[window-management.md](window-management.md).

## Custom commands

`CustomCommandStore` supplies user-authored entries to `AppIndex` without joining the off-main
application scan. Custom commands are their own alphabetized section ahead of the built-in Commands
section, and reuse fuzzy ranking, favorites, visibility, keycap rendering and the launcher's flat
selection.

Only the display name is indexed. Activation resolves the stable UUID through the store and dispatches
to `ShellCommandRunner`; see [custom-commands.md](custom-commands.md) for persistence, hotkeys and
execution semantics.

> **Invariant:** `Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from
> `Tinycast/Core/AppIndex.swift`. If you change the scoring in one, mirror it in the other or the test
> is meaningless.

The ranking harness covers prefix learning, frequency/recency scoring, persistence, and both reset
paths; see the command in `development.md`.

Icons go through a count-capped `NSCache` (`IconCache`).

## Reveal in Finder

Application and System Settings results expose **Show in Finder** in their ⌘K Actions menu and on
**⌘↵**. Synthetic command results have no filesystem location, so neither the menu row nor the
shortcut is available for them. `AppEntry.canRevealInFinder` is the one rule both the menu row and
the key handler read, so the advertised chord can't drift from the behavior.

## Quitting apps

`RunningAppsMonitor` (live from `NSWorkspace` launch/terminate notifications) drives both the row's
running dot and the availability of the quit actions:

- **Quit Application** — the last row of an app's ⌘K Actions menu, shown only while that app is
  running, also bound to **⌃⇧Q** on the selected row. The chord guard mirrors the menu row's
  condition (an `.application` entry that `RunningAppsMonitor` reports running) so the key never
  swallows a press it won't act on, and it's skipped in the compact bar, which shows no selection.
  `AppLauncher.quit(bundleID:)` terminates every instance of the bundle and reports whether
  anything was running; the palette only dismisses when something was, and it restores focus unless
  the app it just quit *was* `previousApp`.
- **Quit All Applications** a system command. `AppLauncher.quitAllTargets()` is the
  policy (every `.regular` app except Finder — `terminate()` only relaunches it — and Tinycast,
  excluded by PID because About/Settings temporarily flips it to `.regular`). `AppCore.quitAllApps()`
  resolves that list **once**, confirms it with an `NSAlert`, then terminates exactly what was
  confirmed. The palette hides before the alert — it is a floating panel and would sit above it.

Both quits are graceful `NSRunningApplication.terminate()`, so an app with unsaved work still puts up
its own save sheet.

The ⌘K menu samples `isRunning` **once, when it opens** (`RootPaletteView.openActions()`), so an app
launching or quitting elsewhere can't add or drop the Quit row while the menu is up — the same freeze
the rest of the menu already has ([palette.md](palette.md)). Only `LauncherList` observes
`RunningAppsMonitor` live, for the running dot.
