# Search Files

Search Files is an on-demand palette screen for opening files and folders from the folders the user
configures. Typed queries are answered by Tinycast's own in-memory filename index — a native port of
fsearch's name engine — which is walked on the first typed query and then kept current by FSEvents. The
blank screen's Recently Used list still comes from Spotlight. The screen is reached from the built-in
Search Files launcher command, or its own global shortcut, after the feature is enabled in Settings.

## Invariants

- **The index lives in memory and nowhere else.** Nothing is written to disk: no index file, no query
  cache, no history. Quitting, disabling the feature or changing the scopes drops it, and the next typed
  query walks again. Search is filename-only; there is no content index.
- **File Search is off by default, and off means no entry point, no walk and no watcher.** The first
  typed query on the screen is the first operation that touches the disk. The blank screen walks
  nothing, the global shortcut no-ops while the feature switch is off, and disabling stops the
  FSEvents stream and frees the index.
- **The walk asks macOS for the folders it reads.** Desktop, Documents, Downloads and iCloud Drive are
  TCC-protected, so the first walk raises one system consent prompt for each that falls under a scope.
  A denied folder is skipped and the rest of the index is unaffected. Nothing asks for Full Disk Access.
  Each prompt's wording is the matching `NS…FolderUsageDescription` in `Info.plist`.
- **Hidden names, application bundles, package contents and home's own `Library` are structural.** The
  walk never lists them, so no user setting can re-admit them, and an excluded tree is never opened.
  A package — anything whose extension conforms to `com.apple.package` — is one entry, never walked.
  Everything else that is dropped comes from the ignore list.
- **The walk never downloads anything.** It runs with `IOPOL_MATERIALIZE_DATALESS_FILES_OFF` set on its
  own thread, so an iCloud or File Provider placeholder is listed as it stands. Symlinks are listed and
  never followed; mount points and other roots are listed and not descended.
- **The index holds at most 1,000,000 entries, and a search publishes at most 200 rows.** An entry is
  12 bytes plus its share of the interned names; the cap keeps the worst case inside the 100 MB budget.
- **Everything under `Model/` stays Foundation-only and pure**, `FileSearchIgnoreList`'s `import Darwin`
  and the `UniformTypeIdentifiers` of `FileSearchFilter` and `FileSearchPreviewKind` included — value
  types with no environment of their own. `FileNameIndex` is mutated through an explicit API, so
  `file-search-test` builds one in memory without a disk.
- **The filter belongs to the query, not to the rows.** `FileSearchSession` keys its de-dup and its
  supersession check on the query and the filter together, so narrowing re-runs the same words rather
  than thinning a result set that was already capped at 200.
- **`~/Library` is never a scope Tinycast picks by itself.** A configured home root walks home without
  its top-level `Library`, plus the two cloud-storage roots. A user who adds a folder under `~/Library`
  by hand gets what they asked for.
- **The shipped ignore rules are compiled in and never persisted.** `fileSearchIgnorePatterns` stores
  only what the user added, so changing `FileSearchIgnoreList.defaults` reaches installs that already
  ran. The consequence is that the shipped six cannot be switched off.
- **A superseded query never publishes.** The session checks its revision after every search returns,
  so a late result cannot replace the newer query's rows. Editing the scopes or the patterns cancels the
  session and drops the index for the same reason: a result found under the old rules must not land
  under the new ones.
- **A rebuild never blanks results, and a walk under old rules never lands.** `FileIndexManager` keeps
  answering from the current index while a replacement walks, and a generation counter discards any
  walk or refresh that finishes after a newer one started.
- **Share is the one system popover, and the palette stays up under it.** `AGENTS.md` keeps Tinycast's
  own dialogs because a question or a report is Tinycast's to word. A share sheet is neither: it is
  AirDrop, Mail and Messages, and re-drawing it would mean re-implementing the transports and losing
  whatever the system adds. So this row hands off, and the two rules it does keep are that the palette
  is never hidden and that the row stays visible beside the sheet — which is what anchoring to
  `PaletteWindowController.anchorView` buys. The picker is retained on the coordinator, because it
  dies with its last reference, and `NSItemProvider(contentsOf:)` failing (a file that vanished between
  the query and the keystroke) leaves the palette exactly as it was, which is the only failure this row
  can have.

## Query path

