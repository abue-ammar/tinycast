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

There is no CI: every item is on you, run locally. CodeRabbit reviews each PR, but it is a reviewer,
not a gate. Each is expanded below; the manual sweep at the end of this file is the sixth, judged by
what you touched.

## The harnesses

```sh
./Scripts/run-tests.sh              # all of them
./Scripts/run-tests.sh calc-test    # just one, while iterating
```

The suite runs in parallel, `hw.ncpu` harnesses at a time, which is what takes it from about 140
seconds to about 15. `TINYCAST_TEST_JOBS=1` forces it back to one at a time. Each result is numbered
against the total and shows its run and compile time, a quiet stretch names the harnesses still running, and a harness that runs longer
than `TINYCAST_TEST_TIMEOUT` seconds (default 300) is killed and reported as timed out. Parallelism is safe
because each harness already roots its scratch state somewhere of its own — a UUID-suffixed
`temporaryDirectory`, a `UserDefaults(suiteName:)`, or `NSPasteboard.withUniqueName()` — and a new
harness must keep doing that rather than reach for a fixed path.

Two consequences worth knowing. Status lines arrive in **completion order**, not the order the `run`
lines are written; and a failing harness's compiler diagnostics or assertion output are replayed
together at the bottom, under its name, rather than streamed where they happened. That is deliberate:
a compiler diagnostic is far longer than `PIPE_BUF`, so eleven workers streaming at once would
interleave into nonsense.

A `run` line takes two optional markers before the harness name. `-O` compiles that harness optimised,
which is worth it only where the run dominates the compile — `raycast-test` spends 47 seconds in
scrypt at `-Onone` and one second at `-O`. `slow` dispatches it in the first wave, so the longest
harnesses are not still running after everything else has finished.

The script is the **only** place the harness set is written down. Nothing runs it for you, so run it
before you open a PR. Adding a harness means adding one `run` line.

Each harness compiles the **shipped sources** it guards rather than a copy of them, which is what makes
the pure-layer boundary real: a harness that stops *compiling* means AppKit or SwiftUI has leaked into a
`Model/` folder, or an effect has leaked into a decision. That is a more common failure than a broken
assertion, and it is the more important one.

A harness also runs in your own login session against the real system, with no sandbox and no fixture
world, so it must never mutate state the machine shares with the apps you use. `NSPasteboard.general`
is the trap: a running Tinycast records every write to it as a genuine copy, so a fixture left there
lands in clipboard history looking like something the user copied. `notes-editor-test` seeded one on
every run from #232 onward by calling the native `copy:`/`cut:`/`paste:` actions; it now drives the
`writeSelection(to:types:)` and `readSelection(from:)` primitives those actions delegate to, against
`NSPasteboard.withUniqueName()`. Same AppKit path, no shared side effect. `pasteboard-test` is the
second case, and it is why `ClipboardManager.fileURLs(on:volatileRoots:)` and `Paster.write(_:store:to:)`
each take the thing they act on as a parameter: a seam that exists so the harness never has to reach
for the shared board. Its scratch tree lives under `temporaryDirectory`, which is itself a volatile
root, so the cases about *reading* files inject an empty root list and the one case about durability
is the one that runs against the shipped roots. Both file URL and legacy filename boards also cover
the capture cap, exact ordering, rejected prefixes, duplicates and symlinks using private fixtures.
The reader cases add the limit boundaries, the predicate call counts and modern/legacy precedence.
Note that macOS synthesizes `public.file-url` items for any `NSFilenamesPboardType` write, so a
legacy fixture still exercises the modern representation and the fallback branch stays unreached.

Never join a compile to its run with `&&` in a `set -e` script. `set -e` is specified to ignore a
failing command in a non-final AND-OR list member, so `swiftc … && /tmp/x` swallows a compile error and
the script sails on. CI reported success over a harness that had not compiled for twenty-five phases
because of exactly this; `run-tests.sh` keeps the two steps separate and records both kinds of failure.

### What to run when

If a change touches anything in the right column, the harness on the left is mandatory.

