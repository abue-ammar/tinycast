# Testing and verification

How to check that a change holds up. Tinycast has no XCTest target and no UI tests: the automated half
is a set of standalone harnesses, and the manual half is the sweep at the bottom of this file.

## Definition of done

The mechanical bar, in one place so it cannot drift. All five pass before a change is finished.

| Check | Command |
| --- | --- |
| The harnesses | `./Scripts/run-tests.sh` |
| Lint | `./Scripts/lint.sh` |
| Pure-layer purity | `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` |
| A clean build | `xcodebuild … -configuration Debug CODE_SIGNING_ALLOWED=NO`, zero **new** warnings |
| Docs still true | any doc your change made wrong, fixed in the same commit |

CI runs the first two and does not build the app at all — so the build, the purity grep and the docs
are on you. Each is expanded below; the manual sweep at the end of this file is the sixth, judged by
what you touched.

## The harnesses

```sh
./Scripts/run-tests.sh              # all of them
./Scripts/run-tests.sh calc-test    # just one, while iterating
```

The script is the **only** place the harness set is written down — CI runs exactly this, so the two
cannot drift. Adding a harness means adding one `run` line.

Each harness compiles the **shipped sources** it guards rather than a copy of them, which is what makes
the pure-layer boundary real: a harness that stops *compiling* means AppKit or SwiftUI has leaked into a
`Model/` folder, or an effect has leaked into a decision. That is a more common failure than a broken
assertion, and it is the more important one.

Never join a compile to its run with `&&` in a `set -e` script. `set -e` is specified to ignore a
failing command in a non-final AND-OR list member, so `swiftc … && /tmp/x` swallows a compile error and
the script sails on. CI reported success over a harness that had not compiled for twenty-five phases
because of exactly this; `run-tests.sh` keeps the two steps separate and records both kinds of failure.

### What to run when

If a change touches anything in the right column, the harness on the left is mandatory.

| Harness | Guards |
| --- | --- |
| `fuzz-test` | `Launcher/Model/SearchRelevance.swift` |
| `file-search-test` | `FileSearch/Model/`, plus the shared `FuzzyMatch` scorer |
| `file-search-session-test` | serialized query execution, debounce coalescing and cancellation |
| `ranking-test` | `Launcher/Model/LauncherRankingStore.swift` |
| `scopes-test` | `Launcher/Model/SearchScopes.swift` |
| `calc-test` | all of `Calculator/Model/` |
| `clipboard-test` | `Clipboard/Model/ClipboardStore.swift` |
| `emoji-test` | `Emoji/Model/EmojiCatalog.swift`, `EmojiGridGeometry.swift`, the generated data |
| `palette-selection-test` | `Features/PaletteRowIndex.swift` |
| `palette-placement-test` | `DesignSystem/Theme.swift`, `Palette/PalettePlacement.swift` |
| `hotkey-test` | `HotKeys/Model/DoubleTapModifier.swift`, `DoubleTapDetector.swift` |
| `callout-test` | `DesignSystem/Theme.swift`, `HotKeys/UI/CalloutPlacement.swift` |
| `system-action-test` | `SystemActions/Model/SystemAction.swift` |
| `volume-test` | `SystemActions/Model/VolumeLevel.swift` |
| `window-command-test` | `WindowManagement/WindowCommand.swift`, `WindowLayout.swift`, `WindowActionMemory.swift` |
| `custom-command-test` | `CustomCommands/Model/CustomCommand.swift`, `Service/ShellCommandRunner.swift` |
| `uninstall-test` | all five pure files in `Uninstall/Model/` |
| `quicklink-test` | all four files in `Quicklinks/Model/` |
| `snippets-test` | all of `Snippets/Model/` and `Snippets/Service/`, plus `Platform/HealthTicker.swift` |
| `raycast-test` | `Backup/Model/RaycastFormat.swift`, `RaycastV1Decoder.swift`, `Service/Gunzip.swift` |
| `settings-backup-test` | `Settings/AppSettingsKey.swift`, `Backup/Model/SettingsBackupCoverage.swift` |

