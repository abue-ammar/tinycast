# Multiple Notes

**Status:** Approved

## Purpose

Extend the approved floating-note vertical slice into an unlimited local note collection without
replacing its editor or turning Notes into a document manager. Tinycast continues to show one compact
floating window, but that window can create, select, rename, search, and delete any number of plain
Markdown notes.

“Unlimited” means Tinycast imposes no note-count limit. Filesystem capacity remains the only storage
limit. Search may cap the number of rows it presents, as the launcher and Search Files already do, but
it examines the complete collection and never prevents another note from being created.

The accepted product decisions are:

- One floating window edits one active note at a time.
- The current editor and overall window treatment stay intact.
- The header title opens a searchable switcher; a small plus control and Command-N create a note.
- Every note is one human-readable Markdown file whose filename is its explicit title.
- Notes publishes **Show Notes**, **Create Note**, and **Search Notes** commands.
- **Show Notes** reopens the last active note and only shows or focuses the window; it never hides it.
- Search matches titles and Markdown contents without a persistent index.
- Delete confirms through Tinycast, then moves the file to the macOS Trash.
- Notes is off by default and follows the complete Search Files enablement pattern.

## Existing boundaries

The first slice in `docs/specs/2026-08-11-floating-note-design.md` established the parts this change
keeps: source-preserving TextKit 2 rendering, top-anchored content growth, lazy filesystem work,
coordinated atomic saves, external-edit detection, dirty-conflict preservation, and termination
flushing. The shipped contract is summarized in `docs/features/notes.md`.

This change replaces the single canonical-file assumption. It does not wrap the old repository or
maintain two storage paths. `NoteRepository` becomes a collection repository, `NotesStore` becomes the
only live collection/editor state, and the existing editor and window controller remain consumers of
the selected document.

The enablement model follows `docs/features/file-search.md`,
`Tinycast/Features/FileSearch/Settings/FileSearchSettingsView.swift`, and
`Tinycast/Features/FileSearch/UI/FileSearchCoordinator.swift`: Settings owns the switch, `AppCore`
observes it, the coordinator projects commands into `AppIndex`, and every invocation is guarded again
at the coordinator boundary.

## Approaches considered

### Collection storage

1. **One titled Markdown file per note, with no index or sidecar — selected.** The directory is the
   collection, the filename is the title, and modified time supplies recency. It preserves direct
   Finder access and the source-only contract while keeping settings backups independent from note
   data.
2. Markdown plus a manifest would provide stable IDs, manual ordering, and pins, but it would create a
   second source of truth and require cross-file recovery whenever a user renames or moves a Markdown
   file externally.
3. SQLite would make indexed content search and metadata transactions easier, but Reveal in Finder
   would no longer expose the canonical source and export would become part of the basic editing path.

The selected design deliberately gives up stable identity across renames. A note's identity is its
relative filename, and a successful rename returns a new identity. No per-note hotkey, launcher item,
favorite, or visibility preference refers to that identity, so nothing external can become stale.

### Window model

1. **One window with an in-window switcher — selected.** It preserves the current interaction and has
   one unambiguous dirty document to flush.
2. One floating window per note would require independent focus restoration, frame persistence,
   monitors, conflicts, and termination state for an unbounded number of windows.
3. A permanent sidebar would make navigation obvious but would materially change the compact UI the
   user has accepted.

## Storage and identity

The collection remains under the channel-specific path injected by `AppCore`:

```text
~/Library/Application Support/<bundle-id>/Notes/
```

Every regular, non-hidden, immediate child whose extension is `.md` is a note. Tinycast does not walk
subdirectories or follow symbolic links. A file added externally appears after the directory monitor
reconciles; a non-UTF-8 file remains visible by filename but reports an error if opened and is skipped
for body search.

The model consists of:

- `NoteID`, a Sendable relative Markdown filename.
- `NoteSummary`, carrying the ID, display title, modification date, and byte count without loading the
  source.
- `NoteDocument`, carrying the ID, literal source, byte revision, and modification date.
- `NoteSearchResult`, carrying a summary, rank, and a short excerpt around the first body match.
- `NotesRepository`, carrying the injected Notes directory and all coordinated filesystem operations.

Display titles are filenames without `.md`. Creating a note starts with `Untitled.md`; collisions use
`Untitled 2.md`, `Untitled 3.md`, and so on. Renaming trims surrounding whitespace and newlines, removes
one trailing `.md` if supplied, and rejects an empty title, `.` or `..`, a leading dot, `/`, or a null
character. It applies the same numeric collision rule using case- and diacritic-insensitive comparison,
even on a case-sensitive volume. The source file contains only editor text—no frontmatter, embedded
identifier, or title line.

The existing `Floating Note.md` is already a valid member of this directory and therefore becomes the
first note through ordinary enumeration. This is not a migration and needs no legacy branch. If the
directory has no notes when a show or create operation first needs a document, the repository creates
`Untitled.md`.

