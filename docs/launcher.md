# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the standard `/Applications` dirs, and dedups by bundle ID
(first dir wins).

`FuzzyMatch.score` is a tiered scorer: exact → prefix → substring / word-start → subsequence with
consecutive / word-boundary bonuses. Rankings are memoized one query deep.

> **Invariant:** `Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from
> `Tinycast/Core/AppIndex.swift`. If you change the scoring in one, mirror it in the other or the test
> is meaningless.

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
