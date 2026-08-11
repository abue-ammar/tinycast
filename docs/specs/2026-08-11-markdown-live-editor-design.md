# Markdown Live Editor

**Status:** Approved

## Purpose

Evolve Notes from source highlighting into a native, Typora-style live Markdown editor while keeping
the current floating window, literal Markdown files, autosave, conflicts, and unlimited-note model.
The visual reference is
[`pluk-inc/markdown-preview`](https://github.com/pluk-inc/markdown-preview): inactive Markdown syntax
recedes, the construct reads close to rendered content, and placing the caret inside it reveals the
source needed to edit it.

Tinycast adopts that interaction, not the reference implementation. Markdown Preview uses CodeMirror
inside `WKWebView`; Tinycast remains Swift, AppKit, TextKit 2, and zero-dependency. The exact Markdown
source remains the only value sent to `NotesStore` and saved by `NotesRepository`.

The accepted product decisions are:

- Inactive Markdown markers genuinely collapse from layout and reappear when the caret enters their
  construct. Invisible source-width gaps are not an acceptable approximation.
- Formatting is available through keyboard shortcuts and a small Tinycast-owned overlay opened from
  a new header button.
- The supported first phase is headings, emphasis, strikethrough, links, blockquotes, unordered and
  ordered lists, task lists, horizontal rules, inline code, and fenced code blocks.
- Inactive task markers become clickable checkboxes that update the literal `[ ]` or `[x]` source.
- Inactive links show their label; entering the link reveals its complete source, and Command-click
  opens the destination.
- Image syntax remains styled source. Tinycast does not load or render images in this phase.
- The implementation remains native TextKit 2 with no third-party parser, editor, or web view.
- The existing floating, content-sized, top-anchored Notes panel remains the only surface.
- The header uses the `textformat` symbol and opens the Tinycast-owned formatting overlay.

## Existing boundaries

The collection, persistence, and lifecycle contracts in
`docs/specs/2026-08-11-multiple-notes-design.md` do not change. One active note can be dirty; editor
transactions flow through the same 300-millisecond autosave, coordinated revision check, conflict
recovery, monitor, and termination flush described in `docs/features/notes.md`.

`Tinycast/Features/Notes/UI/NoteEditorView.swift` already creates a TextKit 2 `NSTextView`, disables
rich text and automatic substitutions, and applies presentation attributes. The live editor replaces
that simple presentation path. `NoteMarkdownScanner` is replaced rather than retained as a parallel
syntax system.

The current editor binding carries only a `String`. That is insufficient because a note switch or an
authoritative external reload must invalidate selection and undo state even when ordinary editor echoes
must not. The view receives a transient `NoteEditorInput` containing the active `NoteID`,
literal source, and an editor epoch. `NotesStore` increments the epoch only when it installs an
authoritative document: initial load, note switch, clean external reload, conflict recovery, or a new
document replacing the active one. Typing and save completion do not increment it. The coordinator
passes source changes back through one callback instead of turning the entire input into a writable
binding, and the epoch is never persisted.

The layering remains the one in `docs/architecture.md`:

- Foundation-only parsing, projection, range mapping, and edit planning live under
  `Features/Notes/Model/`.
- AppKit text input, TextKit layout, hit testing, selection, accessibility, and editing transactions
  live under `Features/Notes/UI/`.
- Opening a resolved destination is an AppKit effect under `Features/Notes/Service/`, following
  `QuicklinkLauncher` rather than placing `NSWorkspace` in `NotesCoordinator`.
- `NotesCoordinator` remains the only Notes action surface reached by SwiftUI.
- `AppCore` gains no competing owner. `NotesStore` owns only the authoritative editor epoch added to
  its existing active-document state.

## Chosen editor architecture

### Why rendering attributes alone are rejected

TextKit 2 rendering attributes can change drawing, but they do not remove the source glyphs from line
geometry. Making `](destination)` clear or nearly zero-sized therefore leaves the source width in the
line. It cannot produce the accepted collapsed-link or collapsed-marker behavior.

The live editor consequently does not claim that `NSTextView.string` is canonical source. It uses a
native display projection and an explicit bidirectional map. This is more machinery than source-backed
rendering attributes, but it is the only selected approach that satisfies both genuine Typora-style
collapse and the native TextKit 2 constraint.

### Canonical source and display projection

A proposed Foundation-only `NoteDisplayProjection` derives four values from literal source, the parsed
presentation, and the active construct:

- a display string laid out by `NSTextView`;
- display styling spans;
- ordered mapping segments between UTF-16 source and display ranges;
- display anchors for controls and non-text decorations.

Mapping segments are identity, elision, or replacement segments. Identity segments map source and
display offsets one-to-one. Elisions map concealed source to a display boundary with explicit upstream
and downstream affinity. Replacements map a source range to display content such as a bullet, checkbox
placeholder, or horizontal-rule placeholder. The map exposes source-to-display and display-to-source
selection conversion, editing-range conversion, and copy-range conversion; no UI caller performs its
own offset arithmetic.

`NoteTextView` contains only the current display projection. A proposed `NoteEditorEngine`, owned by the
view coordinator, owns canonical source, parse state, projection generation, canonical source
selection, composition state, and the active document identity. Every text input, formatting action,
checkbox toggle, copy, cut, paste, undo, and redo passes through that engine before the source binding
is called.

The projection is recreated only where presentation changed. A normal source edit reparses and patches
the affected block region. Activating or leaving a construct replaces only the old and new construct
projections. The complete display buffer is built on document load, but ordinary caret movement never
rebuilds the document.

### Feasibility gate

Implementation begins with a narrow TextKit 2 slice using the real mapping and transaction types. That
slice and its regression harness remain part of the shipped implementation; they are not a throwaway
alternate editor. Before the remaining syntax work starts, it must prove all of these:

- `**bold**` and `[label](destination)` occupy only their rendered display width while inactive;
- pointer placement, arrow movement, selection, deletion, and insertion map to the intended source;
- entering and leaving a construct preserves the canonical caret through projection changes;
- ASCII input, emoji, combining marks, and one marked-text input method commit exact source;
- copy, cut, paste, undo, and redo preserve exact Markdown;
- switching to a shorter note and invoking Undo cannot address the previous note's ranges.

If the native projection cannot pass this gate, implementation stops and this design returns for a
product decision. It must not fall back to invisible gaps, ship two editor modes, or introduce WebKit
without explicit approval.

## Markdown presentation model

`NoteMarkdownScanner` is replaced by a Foundation-only `NoteMarkdownParser`. It returns a
`NoteMarkdownPresentation` containing semantic content spans, marker ranges, complete construct ranges,
line-level block state, task state, link parts, image ranges, and fenced-code metadata. Ranges use
`NSRange` because the editor boundary is UTF-16.

The supported grammar is deliberately explicit:

- ATX headings recognize levels 1 through 6; formatting controls insert levels 1 through 3.
- Emphasis recognizes paired `*` or `_`, strong recognizes paired `**` or `__`, and strong emphasis
  recognizes paired triples. Intraword underscores remain literal.
- Strikethrough recognizes paired `~~`; inline code recognizes matching backtick runs.
- Inline links recognize escaped brackets, one level of balanced brackets in labels, balanced
  parentheses in destinations, and an optional quoted title. Reference links remain literal.
- Blockquotes and list items may be nested by repeated valid prefixes. Formatting commands change only
  the outermost selected prefix.
- A horizontal rule requires at least three matching `*`, `-`, or `_` markers with optional spaces and
  no other content. A list marker followed by content wins the list interpretation.
- Fences use at least three matching backticks or tildes. A closer uses the same character and at least
  the opener length. An unmatched opener treats the remainder as fenced content so inline parsing is
  suppressed to end of source.
- Backslash-escaped delimiters are literal. Unsupported, incomplete, or ambiguous syntax receives base
  source presentation.

Fenced and inline code suppress nested inline parsing. Images are recognized only enough to style the
literal source and are never projected into image content. Tables, HTML blocks, footnotes, frontmatter,
math, Mermaid, and reference-style definitions are outside this phase.

The parser keeps a source-line index and the entering parser state for each block. After an edit it
reparses from the nearest preceding stable block boundary until the emitted records and outgoing state
match the previous cache. Edits to an unmatched fence can invalidate through end of source; that is the
documented worst case. The pure parser accepts the complete source plus the prior parse and edited range,
and returns both the new presentation and invalidated source range.

## Caret-aware projection

A construct is active only while the editor is first responder, the primary source selection is a
caret, and that caret lies in the construct. A range selection retains live presentation so Command-A
and drag selection do not expose every marker. When overlapping constructs contain the caret, the
smallest complete construct is active and its ancestors reveal only markers needed to keep the active
source legible.

Inactive projection rules are:

- Heading content uses the title hierarchy and its `#` prefix is elided.
- Strong, emphasis, strikethrough, and inline-code markers are elided while their content is styled.
- A link projects its label only. Activating the label replaces that projection with the complete
  literal link source.
- Blockquote prefixes are elided and represented by indentation, quote color, and a leading rule.
- Unordered markers project as bullets; ordered markers retain their authored number.
- A task marker projects to one fixed-width checkbox placeholder.
- A horizontal-rule source line projects to one rule placeholder.
- Fence lines and optional language labels are elided while fenced content keeps its code treatment.
- Image syntax remains styled literal source and has no projection or side effect.

The active construct uses identity mapping for its complete source range. Reprojection converts the
canonical source selection into the new display selection, restores first responder, and scrolls the
caret into view. The editor snapshots the visible caret rectangle before reprojection and adjusts the
scroll origin by the resulting delta when possible, preventing an activation above the caret from
jumping the viewport. The panel's top edge remains fixed while content height changes.

Display attributes and decorations never call the source binding, register undo, or dirty the note.
The canonical source is the value used for save, search, conflict recovery, and explicit copy/cut
operations. Command-A followed by Copy always returns the complete literal Markdown. A partial visible
selection maps character-precisely; when it covers an entire projected construct, copy includes that
construct's elided delimiters so the copied fragment remains valid Markdown.

## Editing transactions, IME, and undo

`NoteEditorEngine` is the only unit allowed to mutate canonical source. A transaction contains the
document identity and epoch, projection generation, source replacement range, replacement string, and
source selections before and after. It revalidates all ranges, applies one source replacement, patches
the parse and projection, emits the source binding exactly once, and registers one inverse operation.

The text view's automatic character undo registration is disabled because its display ranges are not
canonical. The editor uses the window's native `UndoManager` with canonical inverse transactions.
Typing coalesces with adjacent typing using normal AppKit undo grouping; formatting and checkbox actions
each form one group. Undo and redo run through the same transaction path and therefore update autosave
exactly once.

When `NoteEditorInput.id` or `epoch` changes, the engine ends composition, installs the authoritative
source, resets projection and selection, calls `removeAllActions()` on its undo manager, and starts a new
undo generation. A view update echo carrying the same identity, epoch, and source is ignored. An unexpected
same-epoch source mismatch is treated as authoritative, resets undo defensively, and is covered by a
diagnostic assertion in Debug builds.

Marked-text composition has an explicit protected mode. Before the first marked replacement, the engine
reveals the containing source construct and records its mapped source range. While `hasMarkedText` is
true, it lets TextKit manage the marked display segment, freezes projection changes, removes controls
intersecting that segment, and rejects formatting or checkbox commands. It does not reset text,
selection, or rendering. When composition commits, the engine translates the final display replacement
to one canonical source transaction and then resumes parsing and projection. Cancellation restores the
pre-composition projection without emitting a source change.

## Interactive tasks and links

A proposed `NoteTaskOverlayController` pools `NSButton` checkbox views for visible inactive task
anchors. The display projection provides one placeholder per task, and TextKit 2 text segments provide
its frame. The controller updates after layout, scrolling, projection, selection, and editor resizing;
offscreen tasks own no view.

Every checkbox carries document identity, editor epoch, projection generation, source marker range, and
checked state. Activation first verifies all tokens, range bounds, and that the current source substring
is exactly `[ ]`, `[x]`, or `[X]`. A failed validation discards the stale control and reprojects instead
of editing. A valid activation replaces only the middle marker character through one editor transaction.

The checkbox exposes a checkbox accessibility role, task text label, and state. Its display placeholder
is excluded from accessibility so the marker is not announced twice. In Full Keyboard Access and
VoiceOver navigation, the checkbox precedes its task text, Space toggles it, and focus returns to the
corresponding task text. Moving the text caret onto the task line reveals literal source and removes the
checkbox, preserving direct keyboard editing.

A Foundation-only `NoteLinkDestination` resolves `http`, `https`, and `mailto` URLs plus absolute and
relative file paths. Relative paths use the active note's directory. Anchor-only destinations do
nothing because Notes has no rendered-document navigation; every other custom scheme is rejected.

Command-click maps the hit-tested display label back to its link record and asks a stateless
`NoteLinkLauncher` in `Features/Notes/Service/` to open the resolved URL with
`NSWorkspace.OpenConfiguration`. Ordinary click only positions the caret. Invalid destinations stay
editable, and open failures use the existing Notes failure presenter. Image destinations are never
opened or fetched as part of presentation.

## Formatting actions and shortcuts

A Foundation-only `NoteMarkdownEditing` plans canonical source edits from a command, source, and source
selection. It supports normal text, heading levels 1 through 3, bold, italic, strikethrough, inline code,
blockquote, unordered list, ordered list, task list, fenced code, link insertion, and horizontal rule.

Inline commands trim whitespace outside markers, remove a matching wrapper when present, and otherwise
wrap the selection. Empty selections insert paired markers and place the caret between them. Link
insertion wraps selected text or inserts `[text](url)`, then selects `url`.

Block commands operate on every selected line. If every line already has the requested outermost form,
the command removes it. Otherwise it replaces one existing supported outermost heading, quote, list, or
task prefix with the requested form instead of double-prefixing mixed selections. Normal removes one
supported outermost block form. Ordered insertion renumbers the selected lines from one. Fence wrapping
preserves selected text exactly.

`NotesCoordinator` exposes formatting actions and delegates them to `NotesWindowController`, which
forwards to the current `NoteTextView`. The resulting plan runs through one canonical editor transaction.
The text view handles the following key equivalents only while it is the active responder:

- Command-B — bold;
- Command-I — italic;
- Command-K — insert link;
- Shift-Command-X — strikethrough;
- Shift-Command-7 — ordered list;
- Shift-Command-8 — unordered list;
- Shift-Command-9 — task list.

Unrecognized key equivalents continue through the normal responder chain, preserving native Copy,
Paste, Select All, Undo, Redo, and window commands. Formatting no-ops while composition or the note
switcher is active, Notes is disabled, or no document is loaded.

## Formatting overlay

The Notes header adds one circular `textformat` control before Create. It opens a custom in-window
`NoteFormattingMenu`, anchored below the button and layered over the editor. It is not `NSPopover`,
`NSMenu`, or another window. Its treatment follows `Tinycast/DesignSystem/PopoverMenu.swift` and
`docs/ui.md`.

The compact menu groups controls into three rows:

1. Normal, H1, H2, H3.
2. Bold, italic, strikethrough, inline code, link.
3. Quote, bullets, numbering, task, code block, horizontal rule.

Opening by pointer places keyboard focus on the selected or first control while preserving the editor's
canonical selection. Arrow keys use roving movement within and between rows; Tab and Shift-Tab follow
visual order; Return or Space invokes; Escape closes and restores the editor selection and focus. Every
control has an accessibility label, selected state where applicable, shortcut help when one exists, and
a stable VoiceOver order matching the rows. Invoking a command closes the overlay and restores editor
focus.

Clicking outside closes the overlay before the same event continues to its original target, so placing
the caret takes one click. Clicking the format button again, switching notes, opening the switcher,
hiding the window, or disabling Notes also closes it. The controller removes its event monitor whenever
the overlay closes or the window tears down.

Escape closes the formatting overlay first, then the note switcher, then the Notes window. Command-W
continues to hide the window directly. The menu overlays content and never resizes the panel.
`NotesCoordinator` owns its short-lived visibility alongside switcher presentation; `NotesWindowController`
owns the event monitor and focus restoration.

## Window sizing, focus, and accessibility

The existing 520-point width, height limits, screen clamp, and top-edge anchor do not change. Content
height is measured from the display projection. Activating source can change wrapping and height;
`NotesWindowController` applies the existing top-anchored resize rule and restores caret visibility.

The text view's accessibility value follows the visible projection so inactive prose is read naturally.
When a construct is active, its revealed literal source is exposed. Custom checkbox controls replace
their placeholder in the accessibility tree, and decorative quote/rule views are hidden. Copy remains
an explicit canonical-source operation and is not derived from the accessibility string.

External clean reloads arrive with a new editor epoch, install authoritative source, clear undo, clamp
the previous source selection, and rebuild projection. Dirty external conflicts keep the in-memory
source and current epoch. Smart quotes, dash substitution, text replacement, spelling correction, and
rich-text paste remain disabled.

## Performance and failure behavior

Initial parsing is linear in UTF-16 length. Ordinary source edits use block-state convergence, patch
only the invalidated projection, and relayout that display range. Caret movement reprojects at most the
old and new active constructs. A fence edit may require a full tail parse; while a full recomputation is
pending, the invalidated tail is temporarily shown as literal source so editing and mapping stay correct.
The pure recomputation runs in a cancellable `Task.detached`, publishes only for the matching document
identity and source generation, and introduces no additional actor. Parser, projection, and edit-plan
payloads crossing that boundary are `Sendable`; AppKit objects remain main-actor-only.

The implementation adds a `NoteEditor.project` signpost covering parse, projection patch, and selection
restoration. On the deterministic 250,000-character fixture after ten warm-up edits, 100 ordinary
single-character edits in the middle of a paragraph must have a median below 8 milliseconds and p95
below 16 milliseconds on the development Mac. The harness prints measurements but does not enforce
hardware-dependent wall-clock thresholds in the regular test suite. The same Instruments run verifies
that selection changes touch no more than two constructs and that scrolling does not grow the checkbox
pool beyond visible tasks plus a small reuse reserve.

Presentation failure never blocks source editing or saving. A failed map validation reveals the affected
construct as identity-mapped source and rebuilds its projection. Missing checkbox geometry leaves literal
task source visible until the next layout pass. A superseded async projection is discarded. Parser and
presentation limitations fall back to literal source rather than reporting a document error.

## Compatibility and rollout

There is no data migration, setting, feature flag, or alternate editor. Existing Markdown files acquire
the new projection on the next build, and disabling Notes retains the current lifecycle. Since the
canonical source format is unchanged, reverting to the previous editor loses no note data.

The bundled CodeMirror, JavaScript, CSS, Mermaid, KaTeX, table editor, preview sidebar, and WebKit bridge
from the reference repository are explicitly not copied. The reference informs behavior only.

## Verification

`Tests/notes-test.swift` compiles the shipped Foundation-only model and service sources. It replaces the
old scanner checks and adds coverage for:

- every supported grammar rule, including H1-H6, triples, intraword underscores, escapes, unmatched and
  mismatched fences, rule/list ambiguity, nested block prefixes, balanced link parts, and optional title;
- exact UTF-16 parser and projection ranges with emoji, combining marks, and RTL text;
- source/display conversion at every identity, elision, replacement, affinity, and construct boundary;
- partial and whole-construct copy ranges and exact source round trips;
- incremental parse convergence matching a clean full parse after every fixture edit;
- mixed block normalization, inline toggles, empty selections, and resulting source selections;
- stale checkbox token rejection and valid marker replacement;
- deterministic output for the 250,000-character fixture.

A standalone AppKit editor harness proves behavior that pure tests cannot:

- one delegate delivery, one undo, and one redo for typing, formatting, multi-line formatting, and task
  toggles;
- edit Note A, switch or externally reload to a shorter Note B, then Undo and Redo without stale ranges;
- native Copy, Cut, Paste, Select All, and unrecognized key equivalents through the responder chain;
- composition commit and cancellation without intermediate source emissions or selection resets;
- projection width, hit testing, caret preservation, scrolling, and one-click outside-menu dismissal;
- checkbox generation validation, pooling, keyboard activation, and accessibility ordering.

Manual verification covers every construct inactive, active, selected, copied, formatted, undone, and
redone; long wrapped links and headings; IME input; menu pointer, keyboard, and VoiceOver navigation;
ordinary versus Command-click links; autosave; switching; external reload; conflict recovery;
termination; and a large note at the panel height cap.

Completion requires the TextKit feasibility gate, all checks in `docs/testing.md`, a Debug build with no
new warnings, and updates to `docs/features/notes.md`, `docs/ui.md`, `docs/testing.md`, and any architecture
or standard statement made inaccurate by the final implementation.