`FileSearchSession.search` retains the previous rows, debounces a typed query for 120 ms, then runs its
`searchOperation`. One worker serializes searches and coalesces changes to the newest pending query, so
slower typing cannot accumulate overlapping work. The session owns *when* a search runs and nothing
else. Its operation sends an empty query to `FileSearchService.recent` (Spotlight, in a detached task)
and anything typed to `FileIndexManager.search`.

`FileIndexManager` is the `@MainActor` owner on `AppCore`. A search first waits for an index built
under the current `FileSearchPolicy` — starting the walk if there is none, which is what the screen's
"Indexing files…" waits on — then parses the words into a `FileNameQuery` and scores the snapshot in a
detached user-initiated task. The index is a value type, so the search reads a copy that a concurrent
refresh cannot change under it. A search over the developer home's 99k entries takes 1–5 ms.

## The index

`FileNameIndex` is the store, laid out for one pass over every name per keystroke:

- **Names are interned.** Each distinct filename is stored once as UTF-8 in one byte buffer, with a
  64-bit character-class mask beside it — which letters and digits occur, plus hash bits for the
  letters that start a word. A non-ASCII name also stores its `FuzzyMatch.normalized` key, so
  `resume` finds `Résumé` without folding anything at query time.
- **A folder is a list of 12-byte entries** — name id, modification time, and either a child folder id
  or a code for file, link, package or folder not walked. Folders know their parent, a location prior
  inherited from fsearch's table (`src` and `Documents` up, `vendor` and caches down), and nothing else;
  a path is rebuilt from the parent chain only for the rows that publish.
- **A query scores names, not entries.** Every name whose mask can hold a token is scored once, so a
  `README.md` that appears in four hundred repositories costs one fuzzy match. Entries then add the
  folder prior and a recency bonus, apply the filters, and feed a top-k buffer.

Matching is fsearch's: fzf-style fuzzy scoring with boundary, camel-case and consecutive bonuses, and
one forgiven typo for a word of five ASCII letters or more. Every positive word must match the name or
a folder above it, and at least one must match the name itself, so `tinycast palette` finds
`Tinycast/Palette.swift` without listing every file under `Tinycast`. A word a folder answers scores
three quarters of what the name would. Ties fall to the localized name, then the path.

`FileIndexScanner` is the disk half. One `getattrlistbulk` call per folder returns every child's name,
type, modification time, flags and mount status, read into a reused 256 KB buffer; children are opened
with `openat` relative to their parent, so no path is re-resolved. Exclusions are tested one name at a
time as the walk descends — `FileSearchIgnoreList.excludes(name:)` — and path globs only when the user
has any. The developer home walks in about half a second.

`FileEventMonitor` turns an FSEvents stream over the roots into batches of changed folders. A batch
relists each changed folder one level deep, keeping the ids of child folders that are still there; a
folder that is gone takes its subtree with it. A must-scan-subdirs event relists the whole subtree. A
dropped-events or root-changed flag, or lost history above a root, rebuilds. The watcher starts before
the walk, so a change made while it runs is applied after it. A refresh runs detached on a copy of the
index and is published only if no rebuild started meanwhile.

## Query language

Words are separated by spaces; "double quotes" keep a run of words together. Every positive word is
required, in any order.

| Form | Means |
| --- | --- |
| `word` | fuzzy, in order, one typo forgiven at five letters or more |
| `'word` | the exact substring |
| `^word` / `word$` | the name starts / ends with it |
| `!word` | no match in the name or any folder above it |
| `src/main` | each piece is a word, which a folder can answer |
| `ext:pdf,md` | one of these extensions |
| `kind:file` / `kind:folder` | `f`, `dir` and `d` also work |
| `in:path` | under this folder; a relative path is under home |
| `mtime:<7d` | changed within seven days; `>7d`, `1d..7d`; units `s m h d w mo y`, days by default |

An unknown `key:` is searched for as typed, so a filename with a colon still matches. An empty or
invalid filter value filters nothing. At most eight positive words count.

## Recently used

An empty query is a request of its own, and it skips the typing debounce — there is no next keystroke for
it to coalesce with. It is Spotlight's, because the filesystem records no last-used date for the index
to read. `FileSearchRecents.Stamp` names the two stamps it asks about, each with its own window: changed
in the last 3 days, used in the last 30. Both are needed because macOS writes `kMDItemLastUsedDate` for
very few opens now — a used-only list is a handful of downloads — and the shorter change window is what
keeps a busy machine's matches under the 1,000-candidate `MDQuerySetMaxCount` cap.

