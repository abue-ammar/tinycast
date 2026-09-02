# Notes

Notes is an unlimited local collection of plain Markdown files in one persistent floating editor. One
window edits one active note at a time; a title-bar button opens the searchable switcher, and launcher
commands and global shortcuts can show, search, or extend the collection.

## Invariants

- **One regular, non-hidden `.md` file is one note.** Its filename without the extension is its title;
  the source contains no frontmatter, embedded ID, or title field, and there is no database or sidecar.
- **A note the user has not named shows its first line instead.** Only the names `create` claims yield
  it, it is presentation and nothing else, and naming the note replaces it.
- **The editor displays literal source.** The string in `NSTextView`, `NotesStore`, search, and the
  file are identical; there is no parser, projection, preview, or hidden syntax.
- **Only the active note can be dirty.** Switching, creating, renaming, and deleting first flush it, so
  collection navigation cannot abandon an in-memory draft.
- **Tinycast is the only writer.** There is no watcher and no revision check: a save replaces the file
  with what is in the editor. Every show re-lists the folder, so a note added outside appears, but the
  active draft is never re-read from disk.
- **Search is on demand and unindexed.** An empty switcher query reads metadata plus the head of every
  unnamed note; a nonempty query reads bodies sequentially off-main and retains no collection-sized
  source cache.
- **Off means no entry point or Notes work.** The feature is off by default; its shortcuts no-op, its
  commands are absent, and enabling alone does not enumerate or create the Notes directory.
- **The collection may be empty.** Deleting the last note is allowed and creates no replacement; the
  window shows its empty state and Create Note still works from there.
- **The user owns the window size.** AppKit resizes and autosaves the frame; the controller only
  clamps it to the floor below which the title bar's own parts collide.

## Storage and identity

The per-channel directory is:

```text
~/Library/Application Support/<bundle-id>/Notes/
```

`NoteID` is the relative filename. A rename therefore returns a new identity; there are no per-note
launcher items, hotkeys, favorites, or visibility settings that could retain the old one. Immediate
regular `.md` children are sorted by modification date, then localized title. Subdirectories, hidden
files, and symbolic links are ignored.

Create uses `Untitled.md`, then `Untitled 2.md`, and so on, and rename claims a free name by the same
rule. `importNotes` claims one the same way, so a note restored from a backup lands beside the note it
shares a title with rather than over it. Collisions with *another* note are case- and diacritic-insensitive, so `plán` beside `Plan`
becomes `plán 2.md`. A note never collides with itself: only an exact filename match is a no-op, which
is what lets a rename change nothing but the case or the accents. The active filename is local UI state
in UserDefaults and does not ride settings backups.

## Derived titles

A note still carrying a name `create` claimed — `Untitled`, `Untitled 2`, … — shows the first line of
its source that carries visible text. `NoteTitle` owns that rule: leading blank lines are skipped,
Markdown heading markers are dropped, and the line is capped to 120 characters so no row or title bar
has to carry a paragraph. `NoteSummary.title` remains the filename; `displayTitle` is what every
surface renders — switcher rows and their VoiceOver labels, the Trash confirmation, the window title,
and the title band of `NoteSearch`, so a fuzzy query reaches a note nobody has named.

`list()` reads at most 4 KB of each unnamed note to derive it, and a named note costs nothing beyond
the enumeration it already pays for. The **active** note derives from the live draft rather than the
last listing, so its window title follows the first line as it is typed while its switcher row catches
up on the next autosave. Renaming edits the filename, so the rename field starts from `title`: a
derived line stands in for a name, and is never one.

`NotesRepository` owns list, create, load, save, rename, Trash, and search reads. Every
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
invalidates pending presentation work, cancels search, flushes the draft, and removes the commands. A
failed flush retains the draft for retry.

## Commands, switcher, and window

- **Show Notes** selects the last active note and shows or focuses the panel without toggling it closed.
- **Create Note** creates and selects one unique Untitled note, including from an empty channel.
- **Search Notes** shows the same panel with the switcher open and its search field focused.

Command-N creates, Command-P opens or refocuses the switcher, Command-O opens the Notes folder, Escape
closes the switcher before hiding, and Command-W and the red traffic light both hide directly. Hiding
restores the prior external application or Tinycast window and flushes without delaying the order-out —
but only while that app is still the frontmost one, so closing a window the user has already left behind
leaves them in whatever app they moved to.
Command-Q is bound to nothing app-wide, so no chord over Notes can quit Tinycast.

Both windows are one `NotesPanel`, a non-activating floating panel that owns the Escape rule and reads
⌘⌫. They differ only in style mask and in the `commandChords` their controller installs: the note window
claims ⌘N, ⌘P, ⌘O and ⌘W, and the switcher reads ⌘N plus ⌘W and ⌘P as dismissals.

AppKit draws the note window's chrome. Its 52-point title bar holds the traffic lights, the centred
active title, and one frosted capsule of Create, Browse, and Open Folder. The title is drawn, not
native, so it centres on the window; it is not hit-testable, so dragging it moves the window.

The switcher is a borderless child window centred on its host and hung below the title bar, not an
in-window screen — a note window may be 180pt tall, and the list must not be. It carries the same glass
surface as a `PopoverMenu`, and its 240-point height is a ceiling rather than a size: the list reports
its own height and the window shrinks to it with the top edge pinned. It travels with its host, dismisses
like a popover when it resigns key, and closes outright when the last note goes. An empty query lists
metadata by recency; a nonempty query searches titles and literal bodies after a 120-millisecond
debounce. Results are capped at 200, and generation checks prevent superseded search or selection work
from publishing.

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

An empty note shows a `Start writing…` placeholder aligned to the 16-point text container inset, and a
footer under the editor reports the character count straight off `NSTextStorage.length`. Both belong to
the editor surface, so neither appears when no note is active.

## Autosave

Editor changes update the main-actor draft immediately and debounce save for 300 milliseconds. Only the
active source is retained. A successful save refreshes metadata ordering; switching waits for the same
flush before loading another source. Termination awaits that flush before the app exits, but never
vetoes the quit.

**A save overwrites whatever is on disk.** There is no watcher, no revision comparison and no conflict
state: editing the *active* note in another app while Tinycast has it open loses that edit the next time
the debounce fires. Open Notes Folder (⌘O) invites exactly that, and this is the accepted trade for a
feature whose whole job is one local editor. Every other external change is picked up, because showing
the window re-lists the folder before it presents anything.

## Verification

`Tests/notes-test.swift` compiles the shipped Notes model and service sources with the real fuzzy
matcher. It covers repository safety, unique-name claiming, derived titles, search, selection,
autosave, empty collections, switcher interaction, and cancellation.

`Tests/notes-editor-test.swift` uses real TextKit 2 and AppKit undo objects to cover literal source,
native Cut/Copy/Paste, Unicode and marked text, and undo isolation. Window chrome is not automated:
the Notes manual sweep in `docs/testing.md` covers commands, shortcuts, switcher, focus restoration,
Finder, Trash recovery, and accessibility.