The last active relative filename is local UI state in this Tinycast channel. It is persisted in
UserDefaults but is not an `AppSettings` field and is not exported in settings backups: restoring a
filename without restoring the corresponding note files would be meaningless.

## Repository operations and file safety

`NotesRepository` exposes list, create, load, save, rename, trash, and conflict-copy operations. Its
directory and clock are injected, its model remains Foundation-only, and every blocking operation is
driven from a utility-priority detached task. It validates every resolved URL as an immediate child of
the injected directory before reading or mutating it.

Saving retains the first slice's contract: coordinate access, compare the expected byte revision at
the last responsible moment, then atomically replace. Rename first flushes the active source, then
coordinates the move and rechecks its expected revision before choosing a unique destination. Trash
does the same revision check before calling `FileManager.trashItem`; a newly observed external edit is
never silently removed, even though the Trash remains recoverable.

Switching, creating, renaming, or deleting cannot abandon an in-memory edit. `NotesStore` first flushes
the active document. If the save fails or conflicts, the requested transition does not occur and the
existing recovery dialog remains authoritative. Because there is only one dirty document at a time,
the store never needs an unbounded cache of unsaved drafts.

Conflict copies retain the active title and existing timestamp form, for example
`Project (Tinycast Conflict 2026-08-11 143012).md`. They are ordinary Markdown files, so the next
collection reconciliation exposes them as notes rather than hiding recovered work.

Directory events rescan summaries. A clean external edit to the active file reloads it. A dirty edit
enters the existing conflict flow. If the active file disappears while clean, the store selects the
most recently modified remaining note or creates `Untitled.md` when none remain. With no metadata
identity, an external rename is intentionally observed as one removal plus one addition; the source is
still preserved, but selection may fall back by recency.

## Store, monitor, and lifecycle

`AppCore` remains the sole owner of `NotesStore` and lazily constructs `NotesCoordinator`, as required
by `docs/architecture.md`. Views receive only the coordinator through `@Environment`.

`NotesStore` publishes collection summaries, the active document, save/conflict state, and switcher
search state. The existing monitor is generalized to watch the directory and active file so atomic
replacement, external additions, deletion, and renames all converge through one reconciliation path.
Generation checks continue to prevent stale loads, searches, or rescans from publishing.

Enabling Notes performs no filesystem work. **Show Notes**, **Create Note**, or **Search Notes** is the
first action that may enumerate or create the directory. While the feature is enabled, hiding the
window flushes the active edit but leaves the loaded collection available for an immediate reopen.

Disabling Notes orders the panel out immediately, cancels pending search, flushes the active source,
stops monitoring, and removes the three commands from `AppIndex`. If a flush fails, the draft remains
in the store for retry and termination preservation, but no debounce, search, or monitoring work
continues while disabled. Re-enabling does not show the window; the next command reconciles the
directory before presentation.

Termination awaits the active flush or conflict-copy preservation exactly as the first slice does.

## Settings and command projection

`SettingsTab.notes` appears in the Features section beside File Search. `NotesSettingsView` is a
grouped Form with:

1. A Notes section containing **Enable Notes** and explanatory text. `AppSettings.notesEnabled` is
   false when its preference is absent.
2. A Commands section listing **Show Notes**, **Create Note**, and **Search Notes**. Each row comes from
   `CommandCatalog.entry(for:)`, not `AppIndex`, because the index intentionally omits all three while
   Notes is disabled. Each row uses the same `VisibilityStore` checkbox shown in Settings > Commands.
   A hidden command retains its shortcut.

The command section dims and disables with `.settingsEnabled(settings.notesEnabled)` while the master
switch stays usable. `notesEnabled` is safe to include in `SettingsBackup.SettingsData`: Notes is local,
does no background indexing, and enabling it grants no permission.

`AppCore.observeFeatureSwitches()` tracks `notesEnabled` and calls
`NotesCoordinator.applyEnabled()`. `AppIndex` adds Notes presence to its single built-in command
projection function, preserving the existing Quicklinks and File Search flags rather than rebuilding
one feature in isolation.

The consumer boundary is:

```swift
track({ _ = $0.notesEnabled }, reproject: { $0.notesCoordinator.applyEnabled() })
```

and every public action independently guards the same setting:

```swift
func show() {
    guard settings.notesEnabled else { return }
    // Reconcile, select the last active note, and show or focus the panel.
}
```

## Commands and keyboard behavior

The old singular command and action are replaced, not aliased:

- `CommandID.showNotes` / `HotKeyAction.showNotes` — show the last active note, or bring its window
  forward if already visible.
- `CommandID.createNote` / `HotKeyAction.createNote` — create a uniquely named Untitled note, select
  it, and show the editor.
