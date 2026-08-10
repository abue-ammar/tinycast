# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the user's search scopes, and dedups by bundle ID (the
earliest scope wins).

## Invariants

- **`AppEntry.Kind` is the only thing that says what an entry is.** One case per launcher section, per
  `VisibilityStore` category and per Settings pane — never re-derive a category by sniffing an entry ID.
  A new category means a new case, a slice in `AppIndex.publishEntries()`, and the matching filter in
  `LauncherList.rows`, in that order.
- **`Model/SearchRelevance.swift` is Foundation-only and pure**, so `fuzz-test` compiles the shipped
  scorer. It owns both `FuzzyMatch` and the field bands.
- **Searchable fields stay separate** — display name, Spotlight alternate names, bundle id and executable
  name are never flattened into one string, because the field is what picks the band. A new searchable
  field means a new `Band` case and a `consider` call, in priority order.
- **`Model/SearchScopes.swift` and `Model/LauncherRankingStore.swift` are pure too** — the ranking store
  takes its clock via `now` and its path via `fileURL`, for `scopes-test` and `ranking-test`.

## Search scopes

`SearchScopes` (`Launcher/Model/SearchScopes.swift`) owns the paths; the list is user-editable in General
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

## Searchable fields

An app is matched on four fields kept deliberately separate — flattening them into one string would
lose the thing that decides the ranking. `SearchRelevance.score` evaluates each independently and the
strongest one becomes the entry's base relevance:

