# Notes

Notes is an unlimited local collection of plain Markdown files in one persistent floating editor, which
renders the Markdown in place. One window edits one active note at a time; a title-bar button opens the searchable switcher, and launcher
commands and global shortcuts can show, search, or extend the collection.

## Invariants

- **One regular, non-hidden `.md` file is one note.** Its filename without the extension is its title;
  the source contains no frontmatter, embedded ID, or title field, and there is no database or sidecar.
- **A note the user has not named shows its first line instead.** Only the names `create` claims yield
  it, it is presentation and nothing else, and naming the note replaces it.
- **The storage is the source.** The string in `NSTextView`, `NotesStore`, search, and the file are
  identical; rendering is attributes and drawing over that string, never a second string or an offset
  map.
- **The caret's line is raw.** Every line under the selection shows its Markdown; an unfocused editor
  reveals nothing.
- **Styling never reaches undo.** Attribute passes bypass `shouldChangeText`; every edit a Markdown
  gesture makes goes through `NoteTextView.performEdit`.
- **Render Markdown off is the literal editor**, with native Return, Tab and shortcuts and no parsing.
- **The formatting bar is another way to press a shortcut.** Each button sends its chord's
  `NoteEditAction` through `NoteTextView.format`, so it has the chord's gate, undo step and autosave,
  and a button is lit exactly when its toggle would remove that formatting.
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
- **The editor is the one surface snippets expand into.** `NoteTextView` adopts `InjectableTextView`,
  so a typed keyword — and the Snippets browser's ↵ — is written straight into the text storage
  rather than posted as events at whichever app happens to be frontmost. Nothing else in Tinycast
  adopts it: see [snippets.md](snippets.md#text-delivery-and-pasteboard-safety).

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
its source that carries visible text. `NoteTitle` owns that rule: blank, rule and fence lines are
skipped, block and inline Markdown markers are dropped whether or not rendering is on, and the line is
capped to 120 characters so no row or title bar has to carry a paragraph. `NoteSummary.title` remains the filename; `displayTitle` is what every
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
`AppIndex` omits them. It is their only pane: `SettingsTab.ownedCommands` names the three, which takes
them out of Settings > Commands and out of reach of `Enable Commands` — Notes' own switch is the one
that decides they exist.

`AppCore` observes enablement and calls `NotesCoordinator.applyEnabled()`. Disabling hides the panel,
invalidates pending presentation work, cancels search, flushes the draft, and removes the commands. A
failed flush retains the draft for retry.

## Commands, switcher, and window

- **Show Notes** toggles the panel: it selects the last active note and shows it, or hides a visible one.
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

## Editor

`NoteEditorView` is one TextKit 2 `NSTextView` inside an `NSScrollView`. It installs
`NoteEditorInput.source` as `NSTextView.string` and never swaps that string for a display version.
Rendering is attributes and drawing over the source.

### Parsing

`Model/NoteMarkdownParser` splits the source on the same boundaries as `NSString.lineRange(for:)`, so
one line is one TextKit paragraph. `NoteMarkdown` gives each line its kind, UTF-16 ranges for its
content, block marker and task checkbox, and a list level from an indent stack. A source ending in a
terminator, and an empty source, get a final zero-length line, so a caret on the empty last row sits on
a real line like any other. Inline spans are not stored: `NoteMarkdown.inlines(of:)` scans the one line
asked for, which is all the styler, the editing rules and `NoteTitle` ever need.

It covers headings 1 to 6 (4 to 6 look like 3), bold, italic, bold italic, strikethrough, inline code,
links, bare `http` and `https` URLs, bullet, numbered and task lists with nesting, quotes, fenced code
blocks and horizontal rules. Inline spans never cross a line. Images, underline, HTML, setext headings,
indented code, footnotes, reference links and blocks nested inside quotes stay plain text. A GFM table
(a pipe row, a delimiter row with as many cells, then the pipe rows after it) also stays plain text, but
is recognised so it gets no inline styling: it shows in the code font, with wrapped rows hanging under
their first line, and a delimiter row typed under existing rows restyles all of them.
The whole note is reparsed on each edit. The AI chat's `MarkdownBlock` is a separate read-only parser
and is not shared.

### Rendering

`UI/NoteMarkdownRenderer` holds the parse and the set of revealed lines, and is the text storage's
delegate. Every mutation reports its edited range and length delta there, including the undo, redo and
marked-text ones that post no `textDidChange`, and several are folded into one pending edit.
`textDidChange`, `textViewDidChangeSelection` and any read of the parse consume it and reparse. The
edited lines and one neighbour on each side are restyled, widened to the rest of the note when a fenced
block moved and to any list line whose depth changed.

`NoteMarkdownStyler` turns one line into attributes. `NoteMarkdownTypography` sets the body one
system text style up (title3) and headings at largeTitle, title1 and title2, with or without
rendering; Interface Size does not scale Notes. A hidden marker gets a 0.01-point system font and
a clear colour, so it stays in the string at almost no width. Fence and rule lines are cleared at their
normal font instead, so they keep their row height. Every list item (bullet, numbered or task) gets 8
points of space after it, rendered or revealed, so items read as separate rows and moving the caret
never shifts them; a wrapped item keeps normal line spacing. A restyle writes straight to `NSTextStorage` inside
`beginEditing` and `endEditing`, then invalidates layout for those lines. It never calls
`shouldChangeText`, which is what keeps styling off the undo stack.

`NoteRevealPolicy` picks the lines that show raw Markdown: every line under the selection, plus both
fences of a code block the selection is in. Nothing is revealed unless the editor is first responder in
the key window. Revealed markers use `textTertiary`. During a drag selection the reveal waits for
mouse-up, because revealing moves text under the pointer. A revealed list or quote line hangs its
marker left of the content indent, so its text stays where the rendered line had it. Since the caret's line is always raw, the
caret never sits inside hidden text and the arrow keys need no special handling.

### Block drawing

`NoteLayoutFragmentProvider` is the text layout manager's delegate. A paragraph whose first character
carries a `NoteBlockDecoration` is laid out by `NoteBlockLayoutFragment`, which draws code bands with
their language label, quote bars, rules, bullets, the source's own list numbers, and checkboxes, all
list markers in a neutral gray. Vertical
spacing comes from paragraph styles: overriding the fragment's frame would leave the caret above the
glyphs. There are no text attachments, overlay controls, `NSTextList`, `NSTextTable` or private API.

### Editing

`Model/NoteMarkdownEditing` turns a gesture into a `NoteEditPlan`, one replacement plus the selection
after it. Nil means AppKit handles the key natively. `NoteTextView.performEdit` applies a plan through
`shouldChangeText`, `replaceCharacters` and `didChangeText`, so each gesture is one undo step and
reaches autosave.

- Return continues a list or quote and leaves it on an empty item. Tab and Shift-Tab nest list items
  by four spaces. Backspace at an item's content start outdents it, then removes its marker. These
  edits renumber the ordered run they touch in the same undo step.
- Typing `[] ` or `[ ] ` at the start of a paragraph makes `- [ ] `.
- ⌥⌘C wraps the touched lines in a fenced block, or removes the fences of the block the selection is
  in. On an empty line it opens an empty block with the caret inside.
- ⇧⌘B adds `> ` to each touched line, or removes one `>` from each when all of them are quotes. Blank
  lines inside a selection, code, tables and rules are left alone.
- Pasting a single `http` or `https` URL over text selected on one line makes `[text](url)`.
- Clicking a checkbox toggles `[ ]` and `[x]` without moving the caret. The hit test uses
  `NoteCheckboxGeometry`, the rect the fragment draws, grown by 3 points.
- Clicking a rendered link opens it, unless the click lands in the outer 30% of the label's first or
  last glyph, which places the caret. Only `http`, `https` and `mailto` open. A revealed line carries
  no link attribute, so its URL is edited as text.

| Shortcut | Does |
| --- | --- |
| ⌘B, ⌘I, ⌘E | bold, italic, inline code |
| ⇧⌘X | strikethrough |
| ⌥⌘C | code block |
| ⇧⌘B | quote |
| ⌘K | link |
| ⇧⌘7, ⇧⌘8, ⇧⌘9 | numbered, bullet, task list |
| ⌥⌘1, ⌥⌘2, ⌥⌘3 | heading 1, 2, 3 |
| ⌥⌘0 | plain paragraph |

Digits match by key code. The text view sees these chords before `NotesPanel` claims its own, and none
collide. In a note, ⌘E replaces AppKit's Use Selection for Find.

AppKit still owns typing, selection, Cut, Copy, Paste, Select All, Find, marked text, emoji, combining
characters and undo grouping. Copy yields raw Markdown and VoiceOver reads the source. Changing the note
identity or editor epoch reinstalls and restyles the string and clears the previous document's undo
history. Snippets expand through `insertText` and are styled like typed text.

### The formatting bar

While Render Markdown and Show Formatting Bar are both on, the band under the editor holds the
formatting bar at its leading edge and the character count at its trailing edge. The bar is
`NoteFormattingBar`, a frosted capsule in the title bar's recipe. It starts collapsed to one round
`paintbrush` button; ⌥⌘T or a click expands it, and the buttons slide out from behind that button:
a heading menu, Bold, Italic, Strikethrough, Inline Code and Link, then Code Block and Quote, then
Numbered, Bullet and Task List. Hovering a button shows its name and shortcut. Each button is a
28-point square, so the whole row fits the smallest window. The count hides when the row leaves it no
lane, and the band never widens the note.

Expanded or collapsed is window state, not a preference: `AppCore` reads and writes it under
`notesFormattingBarExpanded` in `UserDefaults` and hands it to `NotesCoordinator`, the way it hands
the store the active note's filename. It is deliberately not an `AppSettings` key, so no settings
backup carries it. With Show Formatting Bar off there is no round button at all and the count returns
to its own footer.

`NoteEditorView` reports `NoteMarkdownEditing.formatting(source:selection:markdown:)` on every
install, edit and selection change, and `NotesCoordinator` publishes it only when it changed. That
function uses the same span and line rules as the toggles, so a lit button always undoes. A click goes
`NotesCoordinator.format` → `NotesWindowController.format` → `NoteTextView.format`. The buttons never
take focus, so the caret and its revealed line stay put.

The heading button opens `NoteHeadingMenuView` (Heading 1 to 3 and Text, the current one checked) in a
borderless child window that never becomes key, so it can extend past a short note window while the
editor keeps its caret and chords. It closes on a choice, Escape, any mouse down in the note window,
an edit, the note window losing key, and hiding. It is a copy of the popover menu's row look, because
`PopoverMenu` depends on palette state.

### The setting

Settings > Notes > **Render Markdown** is `AppSettings.notesRendersMarkdown`, on when absent and carried
by settings backups. `NotesCoordinator` exposes it and `NotesView` hands it to `NoteEditorView`. Off
gives the literal editor: one font and colour, native Return, Tab and shortcuts, and no parsing.
Flipping it restyles the open note without touching its undo history or marking it dirty.

Settings > Notes > **Show Formatting Bar** is `AppSettings.notesShowsFormattingBar`, on when absent and
carried by settings backups. It only takes effect while Render Markdown is on, and its row is disabled
otherwise.

An empty note shows a `Start writing…` placeholder aligned to the 16-point text container inset. The
character count comes straight off `NSTextStorage.length` and sits in a footer under the editor, or at
the trailing end of the formatting bar's band while the bar shows. Both belong to the editor surface,
so neither appears when no note is active.

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
autosave, empty collections, switcher interaction, and cancellation, plus the Markdown parser, every
edit plan, the formatting each selection reports and the reveal policy.

`Tests/notes-editor-test.swift` uses real TextKit 2 and AppKit undo objects. It runs the native
Cut/Copy/Paste, Unicode and marked-text cases with rendering off and on, and covers undo isolation, an
exact source after styling, hidden and revealed markers, restyling after edits and after undo, block
decorations and layout fragments, list keys, chords, the task rule, checkbox toggles, link schemes,
pasting a URL, and the formatting reports and `format(_:)` the formatting bar uses.
`Tests/notes-editor-performance.swift` times install, typing and caret moves on a
100,000-character note; its budget is in `docs/testing.md`. Window chrome is not automated:
the Notes manual sweep in `docs/testing.md` covers commands, shortcuts, switcher, focus restoration,
Finder, Trash recovery, and accessibility.