A harness that passed before a change passes after it. There is no "I'll fix it next commit" and no
commenting out a case. If a change genuinely invalidates an assertion, the assertion is rewritten in the
same commit with the reason in the message.

### Purity checks

The layering rule reduces to one grep, and it must return nothing:

```sh
grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/
```

Beyond the imports, the injected-environment half is not mechanically checkable, so it is worth an eye
when touching a pure file:

- `Calculator/Model/` still takes its clock via `now`/`calendar` and its rates via `rates`
- `Uninstall/Model/`'s deciding half still receives directory **names** and a `PathFacts`, never URLs
- `HotKeys/Model/DoubleTap*` still take the clock as a parameter
- `WindowManagement/` geometry still touches no `NSScreen` and makes no AX call
- `Features/PaletteRowIndex.swift` still imports Foundation alone, despite living under `Features/`
- `Quicklinks/Model/` is still handed the home directory rather than reading it
- `FileSearch/Model/` is still handed the home directory rather than reading it

## Build and size checks

A clean build is part of the bar; CI does not build the app, so this is on you.

```sh
xcodegen generate                 # only after editing project.yml
xcodebuild build -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
  CODE_SIGNING_ALLOWED=NO
find ~/Library/Developer/Xcode/DerivedData -name "Tinycast*.app" -maxdepth 6 -print -quit
```

- Zero **new** warnings. Pre-existing ones are not your problem; new ones are.
- No `@unchecked Sendable`, `nonisolated(unsafe)` or `assumeIsolated` added without a stated reason.
- The type-checker did not time out. `LauncherList.rows` already carries an explicit annotation for
  this reason; the fix for a timeout is an annotation, not a restructure.
- Release binary under **4 MB**, and under 2% growth for an ordinary change.

### Lint

```sh
./Scripts/lint.sh
```