| Band | Field                                   | Match strength                                    |
| ---- | --------------------------------------- | ------------------------------------------------- |
| 5    | display name (plus a snippet's keyword) | literal — exact / prefix / word-start / substring |
| 4    | Spotlight alternate names               | literal                                           |
| 3    | display name                            | subsequence                                       |
| 2    | Spotlight alternate names               | subsequence                                       |
| 1    | bundle identifier                       | literal only                                      |
| 0    | executable name (`CFBundleExecutable`)  | literal only                                      |

The arithmetic is what makes that table binding. A band's offset is `rawValue * bandStride`, and:

```
bandStride            = 10 × FuzzyMatch.maximumScore   = 1,000,000
FuzzyMatch.maximumScore                                =   100,000
LauncherRankingStore.maximumBoost                      =     4,500
```

So a field can never reach the band above it — the widest possible fuzzy score is a tenth of a stride —
and the learned frecency boost is two orders of magnitude below a stride, which is what keeps learning
reordering *within* a tier and never across one. Those three numbers are a contract, not a tuning
parameter.

A _literal_ hit on a weaker field outranks a _subsequence_ hit on a stronger one. That is the point of
the split: an alias the vendor actually declared (`Codex` for ChatGPT) must beat the incidental
c-o-d-e…x scattered through an unrelated app's name, while a real prefix hit on a display name still
wins outright.

Identifier fields never subsequence-match — reverse-DNS text is a subsequence of nearly every short
query (`cop` ⊂ `com.apple.Photos`), which would change _which_ apps appear rather than just their
order. For the same reason a bundle id is matched with its leading component stripped
(`apple.Photos`, not `com.apple.Photos`): `com` alone prefixes almost every installed app. The full id
still matches exactly, so a pasted identifier resolves.

### Alternate names

`SpotlightNames` reads `kMDItemAlternateNames` — the aliases macOS itself knows an app by, which no
Info.plist key exposes: `iBooks` for Books, `iCal` for Calendar, `Address Book` for Contacts,
`System Preferences` for System Settings, `browser` / `浏览器` / `사파리` for Safari. `MDItem.h` exports
no constant for the attribute, so it is named directly.

Spotlight mixes junk in with the real aliases, and `SearchFields.usableAlternateNames` (pure, covered
by the harness) drops it: every bundle lists its own `<Name>.app` file name, several system apps ship
untranslated `ALTERNATE_NAME_1` placeholders, and some just repeat the display name. Indexing those
would make `app` match the entire index.

A Spotlight round trip costs ~0.8 ms per bundle cold — 76 ms over the default scopes — and the scan
reruns on every launcher open, so `SpotlightNames.Cache` memoizes per bundle path and re-reads only
when the bundle's modification date moves, taking later passes to ~0.2 ms. Each pass is seeded from
the last and keeps only what it looked at, so uninstalled apps fall out instead of accumulating.
`.appex` Settings panes carry no alternate names, so `SettingsPaneScanner` doesn't ask.

Selecting a launcher result records every prefix of the submitted query, so choosing WhatsApp for
`wha` also teaches `w` and `wh`. Direct hotkeys and empty-query favorites do not affect learned
ranking. Learned data stays on device in `launcher-ranking.json`; a result that has learned ranking
offers a per-item reset in its Actions menu, and users can clear all learned ranking in General
Settings.

Rankings are memoized one query deep and keyed by the ranking store's revision, so a launch or reset
invalidates the cached order. `rank` resolves the whole learned table for a query up front via
`boosts(query:)` — one fold and one clock read per pass, not per candidate.

## System actions

`SystemActionCatalog` is a Foundation-only inventory of the macOS actions Tinycast exposes. Its
stable entry IDs, labels, symbols and confirmation policy are covered by
`Tests/system-action-test.swift`; platform side effects live separately in `SystemActionRunner`.
`SystemActionCoordinator.runSystemAction(id:)` remains the one execution funnel — shared by palette activation and a
global hotkey — hiding the floating palette before any confirmation or value dialog and surfacing
permission-aware failures. With the palette closed it targets the frontmost app, so Hide Others and
Quit All act on the same window a palette launch would have.

System actions occupy their own launcher section and their own Settings pane. The empty-query publication
order is applications, System Settings, quicklinks, snippets, system actions, window commands, custom
commands, then built-in commands; the sectioned view filters in that same order so the visible rows remain
identical to the flat selection index.
Search, favorites, visibility and learned ranking work through the normal `AppEntry` path, and every
action is bindable to a global shortcut from Settings › System Actions
(see [hotkeys.md](hotkeys.md)).

Public AppKit, CoreAudio and workspace APIs are preferred. Actions without a stable public macOS API
use fixed system tools, Apple Events, Accessibility, or a dynamically resolved Bluetooth power API.
Those routes run only on explicit activation. Automation, Accessibility or Bluetooth permission is
requested at first use, and denial produces an alert linking to the relevant System Settings pane.
Tinycast remains locked to dark appearance even when Toggle System Appearance changes macOS.

Restart, Shut Down, Log Out, Empty Trash and Quit All Applications confirm before execution: ↵ runs
the action, Escape cancels. Every dialog is Tinycast's own: confirmations, failure reports and the Set
Volume slider all render through `DialogController` rather than an `NSAlert`
(see [ui.md](../ui.md#dialogs--hud)). Each confirmation carries the action's own icon — Restart shows
`arrow.clockwise`, Empty Trash `trash.slash` — so the dialog is recognizably about the row that
opened it. Volume and mute actions also show Tinycast's transient volume HUD, since macOS only draws
its own for real media keys. Volume Up/Down walk a 5% grid (`VolumeLevel.stepped`, covered by
`Tests/volume-test.swift`): an off-grid level snaps to the next line rather than past it, so from 37%
up lands on 40% and down on 35%, and repeated presses stay on round numbers.

An action whose effect is invisible reports back through a pill (`MessageHUDController`, the same one
Custom Commands and Snippets confirm through) rather than finishing silently:
`SystemActionRunner.run` returns a `SystemActionFeedback` naming the state it landed in
(`Trash Emptied`, `Hidden Files Shown`, `Dark Appearance`, `Bluetooth Off`, `3 Disks Ejected`), and
`AppCore` shows it with a `DialogTone` derived from the feedback's `isNoOp` flag: `.success` when
something actually changed, `.neutral` when there was nothing to do, shown as the glyph trailing the
message rather than a per-action icon, since the message already names the state. Actions that are
their own confirmation, such as Show Desktop, Hide Others,
Quit All and the power actions, return nothing. Volume and mute are the one case that stays on the
palette's own box HUD, since that one has an actual level and number to show, not just a message.

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

`WindowCommandCatalog` supplies the 30 window actions as a static slice, published as a whole by
`AppIndex.setWindowCommandsVisible(_:)` and shown under a "Window Management" section. Like system
actions they carry dedicated global hotkeys (`AppEntry.hotKeyAction` returns `.windowCommand(id:)`),
so launcher rows render keycaps for them. Their per-command shortcut and visibility controls live in
Settings › Window Management rather than a launcher-category pane of their own — the same call already
made for snippets. The feature ships off. See
[window-management.md](window-management.md).

## Quicklinks

`QuicklinkStore` supplies its slice the same way custom commands do, sorted pinned-first then
alphabetically by `Quicklink.precedes`. Only the name is indexed — a URL is a subsequence of nearly
any query — and a per-item "show in root search" flag filters the slice before it is published. The
four Quicklinks commands are dropped from the built-in slice in the same publish while the feature is
off, so a toggle can't leave the section and its commands out of step. See
[quicklinks.md](quicklinks.md).

## Custom commands

`CustomCommandStore` supplies user-authored entries to `AppIndex` without joining the off-main
application scan. Custom commands are their own alphabetized section ahead of the built-in Commands
section, and reuse fuzzy ranking, favorites, visibility, keycap rendering and the launcher's flat
selection.

Only the display name is indexed. Activation resolves the stable UUID through the store and dispatches
to `ShellCommandRunner`; see [custom-commands.md](custom-commands.md) for persistence, hotkeys and
execution semantics.

> **Invariant:** `Tests/fuzz-test.swift` compiles the real `Tinycast/Features/Launcher/Model/SearchRelevance.swift`, so
> that file must stay Foundation-only and pure. There is no copy of the scorer to keep in sync.

The ranking harness covers prefix learning, frequency/recency scoring, persistence, and both reset
paths; see the command in `development.md`.

Launcher icons use a persistent 32 MB cost-capped `NSCache`. Fitted file-row icons use a separate
transient 8 MB cache that is purged when its palette list disappears (`IconCache`).

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
  the app it just quit _was_ `previousApp`.
- **Quit All Applications** a system action. `AppLauncher.quitAllTargets()` is the
  policy (every `.regular` app except Finder — `terminate()` only relaunches it — and Tinycast,
  excluded by PID because About/Settings temporarily flips it to `.regular`). `SystemActionCoordinator.quitAllApps()`
  resolves that list **once**, confirms it with an `NSAlert`, then terminates exactly what was
  confirmed. The palette hides before the alert — it is a floating panel and would sit above it.

Both quits are graceful `NSRunningApplication.terminate()`, so an app with unsaved work still puts up
its own save sheet.

The ⌘K menu samples `isRunning` **once, when it opens** (`RootPaletteView.openActions()`), so an app
launching or quitting elsewhere can't add or drop the Quit row while the menu is up — the same freeze
the rest of the menu already has ([palette.md](palette.md)). Only `LauncherList` observes
`RunningAppsMonitor` live, for the running dot.
