# Floating Note: first vertical slice

**Status:** Superseded by `2026-08-11-markdown-live-editor-design.md`

## Purpose

Add one fast, local floating Markdown note. The first slice validates the capability that makes the
feature distinct: a persistent editor that stays above other applications, grows with its content
without moving its header, and saves directly to a user-visible Markdown file without a database.

The user can open or hide the note from the launcher or a configurable global shortcut, edit literal
Markdown with lightweight source highlighting, reveal its file in Finder, and safely coexist with an
external editor.

## Scope

This slice includes one canonical note, one floating editor window, Markdown-file persistence,
autosave, external-edit detection, a launcher command, a global shortcut, settings-backup coverage,
and a standalone harness.

It deliberately excludes multiple notes, create/browse/search commands, note entries in launcher
search, a Notes settings pane, a feature switch, a menu-bar item, custom storage folders, formatting
toolbars, formatting shortcuts, WYSIWYG editing, rendered images, attachments, sync, encryption,
history, trash, and import/export. The first line has no title semantics while only one note exists.

## Ownership and placement

`AppCore` owns `NotesStore` and lazily constructs `NotesCoordinator`, preserving the single-owner rule
in `docs/architecture.md` and the composition precedent in `Tinycast/App/AppCore.swift`. The store does
no work during launch; the first toggle loads the document.

The feature lives under `Tinycast/Features/Notes/`:

- `Model/NoteDocument.swift` defines the source text, file revision, and repository errors.
- `Model/NoteRepository.swift` owns the canonical path, coordinated reads and writes, atomic saves,
  revision checks, and uniquely named conflict copies. Its storage URL and clock are injected.
- `Model/NoteMarkdownScanner.swift` returns presentation spans over the unchanged UTF-16 source.
- `Model/NoteWindowLayout.swift` decides content-height clamping and top-anchored frames.
- `Service/NotesStore.swift` publishes the loaded draft, dirty/save/conflict state, debounce task, and
  external-file reloads while driving repository work off-main.
- `Service/NoteFileMonitor.swift` watches the canonical file and its directory for external changes.
- `UI/NotesCoordinator.swift` is the feature action surface: toggle, source updates, resizing, reveal,
  retry, and conflict recovery.
- `UI/NotesWindowController.swift` solely owns the panel, focus restoration, placement, and frame.
- `UI/NotesPanel.swift`, `UI/NotesView.swift`, and `UI/NoteEditorView.swift` implement the surface.

`NoteRepository` follows the file identity and source-revision precedent in
`Tinycast/Features/Snippets/Model/SnippetRepository.swift`, but it remains separate: Notes has one
canonical document, continuous autosave, and a different conflict recovery contract.

The Notes view receives `NotesCoordinator` through `@Environment`. It never receives `AppCore` and
never mutates `NotesStore` directly.

## Storage contract

The canonical file is:

```text
~/Library/Application Support/<bundle-id>/Notes/Floating Note.md
```

The repository receives the per-channel application-support URL from the composition root. Debug,
beta, and stable therefore never share files. First open creates the directory and a zero-byte UTF-8
file. The file contains only the editor source: no frontmatter, hidden identifiers, sidecar metadata,
or database record.

Loading captures a revision derived from the file bytes. Saving coordinates access with
`NSFileCoordinator`, revalidates that revision immediately before replacement, and writes atomically.
The new revision is published only after the write succeeds.

## Loading, autosave, and termination

The first toggle begins one load task. A second toggle while loading cancels the pending presentation;
it does not create a second load. The panel is ordered front only after the document and initial editor
height are ready, avoiding a visible empty-to-content resize. Later toggles reuse the loaded store and
are immediate.

An editor change updates the in-memory source immediately, marks it dirty, cancels the previous save
task, and schedules a save after 300 milliseconds without another edit. Repository work runs in a
utility-priority detached task, and only Sendable values cross back to the main actor. There is no
custom actor.

Hiding requests an immediate flush but does not delay ordering the panel out. Application termination
returns `.terminateLater`, awaits the final Notes flush, then replies to AppKit and proceeds through the
existing synchronous teardown. This prevents the debounce window from losing the last keystrokes.

An ordinary I/O failure retains the draft, publishes a fixed warning state, and reports through
Tinycast's `DialogController` with a Retry recovery. Dismissing the dialog never discards text; the next
edit or explicit Retry attempts another save.

## External edits and conflicts

The monitor observes writes, replacements, deletion, rename, and directory recreation. Store generations
discard stale reload results. An event caused by Tinycast's own save becomes a no-op when the on-disk
revision equals the published revision.

When the draft is clean, an external edit reloads the canonical file and updates the editor. External
deletion recreates the canonical empty file and loads it. An unreadable or non-UTF-8 file leaves the
last readable draft in place and reports a failure.