SwiftLint owns the rules that catch defects, including the two checkable comment rules — the
100-character cap and the ban on stacked comment lines. Errors block; warnings do not. There is no
formatter, deliberately — the configuration and the measurements behind that are in
[development.md](development.md#linting).

## Performance measurement

`Platform/Signposts.swift` emits seven intervals on the `com.tinycast.perf` subsystem: `AppCore.start`,
`AppIndex.scan`, `AppIndex.rank`, `PaletteWindowController.show`, `UninstallScanner.discover` and
`UninstallScanner.measure`, plus `FileSearchService.search`. Open the
Time Profiler or `os_signpost` instrument in Instruments and filter to that subsystem; nothing needs
recompiling.

Run the real Spotlight-backed file-search benchmark separately from the deterministic harnesses:

```sh
swiftc -O -swift-version 6 Tinycast/Platform/Signposts.swift \
    Tinycast/Features/Launcher/Model/SearchRelevance.swift \
    Tinycast/Features/FileSearch/Model/*.swift \
    Tinycast/Features/FileSearch/Service/FileSearchService.swift \
    Tests/file-search-performance.swift -o /tmp/file-search-performance
/tmp/file-search-performance
```

Every query runs twice: once on the shipped rules and once with five extra user patterns, so the output
says what the ignore list itself costs rather than only what Spotlight does.

`Signposts.interval` owns an explicit `defer` around the wrapped work on purpose. The obvious spelling
leaks the interval when the work throws, because the `.end` emit is skipped on the throw path and the
instrument then shows an interval that never closes.

Measure before optimising, and measure the same way twice. For cold launch: quit fully, relaunch, time
it three times, take the median.

### Recorded baselines

Measured at the end of the 2026 refactor, on `main`. Useful as orders of magnitude, not as contracts.

| | Value |
| --- | --- |
| Release binary | 3,655,736 B (from 3,471,592 B at the start of the refactor) |
| Resident memory | 40–80 MB in normal use; the hard ceiling is 100 MB |
| `SpotlightNames` cache | 76 ms cold, 0.2 ms warm |
| `SettingsPaneScanner` warm scan | 0.014 ms (16.5 ms cold), 52 panes |
| Largest view / owner | `RootPaletteView` 662 lines, `AppCore` 284 lines |
| Comment density | 1,653 of 27,289 source lines (6.1%) |
| `palette-selection-test` | 111,684 assertions — a tripwire: a change in this count means the row-order model moved |
| `SnippetKeywordPolicy` match | 7 µs/keystroke at 50 keywords, 59 µs at 1,000 — the `lowercased()` is 0.09 µs of it |
| `ClipboardStore.pinnedItems` | 27–127 µs per uncached search, 1,000-row window — no cache earns its invalidation yet |
| `count items of trash` | 5,000 ms against a cold Finder on an *empty* Trash, 110 ms warm — why AppleScript is detached |

Launch time, allocation counts and RSS have never been captured as numbers. The signposts are in place,
so any of them can be taken from `main` whenever a change makes it worth knowing.

## Manual regression sweep

There is no UI test suite, so this is it. Run the core sweep for any change that touches the palette;
run the scoped section for whatever feature you touched. Budget about five minutes plus three per
section.

Run against the **Debug channel** (`Tinycast Dev.app`, `com.tinycast.app.dev`). It has its own prefs,
caches, TCC grants and login item, so this cannot disturb an installed copy.

### Core

- Palette hotkey opens the launcher; pressing it again closes it; Escape closes it; clicking away closes it
- Reopening focuses the search field with an empty query, in the same position and at the same size
- Compact mode: typing expands it, and the search bar does **not** shift vertically during the swap
- Typing filters instantly; ↑/↓ move the highlight and scroll it into view without yanking the list
- ⌃N/⌃P move the highlight as ↓/↑ do; ⌃F/⌃B step the emoji grid's selection, and the caret elsewhere
- The highlight always sits on the row the footer pill describes
- With a calculation typed, the calculator card is first and is selected first
- Section headers appear in order: Favorites, Applications, System Settings, Quicklinks, Snippets,
  System Actions, Window Management, Custom Commands, Commands
- ⌘K opens the Actions menu; ↑/↓ move it, ↵ activates, Escape closes the menu rather than the palette
- While a menu is open, typing does **not** change the query and the caret is hidden
- Tab toggles launcher ↔ clipboard; bare Backspace on an empty query backs out of a sub-screen
- Launching an app focuses it; escaping the palette returns focus to the app you came from
- Paste from clipboard history lands in that app, not in Tinycast
- No flash, flicker or reflow on open, and row metrics unchanged

### Clipboard

- A copy appears at the top within about a second; an image copy records a thumbnail
- Search is correct both under and over three characters
- ⌘P pins and the highlight follows the row into Pinned; ⌘⌫ deletes; ⌘↵ copies without pasting
- ⌃X deletes the selected entry and ⌃⇧X clears the history, from the list and from an open ⌘K menu
- ⌃⇧X asks first, through Tinycast's own dialog; Cancel and Esc both leave every entry in place
- ↵ pastes into the previous app; ⌥↵ pastes without closing the palette
- A copy from an excluded app (Settings ▸ Clipboard ▸ Disabled Applications) is **not** recorded
- Password-manager copies are still not recorded

### Launcher and icons

- Every installed app appears; Settings panes appear under System Settings; running apps show the dot
- Icons render with no placeholder flash on reopen, and Settings ▸ Applications scrolls without hitching
- An app removed since the last open drops out after a reopen
- Learned ranking still surfaces your habitual result for a short query

### Hotkeys

- The palette, clipboard and emoji shortcuts fire; a per-app shortcut still toggles that app
- Recording captures a shortcut, and the old binding does not fire while recording
- A conflicting binding is rejected and names its current owner
- A double-tap binding fires; Hyper Key remaps and its status dot is green
- Every binding survives quit and relaunch

### Uninstall

- The launcher's Uninstall action opens the scan screen; the bundle is first, leftovers sorted by path
- Rows appear with no loading copy at any point; folder sizes fill in behind them and totals climb
- Locked rows cannot be checked; filtering by name works
- Confirming moves items to the Trash and they are **recoverable from it**
- Escaping mid-scan cancels promptly with no spinner left behind
- Hiding and immediately restoring the screen never strands an in-flight file icon as a placeholder

### Quicklinks

- A quicklink opens its destination; `{argument}` prompts in order and Backspace steps back
- `{selection}` falls back per the Settings choice
- Pin, duplicate, delete and Open with Default all behave; import and export round-trip
- Display order is pinned first by pin time, then by name

### File Search

- With File Search **off**: Search Files is absent, its shortcut no-ops, and no permission appears
- Enabling in Settings exposes Search Files immediately; it persists across relaunch and backup import
- Disabling during a query cancels it and returns the open screen to the launcher
- File Search and Quicklinks remain independently visible in all four enabled/disabled combinations
- An empty query performs no search; a filename query returns only files and folders beneath the scopes
- Library internals, generated trees, application bundles and hidden paths do not appear
- Visible custom top-level home folders and cloud-drive files remain searchable
- Return opens, Command-Return reveals in Finder, and Copy Path keeps the palette open with a HUD
- Replacing a query quickly never lets an older result list overwrite the current query
- A broad `.` search can be scrolled end to end; leaving it releases its fitted icons, and repeating the
  cycle does not raise the post-close memory floor
- Removing home and adding one folder narrows results to it; restoring the default brings them back
- A cleared scope list returns nothing rather than falling back to home, and never hangs
- A missing scope shows the warning triangle without failing the rest of the search
- Adding `*.log` takes effect on the next query with no relaunch; removing it restores those results
- Built-in ignore rows carry no remove button; user rows do, and a duplicate or blank is refused
- Recording a shortcut opens the palette straight into File Search, hidden from the launcher or not
- The pane's checkbox and the Search Files row in Settings ▸ Commands move together
- Export, clear both lists and the shortcut, re-import: all three return, defaults undo not duplicated

### Snippets

- With snippets **off**: no launcher entries, no keyword expansion, and no permission prompt at launch
- Enabling shows the consent dialog **before** the Accessibility prompt
- Declining leaves the feature off and prompts for nothing
- After enabling, a keyword expands in a text field; an argument-bearing snippet prompts then delivers
- Editing a snippet file externally reloads it

### Calculator and currency

- `2+2` shows a card; ↵ copies and records to history; unit and date conversions work
- In Calculator History, ⌃X deletes a row and ⌃⇧X clears the history behind a confirmation
- With currency conversion **off**, a currency query produces no card and **no network request**
- Turning it on shows the consent sheet, naming the provider, first

### System actions and window management

- A confirmation-gated action (Restart, Quit All) confirms, showing the subject's own glyph
- Volume actions show the volume HUD; everything else shows the message pill
- Holding a bound hotkey does **not** stack dialogs
- Window commands move the window you were last in; cycle-on-repeat steps ½ → ⅓ → ⅔
- "Top Half" lands flush with the top of the visible frame, on a secondary display too

### Settings and backup

- Every pane renders and the sidebar switches without flicker
- A feature switch takes effect in the launcher immediately; every setting survives relaunch
- Export produces a file; import applies it and reports a sensible summary
- **`snippetsEnabled` is not in the exported file**, and importing does not enable snippets

### Clean install

The realistic storage failure is a store that crashes on an absent file rather than starting empty.
Wipe the Dev channel and check that path directly:

```sh
rm -rf ~/Library/Caches/com.tinycast.app.dev
rm -rf "$HOME/Library/Application Support/com.tinycast.app.dev"
defaults delete com.tinycast.app.dev 2>/dev/null || true
tccutil reset Accessibility com.tinycast.app.dev 2>/dev/null || true
```

- Launches with every store directory absent — no crash, no hang; onboarding runs
- Palette opens and lists apps; clipboard, quicklinks, snippets and calculator history are all empty
  and all accept a first entry
- **Every setting shows its intended default.** Walk the panes: this is what catches a broken
  absence-versus-`false` read
- Quit and relaunch: everything created above persisted
- Nothing was written outside `com.tinycast.app.dev/`. Channel isolation is not negotiable — a Dev build
  writing into the stable app's directory is a defect even though the data is disposable
