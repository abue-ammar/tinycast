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

## Pinyin

An entry whose name carries a Han character also matches on its Latin reading. `Pinyin.aliases`
(`Core/Pinyin.swift`) returns the full reading and the per-character initials, and `AppEntry.init`
attaches them to every entry it builds — so applications, System Settings panes, snippets, system
commands and custom commands all get them from one place rather than each call site. 微信 answers to
`weixin` and to `wx`, 网易云音乐 to `wangyiyunyinyue` and `wyyyy`. A name in no Han script costs one
scalar range check and gets no alias.

Readings come from `CFStringTokenizer`'s Latin transcription rather than
`kCFStringTransformMandarinLatin`, because the tokenizer segments words before reading them and so
resolves a polyphone in context where a character-at-a-time transform cannot: 音乐 is `yinyue`, not
`yinle`, and 地图 is `ditu`, not `detu`.

Initials need one syllable per character, but the transcription arrives word-grouped
(`wangyi yun yinyue`), so `Pinyin.syllables` cuts it against the syllable inventory macOS itself
transliterates to. Pinyin is ambiguous on its own — `xian` is 西安 or 险 — and it is the known
character count that makes the boundaries decidable; the cut is longest-first, so `pingan` is 平安. A
reading that won't cut still searches in full, it just contributes no initial-letter shortcut, and a
one-letter initial is dropped rather than matching everything it leads.

A reading is a weaker claim on the query than the name itself, so `AppEntry` keeps the two apart:
`literalAliases` holds literal strings (a snippet's keyword) and scores in the name's own tiers,
while `romanizedAliases` is scored `FuzzyMatch.romanizedPenalty` lower — half the gap between two
tiers, and deliberately more than `LauncherRankingStore.maximumBoost`, so learned ranking cannot lift
a reading back over the literal match it sits under. A reading therefore lands under the literal
match of the same kind without falling past the kind below it: typing `safari` can never lose Safari
to something whose pinyin spells it, but `wx` still reaches 微信 ahead of a longer name that merely
starts with those letters. Names are read once per scan, off-main with the rest of `AppIndex.scan`.

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
order is applications, System Settings, system commands, then built-in/custom commands; the sectioned
view filters in that same order so the visible rows remain identical to the flat selection index.
Search, favorites, visibility and learned ranking work through the normal `AppEntry` path. Dedicated
global hotkeys are deliberately out of scope.

Public AppKit, CoreAudio and workspace APIs are preferred. Commands without a stable public macOS API
use fixed system tools, Apple Events, Accessibility, or a dynamically resolved Bluetooth power API.
Those routes run only on explicit activation. Automation, Accessibility or Bluetooth permission is
requested at first use, and denial produces an alert linking to the relevant System Settings pane.
Tinycast remains locked to dark appearance even when Toggle System Appearance changes macOS.

Restart, Shut Down, Log Out, Empty Trash and Quit All Applications confirm before execution, with
Return assigned to Cancel. Every dialog is Tinycast's own: confirmations, failure reports and the Set
Volume slider all render through `ModalWindowController` rather than an `NSAlert`
(see [ui.md](ui.md#modals--hud)). Volume and mute commands also show Tinycast's transient volume HUD,
since macOS only draws its own for real media keys.

A command whose effect is invisible reports back through the same HUD rather than finishing silently:
`SystemCommandRunner.run` returns a `SystemCommandFeedback` naming the state it landed in
(`Trash Emptied`, `Hidden Files Shown`, `Dark Appearance`, `Bluetooth Off`, `3 Disks Ejected`), and
`AppCore` shows it. Commands that are their own confirmation, such as Show Desktop, Hide Others, Quit All and the
power actions, return nothing.

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
> is meaningless. It compiles the real `Core/Pinyin.swift`, which must therefore stay Foundation-only.

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