| Harness | Guards |
| --- | --- |
| `fuzz-test` | `Launcher/Model/SearchRelevance.swift`, `EntryNaming.swift`, `ScriptRomanization.swift`, `LauncherOrder.swift` |
| `corpus-test` | the launcher's ranking, over a dense synthetic index — **a new complaint is a new case in `Tests/launcher-corpus/corpus.json`** |
| `file-search-test` | `FileSearch/Model/`, plus the shared `FuzzyMatch` scorer |
| `file-search-session-test` | serialized query execution, debounce coalescing and cancellation |
| `menu-search-test` | `MenuSearch/Model/` decisions, `MenuSearch/Service/` session filtering, the shared `FuzzyMatch` scorer |
| `action-menu-search-test` | Action-menu query normalization and shared fuzzy matching |
| `ranking-test` | `Launcher/Model/LauncherRankingStore.swift` |
| `scopes-test` | `Launcher/Model/SearchScopes.swift` |
| `app-name-test` | `Platform/AppDisplayName.swift` — every path that names a scanned bundle |
| `calc-test` | all of `Calculator/Model/` |
| `calendar-test` | all of `Calendar/Model/` — link detection, the join window, the day buckets |
| `clipboard-search-test` | Ordinary and OCR result ordering, opt-in lifecycle, cancellation, pins and type filters |
| `clipboard-text-test` | Apple Vision/PDF extraction, scheduling, retry backoff and recovery |
| `clipboard-test` | `Clipboard/Model/ClipboardStore.swift`, `ClipboardFilter.swift`, `ClipboardFileKind.swift`, the colour trio |
| `pasteboard-test` | `Clipboard/Service/ClipboardManager.swift` capture and `Paster.write` — what a Finder copy reads as, and what a file entry writes back |
| `emoji-test` | `Emoji/Model/EmojiCatalog.swift`, `EmojiGridGeometry.swift`, the generated data |
| `emoji-search-test` | `Emoji/Service/EmojiIndex.swift`, `FrequentEmojiStore.swift`, `Scripts/gen-emoji.js`'s keyword format |
| `palette-navigation-test` | `Palette/PaletteState.swift`'s screen motions — `prepare`, `replace`, `push`, `pop` |
| `palette-selection-test` | `Features/PaletteRowIndex.swift` |
| `interface-size-test` | `DesignSystem/InterfaceMetrics.swift`, `Features/Settings/InterfaceSize.swift`, `Extensions/Model/ExtensionFormMetrics.swift` |
| `palette-placement-test` | `DesignSystem/Theme.swift`, `Palette/PalettePlacement.swift` |
| `hotkey-test` | `HotKeys/Model/DoubleTapModifier.swift`, `DoubleTapDetector.swift`, `HyperKey.swift`, `HotKeyAction.swift`, `Service/KeyShortcut.swift`, and the command→action mapping in `Launcher/Model/CommandID.swift` |
| `fallback-test` | `Launcher/Model/Fallback.swift`, plus the `CommandID` and `Quicklink` ids it is built from |
| `dictionary-test` | `Dictionary/Model/DictionaryEntry.swift`, `DictionaryMarkup.swift` — a real XHTML record and the plain-text fallback, read into page blocks |
| `callout-test` | `DesignSystem/Theme.swift`, `HotKeys/UI/CalloutPlacement.swift` |
| `system-action-test` | `SystemActions/Model/SystemAction.swift` |
| `volume-test` | `SystemActions/Model/VolumeLevel.swift` |
| `window-command-test` | `WindowManagement/WindowCommand.swift`, `WindowPlacementEngine.swift`, `WindowActionMemory.swift` |
| `window-layout-test` | `WindowManagement/Model/WindowLayout*.swift` and `CustomWindowSize*.swift` — the layout record, its geometry and its inverse, the plan and the store; custom sizes' units, frames and store |
| `custom-command-test` | `CustomCommands/Model/CustomCommand.swift`, `Service/ShellCommandRunner.swift` |
| `uninstall-test` | all five pure files in `Uninstall/Model/` |
| `quicklink-test` | all of `Quicklinks/Model/` |
| `apple-shortcut-test` | all of `AppleShortcuts/Model/` — the `shortcuts list` parser and entry ids |
| `snippets-test` | all of `Snippets/Model/` and `Snippets/Service/`, plus `Platform/HealthTicker.swift` |
| `notes-test` | all of `Notes/Model/` and `Notes/Service/`, including the Markdown parser, edit plans and reveal policy, plus the real fuzzy matcher and signposts |
| `notes-editor-test` | the Notes editor, rendered and literal, with real TextKit 2 and AppKit editing objects: styling, reveal, layout fragments, keys, chords, checkboxes and links |
| `raycast-test` | `Backup/Service/RaycastDecoder.swift`, `Scrypt.swift`, `Platform/Compression/Zlib.swift` |
| `symbols-test` | `Extensions/Service/SymbolCatalog.swift`, against this machine's CoreGlyphs |
| `ext-store-test` | `Extensions/Model/` — the registry model and both registry APIs' parsers |
| `ext-refresh-test` | `Extensions/Model/ExtensionRefreshPolicy.swift` — interval parsing, due dates, backoff, subtitle fallback, indicator state |
| `ext-metadata-test` | `Extensions/Service/ExtensionCommandMetadataStore.swift` — round-trip, failure runs, uninstall |
| `ext-test` | the extension runtime end to end — boots a real bundle in JavaScriptCore and renders it |
| `ext-icon-test` | `Extensions/Service/ExtensionIconCache.swift` — artwork sizing and its fallback |
| `icon-cache-test` | `Platform/Images/IconCache.swift` — row sizing at 1×/2×, warm reuse, stamp and style invalidation, bitmap release, and that a row icon draws identically to the 96px one |
| `entry-icon-test` | `EntryIcon` — that each case draws, caches and prints apart from the others, and that a moved `FileIconStamp` retires the bitmap decoded before it |
| `text-diff-test` | `QuickActions/Model/TextDiffEngine.swift` — exact chunks, Unicode, ties, token-cap boundaries and fast paths |
| `settings-backup-test` | `Settings/AppSettingsKey.swift`, `Backup/Model/SettingsBackupCoverage.swift` |
| `backup-archive-test` | all of `Backup/Model/`, plus `Backup/Service/BackupStaging.swift` |
| `updates-test` | `Updates/Model/` — version precedence, channel filtering, install route, readiness |
| `support-test` | `Support/Model/` — when the support reminder comes due, and a clock moved backwards |
| `mcp-test` | `MCP/Model/` and `MCPSettingsStore` — JSON-RPC framing, handles, tool names, output flattening, trust, `@server` addressing |
| `mcp-stdio-test` | `MCP/Service/` against a stub server — handshake, listing, calling, and every way one can go away |