When the draft is dirty, a mismatched revision pauses autosave and enters conflict state. Tinycast asks
through its own failure dialog; the single recovery is **Save Copy & Reload**. Recovery writes the
in-memory source to a unique sibling such as
`Floating Note (Tinycast Conflict 2026-08-11 143012).md`, then loads the latest canonical file.
Dismissing preserves the draft in memory and keeps autosave paused with a fixed warning indicator.
Termination with an unresolved conflict writes the same conflict copy before allowing the process to
exit, so neither version is lost.

## Source-preserving Markdown editor

`NoteEditorView` is an `NSViewRepresentable` backed by
`NSTextView(usingTextLayoutManager: true)`. TextKit 2 is required because its
`usageBoundsForTextContainer` supplies the actual laid-out content height used by the window controller.
SwiftUI's attributed `TextEditor` does not expose that measurement boundary.

The `NSTextStorage` contains only literal source characters and rich-text editing is disabled.
`NoteMarkdownScanner` recognizes headings, bold, italic, strikethrough, inline and fenced code, links,
blockquotes, ordered lists, unordered lists, and task markers. The UI maps its spans to TextKit 2
rendering attributes. Rendering attributes style without modifying text storage, selection, copied
text, or saved output. Delimiters remain visible. Incomplete or unsupported syntax stays plain and can
never block saving.

The consumer shape is:

```swift
NoteEditorView(
    text: notes.sourceBinding,
    onContentHeightChange: notes.resizeEditor
)
```

The binding setter calls `NotesCoordinator.updateSource(_:)`; the view never reaches through the
coordinator to the store.

## Window and visual behavior

`NotesPanel` is borderless, non-activating, floating, shadowed, and key-capable. It joins all Spaces and
full-screen applications, remains visible when it resigns key, and never becomes the main window. The
toggle, Escape, Command-W, and the header close control hide it. Hiding restores the prior external app
or prior Tinycast window when appropriate.

The panel is 520 points wide. Total height is at least 220 points and at most the smaller of 640 points
or 70 percent of its screen's visible height. The controller preserves the top edge while content grows
downward; after the maximum, the editor scrolls internally. The first placement is optically above the
center of the cursor display. AppKit frame autosaving restores its prior position on later launches;
the controller discards the restored size and reapplies the current measured height, then clamps an
off-screen restoration to an available display.

The header is a fixed 44-point band containing the note glyph and title, drag region, fixed-size save or
conflict indicator, Reveal in Finder control, and hide control. Existing content and controls never move
when status changes. The root uses Tinycast's black scrim over `VisualEffectView`, clipped once with a
continuous corner. Only the header controls use Liquid Glass. All new measurements and colors live in
`Tinycast/DesignSystem/Theme.swift`, and dragging reuses
`Tinycast/DesignSystem/Interaction/WindowDragHandle.swift`.

## Launcher and hotkey integration

`CommandID.floatingNote` publishes **Toggle Floating Note** as an ordinary built-in command.
`LauncherCoordinator` hides the palette without restoring focus, then calls `NotesCoordinator.toggle()`.
`HotKeyAction.toggleNotes` is a fixed action dispatched by `HotKeyManager` to the same coordinator.

`AppEntry.hotKeyAction` maps that command, and only that command, to `.toggleNotes`. The existing
Settings → Commands list therefore supplies its `ShortcutRecorder`, item visibility, search, and
conflict checking without a Notes settings pane. The fixed binding is added to `SettingsBackup` beside
the palette, clipboard, and emoji bindings. No legacy hotkey record or migration is introduced.

There is no new `AppEntry.Kind`: this slice publishes a command, not individual note entries or a Notes
launcher section.

## Verification and documentation

`Tests/notes-test.swift`, registered in `Scripts/run-tests.sh`, compiles the shipped Notes model and
service files. It covers channel isolation, first-open creation, Unicode and Markdown round-trips,
debounced last-edit-wins saving, revision conflicts, unique conflict copies, clean external reloads,
dirty external-edit protection, scanner spans without source transformation, and top-anchored height
clamping.

Manual verification covers first and repeated show latency, hotkey and launcher toggling, focus
restoration, click-away persistence, Escape and Command-W, dragging and restoration, growth at both
height limits, scrolling, Reveal in Finder, clean external edits, dirty conflicts, termination during
the debounce window, and rendering over a light desktop without header or content shift.

Completion requires `./Scripts/run-tests.sh`, `./Scripts/lint.sh`, the Model import purity grep, and a
Debug build with no new warnings. The implementation adds `docs/features/notes.md` and updates every
architecture, launcher, hotkey, UI, testing, and development statement made inaccurate by the feature.
`Tinycast.xcodeproj` is regenerated with XcodeGen after the source files are added.