Spotlight sorts on one attribute, so the service runs **one sorted query per stamp** and merges their heads
by date, newest first, before publishing 20. Only the first 20 rows of each list are dated: no row past
that can reach the merged list, and every date read costs a metadata fetch. The sort attribute has to be
named in `MDQueryCreate`; set afterwards through `MDQuerySetSortOrder` it is ignored, which is what the
first attempt at this measured. **`kMDItemPath` is the only other attribute read**; what a row needs
beyond it comes from one `resourceValues` stat. Its scopes are home's visible non-package folders plus
the cloud roots, since scoping Spotlight to home itself would pull in `~/Library`.

## Type filter

`FileSearchFilter` is the header's **All Types** pop-up: All Types, Folders, Documents, Images, Audio,
Videos, Archives. Each case names the `UTType`s it admits, and everything else is derived from that list.
The index types an entry by its extension through `accepts(pathExtension:isPackage:)` — resolved as a
package type for a package and a data type otherwise, so a `.pages` package files under Documents — and
memoizes the verdict per extension, so a filter costs one `UTType` lookup per distinct extension.
Folders keeps folders, walked or not, and nothing else. Recents use the same list as a
`kMDItemContentTypeTree` clause, parenthesized when a case names several.

The filter lives on `PaletteState` beside the clipboard's, is reset on every summon, and is never
persisted. ⌘P and the header button open it through `PaletteFilterAction` and the one `PopoverMenu` path
`RootPaletteView` uses for every in-window menu; changing it resets the selection, snaps the scroll and
re-runs the query.

## Scopes and ignore patterns

`FileSearchPolicy` is the resolved answer to "what does this scope list mean": it splits the configured
roots into the ones walked as they stand and the home root, and it compiles the ignore list. It is rebuilt
when either setting changes, never per keystroke. `FileIndexScanner.plan` resolves it against the disk:
every root through `realpath`, home's two cloud roots added when they exist, duplicates dropped. A root
nested inside another is listed by its parent and walked as its own root, so nothing is indexed twice.

Scopes are stored tilde-abbreviated in `fileSearchScopes` so a backup taken on one machine still points
somewhere on another. An empty list searches nothing rather than falling back to home — a cleared list is
a deliberate choice, not an unset one.

`FileSearchIgnoreList` compiles each pattern once into one of three buckets, which is what keeps matching
cheap enough to run against every name the walk lists:

| Pattern shape | Matched against | Example |
| --- | --- | --- |
| no `/`, no metacharacters | any path component, case-folded, via a `Set` | `node_modules` |
| no `/`, has `*` `?` `[` | any path component, via `fnmatch` | `*.tmp` |
| contains `/` | the whole absolute path, via `fnmatch` | `**/[Cc]ache/**` |

`fnmatch` runs with `FNM_CASEFOLD` and deliberately **without** `FNM_PATHNAME`, so `*` spans `/` and a
`**/…/**` pattern behaves as written. Patterns are stored pre-terminated as `ContiguousArray<CChar>`, so
the hot path never re-encodes a `String` into a temporary C buffer.

For recents, bare `*` name globs are also pushed into the Spotlight expression as `kMDItemFSName != "…"cd`
clauses, so ignored files cannot consume the candidate cap. Only that shape is pushed: Spotlight reads `?`
and `[` literally, and `kMDItemPath` is not queryable at all. Quotes and backslashes are escaped on the
way in, and any pattern still carrying one is kept out of the expression.

## Measuring

`FileIndexScanner.build`, `FileIndexScanner.refresh`, `FileIndexManager.search` and
`FileSearchService.recent` emit intervals on the shared `com.tinycast.perf` signpost subsystem, and
`FileIndexManager` logs each walk's entry count and duration under the `FileIndex` category.
`Tests/file-search-performance.swift` walks the current user's home and reports walk time, footprint, one
refresh and per-query latency; it stays outside `run-tests.sh` because filesystem contents are
machine-dependent.

The 2026-10-08 baseline used a release-optimized standalone process against the developer home on the
shipped rules: 98,856 entries in 14,120 folders walked in 0.5 s, the index added 8.8 MB, and a root
folder refresh took 0.24 ms. Across `a`, `e`, `swift`, `pdf`, `project`, `main`, `readme` and `agents md`,
repeated searches took 2.7–4.7 ms and first runs within 0.3 ms of that. The Spotlight search these
replaced measured 64–440 ms for the same queries on the same machine that morning. Recents stayed at
74 ms repeated. The palette's debounce adds 120 ms before a typed query and nothing before recents.
These are local orders of magnitude, not budgets; rerun the benchmark after index or matching work.