The two harnesses that need a server to talk to bring their own: `Tests/ai-fixtures/codex-stub.js`
and `mcp-stub.js`, each copied into a scratch directory and put in front of PATH so the locator finds
it the way it would find a real one. Both read fd 0 synchronously rather than through a stream —
`codex-stub.js` stalls mid-turn on purpose, and an event loop would read the next line while it is
still holding — and both write with `fs.writeSync`, so a reply is on the pipe before a mode that
exits does.

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
- `WindowManagement/Model/` still touches no `NSScreen` and makes no AX call, layouts included
- `Features/PaletteRowIndex.swift` still imports Foundation alone, despite living under `Features/`
- `Quicklinks/Model/` is still handed the home directory rather than reading it
- `FileSearch/Model/` is still handed the home directory rather than reading it

## Build and size checks

A clean build is part of the bar; nothing builds the app for you, so this is on you.

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
- Release binary growth under **2%** for an ordinary change.

### Lint

```sh
./Scripts/lint.sh
```

SwiftLint owns the rules that catch defects, including the two checkable comment rules — the
100-character cap and the ban on stacked comment lines. Errors block; warnings do not. There is no
formatter, deliberately — the configuration and the measurements behind that are in
[development.md](development.md#formatting).

The script then runs `Scripts/check-settings-search.js`, one check SwiftLint can't: every
`SettingsAnchor` must be claimed by a section, and every row in `SettingsSearchCatalog` must be
marked by a `SettingsRowTitle`. Either gap compiles and reads fine, and fails only at runtime as a
search result that navigates and then sits there.

## Performance measurement

`Platform/Signposts.swift` emits eight intervals on the `com.tinycast.perf` subsystem: `AppCore.start`,
`AppIndex.scan`, `AppIndex.rank`, `PaletteWindowController.show`, `UninstallScanner.discover` and
`UninstallScanner.measure`, `FileSearchService.search`, and `Notes.search`. Open the Time Profiler or
`os_signpost` instrument in Instruments and filter to that subsystem; nothing needs recompiling.

None of the benchmarks below join the suite, so each is registered in `run-tests.sh` as `run index`
instead: `--index` hands it editor flags without queueing it, and without that entry nothing in the
file resolves. Keep the entry's source list matching the command beside it.

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

The calculator benchmark is deterministic — an injected clock, calendar and rate table — so it is a
timing harness rather than an assertion one, and stays out of `run-tests.sh` for that reason:

```sh
swiftc -O -swift-version 6 Tinycast/Features/Calculator/Model/*.swift \
    Tests/calc-performance.swift -o /tmp/calc-performance
/tmp/calc-performance          # µs per query, by grammar
/tmp/calc-performance --probe  # every answer as JSON, to diff two builds
/tmp/calc-performance --cold "10kg to lb"   # first query, including catalog decode
```

`Tests/text-diff-performance.swift` is the same shape for `TextDiffEngine`: build it with `-O`
against the engine, pass a token count, a workload (`dense`, `sparse`, `equal`, `empty`) and an
iteration count for timings, or `--probe` to diff every chunk between two builds.

`Tests/clipboard-file-performance.swift` measures file capture with private pasteboards and temporary
fixtures. It reports wall and process CPU time as JSON for modern and legacy formats, including
32/1,000/10,000 durable files, rejected-input controls and an uncapped-reader control that guards
the attachment path against the bounded reader it now delegates to. Compare three fresh processes
per build with identical `-O` settings:

```sh
swiftc -O -swift-version 6 Tinycast/Platform/PasteboardFiles.swift \
    Tinycast/Features/Clipboard/Model/{ClipboardStore,ClipboardFilter,ColorValue,ColorFormat,ColorSpaces}.swift \
    Tinycast/Features/Clipboard/Service/ClipboardManager.swift \
    Tests/clipboard-file-performance.swift -o /tmp/clipboard-file-performance
/tmp/clipboard-file-performance
```

`Tests/emoji-search-performance.swift` times uncached queries, typing prefixes and memo hits against
the loaded catalog, with process RSS and footprint as JSON; `--names` also lists every catalog name
missing from its own top five results:

```sh
swiftc -O -swift-version 6 Tinycast/Features/Emoji/Model/{EmojiCatalog,EmojiData.generated}.swift \
    Tinycast/Features/Emoji/Service/{EmojiIndex,FrequentEmojiStore}.swift \
    Tinycast/Features/Launcher/Model/SearchRelevance.swift Tinycast/Platform/{AppPaths,Memo}.swift \
    Tests/emoji-search-performance.swift -o /tmp/emoji-search-performance
/tmp/emoji-search-performance --names
```

`Tests/notes-editor-performance.swift` installs a 100,000-character note in a real rendered editor and
prints, as JSON, the median over 30 runs of the install with its full restyle, one typed character at
the end, middle and start, and a caret move between distant lines. The budget is 150 ms, 8 ms (end and
middle) and 4 ms:

```sh
N=Tinycast/Features/Notes
swiftc -O -swift-version 6 Tinycast/Platform/{Signposts,Appearance,NotificationToken}.swift \
    Tinycast/DesignSystem/{Theme,InterfaceMetrics}.swift \
    Tinycast/Features/TextInjection/Service/InjectableTextView.swift \
    $N/Model/{NoteDocument,NoteMarkdown,NoteMarkdownParser,NoteInlineScanner}.swift \
    $N/Model/{NoteEditPlan,NoteEditAction,NoteFormatting,NoteMarkdownEditing,NoteRevealPolicy}.swift \
    $N/UI/{NoteMarkdownTypography,NoteBlockDecoration,NoteMarkdownStyler,NoteMarkdownRenderer}.swift \
    $N/UI/{NoteCheckboxGeometry,NoteBlockLayoutFragment,NoteLayoutFragmentProvider}.swift \
    $N/UI/{NoteTextViewEditing,NoteTextView,NoteEditorView}.swift \
    Tests/notes-editor-performance.swift -o /tmp/notes-editor-performance
/tmp/notes-editor-performance
```

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
| The harness suite | ~15 s wall clock, 11-way parallel (~98 s serial, ~140 s before either) |
| `palette-selection-test` | 111,684 assertions — a tripwire: a change in this count means the row-order model moved |
| `SnippetKeywordPolicy` match | 7 µs/keystroke at 50 keywords, 59 µs at 1,000 — the `lowercased()` is 0.09 µs of it |
| `ClipboardStore.pinnedItems` | 27–127 µs per uncached search, 1,000-row window — no cache earns its invalidation yet |
| Rendered Notes editor, 100,000 characters | 30 ms install and full restyle; 7.5, 5.9 and 3.3 ms per character typed at the end, middle and start (5.2, 3.1 and 0.6 ms with rendering off); 0.6 ms per caret move |
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

- Palette hotkey opens the launcher; pressing it again closes it; Escape clears a non-empty query,
  then hides on a second press; clicking away closes it
- Search a mode command (Clipboard History, Search Emoji, Search Quicklinks, Search Files, AI Chat)
  and run it: Escape returns to the launcher **with the query still typed and the row still
  selected**, and the next press clears it. The same screen from its own global hotkey hides the
  palette instead, and shows its own header icon rather than a back chevron
- ⌘⎋ from any depth lands on an empty root search with the window still open — **must be checked on
  a real keyboard**: macOS claims the chord, so `CommandEscapeTap` is the only thing that delivers it
  and it needs Accessibility granted to the running build. With the palette closed, ⌘⎋ still does
  whatever macOS does with it
- A bare ⌫ in an empty field walks the same path Escape does
- General ▸ Escape Key Behavior set to `Close window and pop to root`: Escape on any screen closes
  the window, and reopening lands on the root search whatever Pop to Root Search says
- Reopening focuses the search field with an empty query, in the same position and at the same size
- Compact mode: typing expands it, and the search bar does **not** shift vertically during the swap
- With a CJK IME: the placeholder clears as soon as composition starts and the composing text never
  overlaps it; cancelling composition brings the placeholder back, and the list filters only once the
  candidate is committed — check on a second summon too, where first responder never moved
- Typing filters instantly; ↑/↓ move the highlight and scroll it into view without yanking the list
- ⌃N/⌃P move the highlight as ↓/↑ do; ⌃F/⌃B step the emoji grid's selection, and the caret elsewhere
- The highlight always sits on the row the footer pill describes
- With a calculation typed, the calculator card is first and is selected first
- Section headers appear in order: Favorites, Applications, System Settings, Quicklinks, Snippets,
  System Actions, Window Management, Custom Commands, Commands
- With a non-ASCII input source active, ⌘K opens Actions; ↑/↓ move it, ↵ activates, Escape closes it
- In either ⌘K Actions panel, typing filters immediately in the bottom search band without changing
  the palette query; sections survive filtering, **No Results** is centred, and no dissolve covers the
  last row. The native caret blinks; mouse drag and ⌘A select text; ←/→ move through it; ↑/↓ still
  move the menu highlight. Escape clears a non-empty query, then closes the menu on the next press
- The bottom-left app menu also searches from its bottom band; every header menu — including Emoji
  categories, File Search filters and extension dropdowns — searches from its top band
- A long menu opens with unchanged row insets; while scrolling, rows can reach the panel edges
- A click in the palette but outside its menu closes only the menu; a click outside the palette
  closes both, regardless of the menu query; the next summon accepts typing immediately
- Footer menus are about 30pt wider; their row hover keeps the shared 10pt menu-row corner
- Tab toggles launcher ↔ clipboard; bare Backspace on an empty query backs out of a sub-screen
- Launching an app focuses it; escaping the palette returns focus to the app you came from
- Paste from clipboard history lands in that app, not in Tinycast
- No flash, flicker or reflow on open, and row metrics unchanged

### Clipboard

- A copy appears at the top within about a second; an image copy records a thumbnail
- Search is correct both under and over three characters
- The type filter searches from its top band, retains its active checkmark when matched, and shows
  centred **No Results** without changing the clipboard query; its native field supports selection
- ⌘. pins and the highlight follows the row into Pinned; ⌘⌫ deletes; ⌘↵ copies without pasting
- ⌃X deletes the selected entry and ⌃⇧X clears the history, from the list and from an open ⌘K menu
- ⌃⇧X asks first, through Tinycast's own dialog; Cancel and Esc both leave every entry in place
- ↵ pastes into the previous app; ⌥↵ pastes without closing the palette
- A copy from an excluded app (Settings ▸ Clipboard ▸ Disabled Applications) is **not** recorded
- Password-manager copies are still not recorded
- Off (Settings ▸ Clipboard ▸ Enable Clipboard History): nothing new is recorded, the launcher row
  and its shortcut are gone, the menu-bar row is gone, and Tab rings straight past the screen
- Off then on again: existing clips come back; Clear history erases them while it is still off

### Launcher and icons

- Every installed app appears; Settings panes appear under System Settings; running apps show the dot
- Icons render with no placeholder flash on reopen, and Settings ▸ Applications scrolls without hitching,
  even with the scrollbar thumb dragged from end to end in under a second
- An app removed since the last open drops out after a reopen
- Learned ranking still surfaces your habitual result for a short query

### Hotkeys

- The palette, clipboard, emoji, File Search, and all three Notes shortcuts fire; a per-app shortcut
  toggles that app
- Recording captures a shortcut, and the old binding does not fire while recording
- A conflicting binding is rejected and names its current owner
- A double-tap binding fires; Hyper Key remaps and its status dot is green
- Every binding survives quit and relaunch
- `Enable Commands` off leaves every pane-owned command listed, searchable and firing — Notes,
  Clipboard, Emoji, File Search, Snippets, Quicklinks, Calendar, AI and the two layout commands

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

### Apple Shortcuts

- Off out of the box: the pane lists nothing and no shortcut reaches the launcher
- Switching on lists every shortcut with the Shortcuts app's icon; ↵ on a row runs it
- A shortcut added in Shortcuts appears on the next launcher open
- A row's hotkey runs it with the palette closed; switching the feature off silences it
- Unchecking a row hides it from search, and its hotkey still fires
- Deleting a shortcut in Shortcuts frees its alias and hotkey on the next launcher open
- A shortcut that fails shows Tinycast's dialog with the tool's error

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
- Search Files is absent from Settings ▸ Commands, and `Enable Commands` off leaves its shortcut live
- Export, clear both lists and the shortcut, re-import: all three return, defaults undo not duplicated

### Notes

- With Notes **off**: all three commands are absent, their shortcuts no-op, and the Notes directory is
  not created
- Enabling in Settings projects Show Notes, Create Note, and Search Notes immediately; the pane's
  visibility checkboxes and recorders are the only ones — Settings > Commands lists none of the three
- Show Notes opens the last active note and focuses an already visible window without hiding it
- Create Note makes one unique Untitled file, including as the first action in an empty channel
- Command-P and the Browse button focus search, arrows move selection, Return opens, and Command-N
  creates
- Empty switcher search reads the complete recent list; title and body searches rank correctly and a
  superseded query never publishes
- An Untitled note titles itself from its first line as it is typed, in the title bar and — after the
  autosave — in the browse list; naming it replaces that, and clearing the name brings it back
- Inline rename updates the Markdown filename without changing source, and starts from that filename
  even where the row shows a derived title; collisions receive a suffix
- Delete confirms through Tinycast, moves the file to Trash, and selecting another note never loses an
  unsaved edit
- An existing `Floating Note.md` appears as an ordinary note without conversion
- A note using every construct renders in Dark and Light: sized headings, emphasis, strikethrough,
  inline code, coloured links, bullets, numbers, checkboxes with space between tasks, lists nested at
  two and four spaces, quote bars, a code band with its language label, and a rule
- The caret's line shows raw Markdown in the tertiary colour and re-renders when the caret leaves; a
  multi-line selection reveals every selected line, and Select All shows the whole source
- Dragging a selection across rendered lines does not jump under the pointer; the lines reveal on
  mouse-up
- Clicking another app renders the whole note; clicking back reveals the caret line again
- Inside a code block both fences show and Markdown inside it stays literal
- A table shows as its literal source in the code font, with no styling inside it; adding the `| --- |`
  row under existing rows turns them all into the table at once
- Bullets, numbers and checkboxes are a neutral gray, bullet, numbered and task items are evenly spaced,
  and revealing a bullet or numbered line leaves its text where it was
- A checkbox click toggles without moving the caret, autosaves, and Command-Z restores it; the file on
  disk shows `[x]`
- A link click opens the browser, a click at the label's edge places the caret, a `file:` link does
  nothing, and a link on the caret's line is editable text
- Return continues and leaves lists and quotes, Tab and Shift-Tab nest, ordered lists renumber, `[] `
  becomes a task, and every formatting shortcut works and undoes in one step
- Pasting a URL over selected text makes a link; pasting anything else is plain text
- Copy from a rendered line pastes raw Markdown into another app; a snippet keyword expands inside a
  rendered note and is styled at once
- The derived title of an Untitled note shows no Markdown markers
- A narrow window wraps list items under their text, not under the marker
- With Render Markdown **off**, the note is fully literal (markers visible, links inert, task syntax
  plain) and Return, Tab, Delete, and formatting-looking shortcuts keep native plain-text behavior;
  flipping it back re-renders without dirtying the note or touching undo
- Edit one note, switch to a shorter note, then Undo and Redo: the new note remains intact and the app
  does not terminate
- Marked-text input, emoji, combining marks, Copy, Cut, Paste, Select All, Undo, Redo, and Find preserve
  exact source
- An empty note shows `Start writing…`; the footer count is right after typing, pasting and undoing
- With Render Markdown and Show Formatting Bar on, the band under a note holds the character count on
  the left and the round formatting button on the right; with either setting off, the old centred
  count footer is back and nothing else moved
- The bar starts collapsed, ⌥⌘T and the round button both expand and collapse it, the buttons slide out
  from behind that button, and the state survives switching notes, hiding the window and a relaunch
- Every bar button applies its formatting, undoes in one step with ⌘Z, and autosaves; clicking keeps the
  caret where it was and the caret's line stays revealed
- Buttons light for the selection: inside bold, on a list, quote, heading or code line; clicking a lit
  button removes that formatting and the button goes dark
- Hovering a button shows its name and shortcut above it, fully visible and not clipped by the capsule;
  the heading button's tooltip does not show while its menu is open
- The heading menu opens above the capsule, aligned to its left edge, shows the current level checked,
  and applies a level on click; it closes on Escape, on a click anywhere in the note window (including
  the heading button itself, which must not reopen it), on typing, on ⌘P, and when another app is clicked
- At the smallest window size all eleven controls show and the count is hidden, the note's text keeps
  its inset in both states, the heading menu still opens in full above the capsule, and widening the
  window brings the count back
- ⌥⌘C and ⇧⌘B toggle a code block and a quote; with Render Markdown off they do nothing special
- Settings > Notes > Show Formatting Bar is disabled while Render Markdown is off, Settings search for
  "formatting" lands on it, and a backup round trip restores it
- With VoiceOver, the bar reads as "Formatting" with each button named, lit ones as selected, the round
  button announcing Expanded or Collapsed, and the heading button its level; menu rows read their titles
  and the current one as selected
- Traffic lights sit top-left, the title is centred **on the window**, and the capsule is top-right, all
  on one line; the yellow light is disabled and green zooms
- Each capsule button shows a hover capsule and a native tooltip, and fires its action
- Dragging the title bar moves the window and dragging an edge resizes it; both survive relaunch
- Clicking another app leaves the panel visible; Escape, Command-W, and the red light hide it
- Command-Q does nothing anywhere; with Settings in front, Command-W closes Settings
- Hiding restores the previous external app or Tinycast window
- Open Notes Folder opens Finder with the active Markdown file selected, or the folder with no note
- Deleting every note closes the browse list and leaves one clean empty state with no character count;
  Command-N from there creates and selects one note
- The browse list fades only at its bottom edge and rests opaque once it reaches the end
- Quitting inside the debounce window saves the last edit
- Over a light desktop, the corner matches the palette's, the shadow follows it, and no dark edge shows
  around the glass controls

### Snippets

- With snippets **off**: no launcher entries, no keyword expansion, and no permission prompt at launch
- Enabling shows the consent dialog **before** the Accessibility prompt
- Declining leaves the feature off and prompts for nothing
- After enabling, a keyword expands in a text field; an argument-bearing snippet prompts then delivers
- Editing a snippet file externally reloads it

### Calculator and currency

- `2+2` shows a card; ↵ copies and records to history; unit and date conversions work
- In Calculator History, ⌃X deletes a row and ⌃⇧X clears the history behind a confirmation
- A currency query answers from the cached snapshot; with the cache cleared and no network it reports
  rates unavailable rather than guessing
- A bare amount (`1 usd`) answers in the Mac's region currency, and follows a change to
  System Settings ▸ General ▸ Language & Region without a relaunch — and nothing prompts for location
- A crypto query (`1 btc`, `0.5 sol to eur`) answers, and `1 usd to btc` stays in plain notation

### Calendar and meetings

- With Calendar **off**: no launcher entries, no card, no permission prompt at launch
- Enabling shows the consent dialog **before** the macOS prompt; declining prompts for nothing
- After Calendar permission is reset, Settings ▸ Calendar offers `Allow Calendar Access…` and asks
  again; after denial it offers System Settings instead
- With a meeting four minutes out, an empty palette shows the card on top, provider glyph and all
- The countdown steps on the minute boundary rather than on a keystroke
- ↵ joins: a Zoom link opens the Zoom app, and the browser where no app claims the scheme
- Typing a character swaps the card for the calculator's; ↑/↓ never lands on a phantom row
- Unchecking a calendar drops its events from the launcher and My Schedule, and survives a relaunch
- Adding or deleting an event in Calendar.app updates an open palette without a reopen
- A meeting with no link is listed and searchable, and answers Open in Calendar rather than Join
- Import a backup taken with Calendar on: it comes back **off**, and no calendar toggle travels
- Calendar in Menu Bar on Disabled: the calendar item is gone and Tinycast's own item is unaffected;
  turning `Show in menu bar` off leaves an enabled calendar item in place, and both off leaves neither
- On Meeting Title with Show Upcoming Events at 5 minutes, the title and countdown appear at T-5 and
  step on the minute boundary, not on a keystroke
- `Only show events with meetings` hides a linkless event and shows it again when unchecked
- Hide Current Event on Automatically clears the entry at the start and hands the space to the next
  event inside its lead time; on 5 minutes it lingers counting up, then clears
- Clicking the calendar item opens `Join <title>`, `Open in Calendar...`, `My Schedule` and
  `Calendar Settings...` and nothing else; the second opens that event in Calendar.app, while a bare
  click never joins
- Camera Preview on: ↵ on the join card opens the panel **already showing live video** — no black
  frame, no blank mid-preview; ↵ joins, Esc drops the join; the camera light goes out with the
  panel, and the first run prompts once, before any panel appears
- A meeting that ends leaves the launcher results and `My Schedule` on the same minute boundary it
  leaves the menu bar, with the palette open or closed over the end
- Auto Join on: the meeting opens itself at its start, **once** — dismiss it and it does not return.
  With confirm on and camera preview off, the dialog asks first
- Arming Auto Join during a meeting already under way joins nothing
- Sleeping over a meeting's start and waking past it reloads the events; one still inside the window
  joins, one long past does not
- Create Event writes to the default calendar and shows up on the card, the schedule and the launcher
  without a relaunch; a blank title leaves the dialog up on ↵ and on a click
- Arrow keys move the caret in the New Event title field, and still step the Set Volume slider
- Every command row of Settings ▸ Calendar has Add Alias, Record Hotkey and a checkbox, and none of
  the five appears in Settings ▸ Commands
- Export with auto join and camera preview on, import onto a clean profile: both come back **off**,
  while the menu-bar settings carry over

### System actions and window management

- A confirmation-gated action (Restart, Quit All) confirms, showing the subject's own glyph
- Volume actions show the volume HUD; everything else shows the message pill
- Holding a bound hotkey does **not** stack dialogs
- Window commands move the window you were last in; cycle-on-repeat steps ½ → ⅓ → ⅔
- "Top Half" lands flush with the top of the visible frame, on a secondary display too

### Extensions

- Every command under Settings ▸ Extensions has Add Alias, and Record Hotkey when the mode is
  supported; an alias set there finds the command from its start and shows the chip
- Hiding the extension from the launcher, or turning off Show in launcher, dims its alias fields

### Settings and backup

- Every pane renders and the sidebar switches without flicker
- A feature switch takes effect in the launcher immediately; every setting survives relaunch
- Export produces a `.tinycast`; import applies it and reports a per-category summary
- Untick a category on export, and the import picker greys that row out rather than offering it
- Untick a category on **import** and confirm it did not arrive, while the ticked ones did
- An image clip round-trips and still renders; the archive can then be deleted without breaking it
- A file whose `manifest.json` `format` was hand-edited is refused **with a message naming it**
- Cancelling the save panel leaves nothing in `~/Library/Caches/com.tinycast.app.dev/backup-staging/`
- **`snippetsEnabled` is not in the exported file**, and importing does not enable snippets
- Nothing in the extracted tree names a Keychain item, an extension, or an AI conversation

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
- Notes creates no directory until Show, Create, or Search is first used, then accepts its first edit
- **Every setting shows its intended default.** Walk the panes: this is what catches a broken
  absence-versus-`false` read
- Quit and relaunch: everything created above persisted
- Nothing was written outside `com.tinycast.app.dev/`. Channel isolation is not negotiable — a Dev build
  writing into the stable app's directory is a defect even though the data is disposable