- `CommandID.searchNotes` / `HotKeyAction.searchNotes` — show the window with its switcher open and
  the search field focused.

All three Settings rows expose their one shared shortcut recorder and launcher visibility checkbox;
the same bindings appear in Settings > Commands and settings backups. There is no compatibility alias
for `floatingNote` or `toggleNotes`, consistent with the repository's latest-only posture.

Inside the Notes window, Command-N invokes the same create path and Command-P opens the switcher.
Escape first closes the switcher when it is open; otherwise it hides the window. Command-W and the
header close control hide the window. **Show Notes** never doubles as a hide operation.

Launcher invocations hide the palette without restoring focus, then call the coordinator. A command
selected immediately after the feature was disabled no-ops at that coordinator guard.

## Editor and switcher UI

The panel width, material, header height, corner treatment, top-anchored resizing, status position,
editor, Reveal control, and close control stay as defined in the first design. The header changes only
where navigation requires it:

- The static title becomes a button showing the active title and opens the switcher.
- A small plus control creates a note.
- Existing status, Reveal, and close controls remain fixed-size and do not shift with save state.

The switcher is a Tinycast-owned overlay inside the existing panel, not a system popover or another
window. It occupies the existing editor region and scrolls within that height, so opening it never
moves the panel's top edge or changes the saved editor size. It contains a search field followed by a
keyboard-navigable list. An empty query lists every note by most recently modified, with title and
modification date but no body read. A query lists ranked title/body matches with an excerpt around the
first body match. Return selects, Command-N creates, Command-Delete asks to move the selected note to
Trash, and a row action begins an inline rename.

Selecting a result closes the overlay and restores editor focus. Renaming updates the header only
after the coordinated move succeeds. Deleting the active note selects the most recently modified
remaining note; deleting the last note creates and selects a fresh Untitled note. All destructive
confirmation and error reporting goes through `DialogController`, never `NSAlert` or SwiftUI `.alert`.
The title, plus control, status, row actions, and search results carry explicit accessibility labels;
selection, rename, create, delete, close, and return-to-editor are all reachable without a pointer.

## On-demand search

Notes creates no search database, filesystem index, background crawler, or launch task. An empty
switcher query uses the already enumerated summaries and does not read every body.

A nonempty query is trimmed and split on whitespace. Search debounces for 120 milliseconds and runs a
single coalescing detached worker, following the cancellation shape documented for File Search. The
worker examines all current Markdown files sequentially, checks cancellation between files, and keeps
only compact result metadata and excerpts. It never retains the entire collection's sources.

Every term must match either the title or literal Markdown source, case- and diacritic-insensitively.
Fuzzy title matches rank above body-only matches; modification date and localized title provide stable
ties. At most 200 rows publish, but the worker evaluates the full collection before ranking, so the
cap is a presentation and memory bound rather than a note or search-scope limit. Unreadable files are
omitted from body matches and remain selectable by an exact or fuzzy title match, where opening them
reports the repository error.

A query revision and cancellation check immediately before publication prevent superseded results
from replacing newer ones. Closing the switcher, hiding the panel, changing the collection, or
disabling Notes cancels the session. The detached search emits a Notes search signpost so large local
collections can be measured without adding persistent telemetry.

## Verification

`Tests/notes-test.swift` continues to compile the shipped model and service sources. Its new coverage
includes:

- enumeration without a count limit and automatic discovery of `Floating Note.md`;
- unique creation and case-insensitive title collisions;
- rename identity changes, save-before-switch, and destination conflicts;
- active selection persistence and fallback after external deletion;
- coordinated Trash revision checks;
- directory reconciliation for external create, edit, rename, and delete;
- title and body search, ranking, excerpts, cancellation, and the 200-row presentation cap;
- feature-disable flush/stop behavior and guarded invocation;
- termination with a dirty active note or unresolved conflict.

Manual verification covers the Settings pane, backup round-trip, synchronized visibility checkboxes
and recorders, disabled shortcut no-ops, Show-versus-hide behavior, Command-N and Command-P, keyboard
switching, inline rename, Trash recovery, Finder edits, panel focus, resizing, and search over a large
synthetic directory. The memory check confirms search retains result excerpts rather than full note
sources.

Completion still requires the full definition of done in `docs/testing.md`: every harness, a warning-
free Debug compile relative to the existing baseline, clean lint, Model import purity, regenerated
Xcode project files, and updates to every feature, launcher, hotkey, backup, settings, UI, architecture,
development, and testing document made inaccurate by this change.

## Deferred

This design does not add multiple simultaneous windows, individual note entries in root launcher
results, a permanent sidebar, manual ordering, pins, tags, attachments, rendered images, formatting
commands, a custom notes folder, sync, encryption, history, internal Recently Deleted, import/export,
or a persistent full-text index. Any of those changes the storage or interaction contract and needs a
separate design.
