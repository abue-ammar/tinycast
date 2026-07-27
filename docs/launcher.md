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
  something was.
- **Quit All Applications** — a `CommandRegistry` command. `AppLauncher.quitAllTargets()` is the
  policy (every `.regular` app except Finder — `terminate()` only relaunches it — and Tinycast
  itself); `quitAll()` terminates that list.

Both quits are graceful `NSRunningApplication.terminate()`, so an app with unsaved work still puts up
its own save sheet.
