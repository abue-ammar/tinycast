# Notes

Notes is an unlimited local collection of plain Markdown files in one persistent floating editor. One
window edits one active note at a time; its title opens the searchable switcher, and launcher commands
and global shortcuts can show, search, or extend the collection.

## Invariants

- **One regular, non-hidden `.md` file is one note.** Its filename without the extension is its title;
  the source contains no frontmatter, embedded ID, or title field, and there is no database or sidecar.
- **The editor displays literal source.** The string in `NSTextView`, `NotesStore`, search, conflicts,
  and the file are identical; there is no parser, projection, preview, or hidden syntax.
- **Only the active note can be dirty.** Switching, creating, renaming, and deleting first flush it, so
  collection navigation cannot abandon an in-memory draft.
- **A save never overwrites an unseen external edit.** `NotesRepository` coordinates the mutation and
  compares the byte revision immediately before atomic replacement, rename, or Trash.
- **Search is on demand and unindexed.** An empty switcher query reads metadata only; a nonempty query
  reads bodies sequentially off-main and retains no collection-sized source cache.
- **Off means no entry point or Notes work.** The feature is off by default; its shortcuts no-op, its
  commands are absent, and enabling alone does not enumerate or create the Notes directory.
- **The top edge is the resize anchor.** `NotesWindowController` alone owns the frame while the active
  document grows or shrinks and scrolls after its screen-aware maximum.

## Storage and identity

The per-channel directory is:

```text
~/Library/Application Support/<bundle-id>/Notes/
```

`NoteID` is the relative filename. A rename therefore returns a new identity; there are no per-note
launcher items, hotkeys, favorites, or visibility settings that could retain the old one. Immediate
regular `.md` children are sorted by modification date, then localized title. Subdirectories, hidden
files, and symbolic links are ignored.

Create uses `Untitled.md`, then `Untitled 2.md`, and so on. Rename uses the same collision rule with
case- and diacritic-insensitive comparison. `Floating Note.md` is already a valid note and needs no
migration. The active filename is local UI state in UserDefaults and does not ride settings backups.

`NotesRepository` owns list, create, load, save, rename, Trash, conflict-copy, and search reads. Every
URL is validated as an immediate child of the injected directory. It lives in `Service/` because it
performs filesystem effects; `NotesStore` drives its blocking work from detached tasks.

## Ownership and enablement

`AppCore` owns `NotesStore` and lazily constructs `NotesCoordinator`. `NotesView` receives only the
coordinator through `@Environment`; it never receives `AppCore` or mutates the store.

Settings > Notes owns `AppSettings.notesEnabled`, which is false when absent. The pane lists **Show
Notes**, **Create Note**, and **Search Notes** from `CommandCatalog`, so it can still render them while
`AppIndex` omits them. Every row shares its `VisibilityStore` checkbox and `HotKeyAction` recorder with
Settings > Commands.

`AppCore` observes enablement and calls `NotesCoordinator.applyEnabled()`. Disabling hides the panel,
invalidates pending presentation work, cancels search, flushes the draft, stops monitoring, and removes
the commands. A failed flush retains the draft for retry and termination preservation.

## Commands, switcher, and window

- **Show Notes** selects the last active note and shows or focuses the panel without toggling it closed.
- **Create Note** creates and selects one unique Untitled note, including from an empty channel.
- **Search Notes** shows the same panel with its compact in-window switcher focused.

Command-N creates, Command-P opens or refocuses the switcher, Escape closes the switcher before hiding,
and Command-W hides directly. Hiding restores the prior external application or Tinycast window and
flushes without delaying the order-out.

The fixed header contains the note glyph, active-title switcher button, save/conflict state, Create,
Reveal, and Hide controls. The icon, title, and empty header surface move the window; a title click still
opens the switcher, while buttons remain isolated from dragging. The switcher replaces only the editor
region and never changes the frame. An empty query lists metadata by recency; a nonempty query searches
titles and literal bodies after a 120-millisecond debounce. Results are capped at 200, and generation
checks prevent superseded search or selection work from publishing.

Arrow keys and Return do not intercept an inline rename. Command-Delete moves the selected row to Trash
only while the switcher is not renaming; in the editor and title field it remains a native text command.
After confirmation, Trash chooses its successor from the current visible ordering. Each row exposes
VoiceOver actions to activate, rename, and move the actual note title to Trash.

## Plain editor

`NoteEditorView` is one TextKit 2 `NSTextView` inside an `NSScrollView`. It installs
`NoteEditorInput.source` directly as `NSTextView.string` with one system font and Tinycast's note color.
Markdown markers remain visible and receive no syntax highlighting, rendered typography, controls, or
link behavior.

AppKit owns typing, selection, Cut, Copy, Paste, Select All, Find, marked-text input, emoji, combining
characters, and undo/redo. The only `NoteTextView` customization supplies a document-owned undo manager.
Changing the note identity or editor epoch replaces the literal string and clears the previous
document's undo history; ordinary edits keep native undo grouping.

The editor reports laid-out content height with the note identity and epoch that produced it. The
coordinator rejects stale reports, and the window controller skips redundant frame assignments so
editing near the bottom does not reset the viewport. Height comes from the laid-out fragment extent
because TextKit's aggregate usage bounds can retain deleted geometry. Content first consumes the editor
space inside the 220-point minimum, then grows downward while preserving the top edge; deletions shrink
naturally back to the minimum. The panel observes a 16-point vertical screen margin when possible,
clamps fully onto unusually short screens, and scrolls after its 640-point cap.

## Autosave and external changes

Editor changes update the main-actor draft immediately and debounce save for 300 milliseconds. Only the
active source is retained. A successful save refreshes metadata ordering; switching waits for the same
flush before loading another source.

`NoteFileMonitor` watches both the directory and active file because atomic saves replace the file.
Directory events rescan summaries. A clean active-file edit reloads; a dirty revision mismatch pauses
autosave and offers **Save Copy & Reload**. Conflict copies retain the title and become ordinary notes
after reconciliation.

An external rename is a removal plus an addition because filenames are identity. If the active clean
file disappears, the store selects the most recently modified remaining note or creates Untitled. A
dirty disappearance enters conflict. Termination awaits the active save or writes the same conflict copy
before allowing the app to exit.

## Verification

`Tests/notes-test.swift` compiles the shipped Notes model and service sources with the real fuzzy
matcher. It covers repository safety, search, selection, autosave, external reconciliation, conflict
recovery, switcher interaction, cancellation, and top-anchored screen-aware layout.

`Tests/notes-editor-test.swift` uses real TextKit 2 and AppKit undo objects to cover literal source,
native Cut/Copy/Paste, Unicode and marked text, undo isolation, document-scoped height reports, and
content measurement. `Tests/notes-editor-performance.swift` measures the shipped per-edit path with a
250,000-character plain note. The Notes manual sweep in `docs/testing.md` covers commands, shortcuts,
switcher, focus restoration, Finder, Trash recovery, external changes, sizing, and accessibility.