## Palette and actions

`FileSearchScreen.rows` is the exact flat selection order rendered by `FileSearchList`. Results sit in a
290pt column beside a preview pane, split by the same `Theme.Colors.separator` hairline the clipboard
draws. The list uses the shared Results header, row metrics, edge dissolve, thin scrollbar and scroll
intent; its header reads **Recently Used** on the blank screen and **Results** under a query. A row shows
a fitted native file icon and the full filename — a folder prefixed by its parent's name, dimmed, since
half the folder hits on a developer machine are some `src` or `Tinycast`. The path itself is the preview's
`Where` row rather than a second column the narrow list has no width for. A click selects and a double
click opens, both through `onRowClick`, which answers on the press: `.onTapGesture(count: 2)` makes the
single tap wait out the system's double-click interval first, and that wait *is* the second a click used
to take before the preview moved.

Fitted row icons use a separate 8 MB transient cache. Leaving the list or hiding the palette purges it
and invalidates in-flight decodes, so scrolling stays warm within one result set without retaining its
icons after File Search closes. Persistent launcher icons remain in their own cache.

The preview pane is the file itself over an Information block — Name, Where, Type, Size, Created,
Modified. The stage is **16:9 and sized before the block beneath it**, which then scrolls in whatever is
left; without that layout priority the aspect ratio shrinks to the leftover height instead of claiming
it. `FileSearchPreviewKind` picks what draws the file, and `FileSearchSurface` mounts it:

| Kind | Surface | Why not QuickLook |
| --- | --- | --- |
| movies, audio | `FileSearchMediaPlayer` | it draws a movie's first frame but never plays one inside a non-activating panel |
| PDF | `PDFSurface`, PDFKit in process | it draws a PDF in an out-of-process `NSRemoteView` that never scrolls inside the palette |
| text QuickLook shows as an icon | `PlainTextSurface` | it renders only a declared `public.text` type as text |
| everything else | `QuickLookSurface` | — |

