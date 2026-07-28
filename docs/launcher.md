# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the standard `/Applications` dirs, and dedups by bundle ID
(first dir wins).

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

> **Invariant:** `Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from
> `Tinycast/Core/AppIndex.swift`. If you change the scoring in one, mirror it in the other or the test
> is meaningless.

The ranking harness covers prefix learning, frequency/recency scoring, persistence, and both reset
paths; see the command in `development.md`.

Icons go through a count-capped `NSCache` (`IconCache`).

## Quitting apps

`RunningAppsMonitor` (live from `NSWorkspace` launch/terminate notifications) drives both the row's
running dot and the availability of the quit actions:

- **Quit Application** — the last row of an app's ⌘K Actions menu, shown only while that app is
  running, also bound to **⌘↵** on the selected row. `AppLauncher.quit(bundleID:)` terminates every
  instance of the bundle and reports whether anything was running; the palette only dismisses when
  something was, and it restores focus unless the app it just quit *was* `previousApp`.
- **Quit All Applications** — a `CommandRegistry` command. `AppLauncher.quitAllTargets()` is the
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
