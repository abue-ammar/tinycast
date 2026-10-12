# Search Files

Search Files is a palette screen for opening any file or folder on the disk. It searches Tinycast's own
filename index, built from a whole-disk crawl and kept current from FSEvents. Spotlight is not involved.
It is reached from the built-in Search Files launcher command, or its own global shortcut, after the
feature is enabled in Settings. The design follows [fsearch](https://github.com/noahdunnagan/fsearch).

## Invariants

- **The crawl runs in `FileIndexHelper`, never in the app.** On macOS 27 malloc keeps freed small blocks
  dirty, so a crawl inside the app would leave its peak behind for good. The helper writes the index and
  exits; the app only maps the file, whose clean pages never count toward its footprint.
- **Full Disk Access is required, and nothing is indexed without it.** `Permissions.hasFullDiskAccess()`
  probes a TCC-guarded file, which never prompts. The pane and the palette both say how to grant it.
- **Scopes are the crawl roots.** Only what lies under a scope is indexed or searched; a scope inside
  another folds into it, and a cleared list indexes nothing. The default is the whole disk (`/`).
- **A matching ignore pattern skips a folder and everything in it at crawl time.** Changing either list
  rebuilds the index, debounced by a second; the old index serves until the new one maps.
- **Hidden files and bundle contents are indexed.** They rank last instead (see Ranking), and the ignore
  list is how a user narrows further. Mount points are never entered, which keeps firmlinked files from
  appearing twice through `/System/Volumes/Data` and keeps other volumes out.
- **A crawl never downloads.** Every listing runs with `IOPOL_MATERIALIZE_DATALESS_FILES_OFF` on its own
  thread, so dataless iCloud and File Provider items are listed as they are.
- **A live update is idempotent.** Every FSEvents event relists one folder and diffs it, so a replay, a
  duplicate or an event that races a rebuild changes nothing twice.
- **File Search is off by default, and off means no index on disk.** Disabling stops the watcher, cancels
  any build and deletes `Application Support/<bundle id>/FileIndex/`.
- **The shipped ignore rules are compiled in and never persisted.** `fileSearchIgnorePatterns` stores only
  what the user added, so changing `FileSearchIgnoreList.defaults` reaches installs that already ran.
- **A superseded query never publishes.** The session runs one search at a time, keeps only the newest
  pending request, and checks its revision before publishing.
- **Share is the one system popover, and the palette stays up under it.** `AGENTS.md` keeps Tinycast's
  own dialogs because a question or a report is Tinycast's to word. A share sheet is neither: it is
  AirDrop, Mail and Messages, and re-drawing it would mean re-implementing the transports and losing
  whatever the system adds. So this row hands off, and the two rules it does keep are that the palette
  is never hidden and that the row stays visible beside the sheet — which is what anchoring to
  `PaletteWindowController.anchorView` buys. The picker is retained on the coordinator, because it
  dies with its last reference, and `NSItemProvider(contentsOf:)` failing (a file that vanished between
  the query and the keystroke) leaves the palette exactly as it was, which is the only failure this row
  can have.

## Building the index

`FileIndexer` (main actor) owns the lifecycle. With the feature on and access granted it maps
`FileIndex/index.bin` if its fingerprint matches the current `FileSearchPolicy`, and otherwise launches
`Contents/Helpers/FileIndexHelper` with the output path and the policy's `Request` as JSON. The helper
prints its running entry count every 100 ms, which the Settings pane and the palette show.

`FileIndexCrawler.Crawl` lists folders with `getattrlistbulk`: one call returns hundreds of entries with
their type and mtime, so nothing is stat'd. Up to eight workers share one folder stack behind an
`NSCondition` and stop once it is empty and none is busy. The FSEvents id is read before the crawl starts
and stored in the index, so the first replay covers everything that changed while it ran.

`FileIndexSnapshot` writes the result in **block order**: the roots first, then each folder's children as
one run sorted by name bytes, blocks depth first. A lookup is a binary search per path component, and a
folder's whole subtree is the single range `childStart..<subtreeEnd`.

The layout follows fsearch's to stay small, about 9 bytes per entry plus each distinct name once:

- **Interned names.** An entry holds a name id; each distinct name is stored once with its 64-bit
  character mask. Shared names (`index.js`, `Info.plist`) cost 4 bytes per extra entry.
- **Folder-only fields.** A bitset marks directories, and a rank per 64 entries turns an entry into its
  folder number, so the child range and subtree end exist only for folders.
- **No parent column.** Children are contiguous, so a parent is the owner of the block holding the entry:
  a binary search over the block starts, needed only to build the ~200 paths a search shows.

Per entry that leaves the name id, mtime and prior. The sections are 8-byte aligned, the header bounds
every count before the layout is computed, and the file is written beside its final name and renamed
into place.

## Searching

`FileSearchQuery.prepare` folds the query (lowercase, no diacritics) into terms and ORs their character
masks. `FileIndex.search` runs in two passes, each split across the cores with `concurrentPerform`. The
first scores every **distinct name** once: it skips a name whose mask lacks a query character, then
requires every term as a case-insensitive substring. ASCII names are compared as bytes; a name with
non-ASCII bytes is folded through Foundation first. The second walks the entries and keeps those whose
name matched, adding the entry's prior and applying the type filter. Each chunk keeps its best 200, only
the overall best 200 have their paths built, and the overlay of live additions is scored the same way.

One score orders the results: exact name +4000, name starts with the first term +2000, first term at a
word or camel-case boundary +1000, terms typed in order +1500, first term ending a word +500, the prior
× 1500, minus 4 per name byte. Ties go to the shorter path.

`prior` is set per folder at crawl time and inherited by its files: 2 under home and the cloud drives,
1 elsewhere in plain sight (`/Applications`, `/Users/Shared`), 0 for hidden paths, system folders,
`~/Library` and anything inside a bundle.

An empty query lists **Recent**: the 20 newest files with prior 2, by modification date. The session
keeps those rows across closes and computes them whenever the index is swapped in, so the screen opens
on them at once and refreshes them in the background.

The 2026-10-13 benchmark (`Tests/file-search-performance.swift`, `/System /Applications /Library /usr`,
844,911 entries) crawled in 5.2 s with a 103 MB helper peak and wrote a 16.6 MB index, down from 40 MB
before names were interned and the per-entry folder and parent columns dropped. With whole-module
optimization, queries took 0.3–2.7 ms and single letters 3.4 ms.

## Live updates

`FileSystemWatcher` streams folder-level FSEvents for the roots from the snapshot's event id, with fsearch's
10 ms latency on a user-initiated queue, so a rename shows within a few tens of milliseconds and the
stream never falls behind. A batch that changes the item count asks the main actor to redraw it at most
once a second; any other batch never leaves the events queue. For each
event `FileIndex.apply(folder:)` acts only if the path is an indexed folder; any other event is in an
ignored subtree, or it belongs to a new folder that its parent's event will find. The folder is relisted
through one reused `FileIndexCrawler.Lister` and merged against its block: both sides are sorted by name
bytes, so an unchanged row costs a `memcmp` and allocates nothing. Only a real difference builds a
String: a removed entry is marked dead (a folder's whole subtree range at once), a new one joins the
overlay (a new folder is walked whole), and a new mtime replaces the base row from the overlay. Dates
are compared only for files Recent can list, so cache and log churn elsewhere costs nothing. This
matters on macOS 27, where malloc keeps freed small blocks dirty: replaying a launch's backlog through
per-row Strings left about 30 MB behind, and the merge keeps a cold start level with Spotlight's.
`MustScanSubDirs` rescans a folder recursively. History loss at or above a root, a moved root or more
than 100,000 changes since the snapshot trigger a background rebuild.

## Type filter

`FileSearchFilter` is the header's **All Types** pop-up: All Types, Folders, Documents, Images, Audio,
Videos, Archives. Each case names the `UTType`s it admits. The index records no type, so
`contentType(extension:isDirectory:)` derives one from the extension: a folder whose extension is a
declared package (`.rtfd`, `.pages`) is that document, and any other folder is a folder.

The filter lives on `PaletteState` beside the clipboard's, is reset on every summon, and is never
persisted. ⌘P and the header button open it through `PaletteFilterAction` and the one `PopoverMenu` path
`RootPaletteView` uses for every in-window menu; changing it resets the selection, snaps the scroll and
re-runs the query.

## Scopes and ignore patterns

Scopes are stored tilde-abbreviated in `fileSearchScopes` so a backup taken on one machine still points
somewhere on another; `/` is shown as the startup volume's name. The helper resolves each root with
`realpath`, since FSEvents reports real paths.

`FileSearchIgnoreList` compiles each pattern once into one of three buckets:

| Pattern shape | Matched against | Example |
| --- | --- | --- |
| no `/`, no metacharacters | the entry name, case-insensitively | `node_modules` |
| no `/`, has `*` `?` `[` | the entry name, via `fnmatch` | `*.tmp` |
| contains `/`, or starts with `~/` | the whole absolute path, via `fnmatch` | `~/Movies`, `**/[Cc]ache/**` |

`fnmatch` runs with `FNM_CASEFOLD` and without `FNM_PATHNAME`, so `*` spans `/`. Name patterns read the
NUL-terminated name straight out of the `getattrlistbulk` buffer; a path is only built when a path
pattern exists. **Add Folder…** stores the chosen folder as a `~`-relative path pattern.

## Palette and actions

`FileSearchScreen.rows` is the exact flat selection order rendered by `FileSearchList`. Results sit in a
290pt column beside a preview pane, split by the same `Theme.Colors.separator` hairline the clipboard
draws. The list uses the shared Results header, row metrics, edge dissolve, thin scrollbar and scroll
intent; its header reads **Recent** on the blank screen and **Results** under a query. A row shows
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

The first in-flight query says nothing — the rows it is about to replace would only flash a message — an
empty completed query says what the active filter admits ("No files found", "No images found"), and a
blank screen with no recents says "Type to search files and folders". Without Full Disk Access the screen
says so and ↵ opens the Privacy & Security pane; during the first build it shows the running item count.

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
along with the Full Disk Access status, the index status and **Rebuild Index**, the scope list, the
ignore patterns and the Search Files command row. The lists are ordinary settings carried by Tinycast
settings backups; importing them grants no permission.

`AppCore` observes the switch and asks `FileSearchCoordinator` to project `CommandID.searchFiles` into
the launcher and to start or stop `FileIndexer`; a second observation hands it the new policy when either
list changes. The coordinator also
guards entry into `.fileSearch`, so neither a stale selected command nor the global shortcut can open
the screen after the feature is disabled. Disabling cancels the session and returns an open File Search
screen to the launcher without changing palette visibility.

Search Files is bindable like every other built-in command — `AppEntry.hotKeyAction` answers
`.command(.searchFiles)`, so its launcher row prints a bound chord as a keycap.

This pane is the command's only one: `SettingsTab.ownedCommands` names it, so Settings ▸ Commands
neither lists it nor gates it behind `Enable Commands`. Launcher visibility is `VisibilityStore`'s,
keyed on the entry's `preferenceKey`. The entry behind it comes from
`CommandCatalog.entry(for:)` rather than `AppIndex`, because the index drops the command entirely while
the feature switch is off — exactly when the pane still has to draw the row. Hiding the command leaves
the shortcut working, as it does for every other feature.