The extension decides without touching the disk, except where it cannot: an undeclared extension
(`.jsx`, `.vue`) or `.ts`, which the system declares as MPEG-TS video. Those read their first 256 KB
off the main actor once per selection — no NUL and valid UTF-8 is text, anything else falls back to
what the extension declares. `PlainTextSurface` copies QuickLook's own text preview (fixed-pitch 11pt,
3pt inset, unselectable), so a `.jsx` reads like a `.swift`.
**Only the ⌘Y overlay autoplays.** `autoplays` is the surface's one parameter and the pane leaves it
off: arrow-keying a list must not start a movie, while opening Quick Look on one is the ask itself.
The player view is `KeyboardFocusRefusing` either way, so clicking its transport leaves the caret in
the search field; see [palette.md](palette.md#the-keyboard-belongs-to-the-search-field).
The player is File Search's own, deliberately: the clipboard's preview is a separate surface with its own
sizing, and copying forty lines of `AVPlayerView` teardown is the cheaper trade.

**The surface outlives the selection**, and there is no timer in front of it. A move hands the same
`QLPreviewView` another item rather than closing one and building the next, which is the whole cost:
measured against the real machinery inside a panel shaped like the palette's — borderless, floating,
non-activating — a swap paints in about 8 ms, and the first load in a process in about 130 ms. Nothing
about that is worth debouncing, and the debounce that was there only made a click feel slow. The surface
is torn down by not being mounted: when the palette is ordered out, when the ⌘Y overlay covers it, or on
a folder, whose preview is its icon. Information rows are the compact variant; their disk reads happen once per selection
in a detached task, never in `body`, and a folder shows no Size — its own record is a few bytes, which is
never what the row means.

Quick Look (⌘Y) draws **inside the panel**: the palette hides itself on `windowDidResignKey` and the panel
is non-activating, so a system `QLPreviewPanel` would take key and close the palette under itself.
`FileSearchQuickLook` hosts the same two surfaces the pane does, following the selection. **Escape is
answered by `PalettePanel.onEscape`**, not by the palette's own key handler: a focused `AVPlayerView`
takes the key window's Escape first, and `sendEvent` is the one place ahead of it. **Only the margin
around the card dismisses on a click** — a tap over the preview belongs to the preview's own transport,
and a dismissing gesture laid over the whole overlay swallowed the play button — so the Close button is
the pointer's way out. Its corners are concentric, each radius the one outside it less its own inset, and
the overlay is cleared whenever the palette is ordered out: the tree stays mounted, and a preview must
not outlive the window.

| Row | Chord | What it does |
| --- | --- | --- |
| Open File / Open Folder | ↵ | `NSWorkspace`'s asynchronous configuration API; hides the palette without restoring focus, and reports a failure through the dialog controller |
| Show in Finder | ⌘↵ | reveals and dismisses |
| Quick Look | ⌘Y | the in-panel overlay above |
| Share… | — | `NSSharingServicePicker`, anchored to the palette's trailing edge so the row it was opened from stays visible beside it. Escape or a click elsewhere dismisses it, and the palette is never hidden, so the flow returns to the same row. There is no chord: the destinations are the system's, and it is the only place a system popover is right |
| Copy File | ⇧⌘C | the file itself on the pasteboard through `PasteboardFiles.write`, which declares `.fileURL` and the path as `.string` |
| Copy Name | ⌥⌘C | through `Paster`, palette stays open |
| Copy Path | ⌃⌘C | the standardized path, palette stays open |
| Paste File to … | ⇧⌘V | `Paster.pasteFile` into the app the palette was summoned over, named by `PasteTarget` |
| Move to Trash | ⌃X | `FileManager.trashItem` off the main actor, then the row leaves the session |

None of the copies is marked with `ClipboardManager.internalType`, so a copied file enters clipboard
history like any other copy. Move to Trash rides the clipboard's own ⌃X, asks nothing first — trashing is
undoable, as it is for Uninstall and for an extension's `trash` — and has no ⌃⇧X counterpart, since there
is no "all" to trash. The three ⌘C chords differ only by their second modifier, which
`PaletteShortcut` reads in order — ⇧, then ⌥, then ⌃; bare ⌘C stays with the search field.

An in-flight query says nothing — the rows it is about to replace would only flash a message — except a
typed one waiting on the first walk, which says "Indexing files…". An empty completed query says what
the active filter admits ("No files found", "No images found"), a blank screen with no recents says
"Type to search files and folders", and a Spotlight failure behind the recents query says "File search
is unavailable" inline. An index search cannot fail; a folder it could not read is simply absent.

### Dragging out

A row drags its file or folder straight into another app — a Finder window, a browser's upload field,
a mail being written — through the same `onRowClick(drag:)` the clipboard uses, so the press, the
**copy-only** operation and the fly-back are the ones [clipboard.md](clipboard.md#dragging-out)
explains. Copy matters more here than there: every result is the user's own file, and on the boot
volume a plain file-URL drag would default to moving it. The image is the row's fitted tile, already
warm by the time a pointer can reach it; a landed drop hides the palette through
`PaletteCoordinator.dragLanded()`. There is no stat first: a result is seconds old, and its session is
cleared whenever the palette hides.

## Invocation

Settings ▸ File Search owns the `fileSearchEnabled` switch, which is off when its preference is absent,
along with the scope list, the ignore patterns and the Search Files command row. All of them are
ordinary settings carried by Tinycast settings backups; importing them grants no permission and starts
no walk — the first typed query does that, and macOS still asks for each protected folder itself.

`AppCore` observes the switch and asks `FileSearchCoordinator` to project `CommandID.searchFiles` into
the launcher; a second observation rebuilds the policy when either list changes, and drops the index
when the policy actually differs. The coordinator also guards entry into `.fileSearch`, so neither a
stale selected command nor the global shortcut can open the screen after the feature is disabled.
Disabling cancels the session, stops `FileIndexManager` — freeing the index and ending its FSEvents
stream — and returns an open File Search screen to the launcher without changing palette visibility.

Search Files is bindable like every other built-in command — `AppEntry.hotKeyAction` answers
`.command(.searchFiles)`, so its launcher row prints a bound chord as a keycap.

This pane is the command's only one: `SettingsTab.ownedCommands` names it, so Settings ▸ Commands
neither lists it nor gates it behind `Enable Commands`. Launcher visibility is `VisibilityStore`'s,
keyed on the entry's `preferenceKey`. The entry behind it comes from
`CommandCatalog.entry(for:)` rather than `AppIndex`, because the index drops the command entirely while
the feature switch is off — exactly when the pane still has to draw the row. Hiding the command leaves
the shortcut working, as it does for every other feature.
