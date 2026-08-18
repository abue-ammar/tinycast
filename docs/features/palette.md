# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](../architecture.md) for window ownership.

## Invariants

- **`PaletteWindowController` solely owns the palette frame.** The hosting view sets
  `sizingOptions = []` so SwiftUI never drives the window size — otherwise the hosting view resizes the
  panel to fit content and the top edge drifts on the compact↔expanded swap. A user drag is the one
  frame change that starts elsewhere, and `windowDidMove` folds it back into the anchor so the
  controller stays the authority.
- **The flat `selection` index must match the visible row order exactly**, including the inline
  calculator card at index 0 when present. Selection is the single source of truth for highlight and
  activation. `Features/PaletteRowIndex.swift` is that mapping and stays **Foundation-only and pure** —
  no SwiftUI, no AppKit — so `palette-selection-test` compiles the shipped type rather than a copy.
  Section headers are not selectable and never consume an index.
- **While a footer menu is open the search field never resigns first responder.** Input is frozen
  instead; resigning shifts the text a point or two.
- **Focus restoration is load-bearing.** Paste targets the recorded `previousApp` and requires the
  Accessibility permission (`Permissions.ensureAccessibility()`).
- **Input-source switching is a palette session.** The source active at summon time is captured before
  the panel becomes key, the configured source is applied through the search field's input context, and
  the captured source is restored on hide and on termination — but only when the palette is still on the
  source it applied, so a switch made since, by the user or another app, stands.

## Summoning

```
⌥Space (Carbon) → HotKeyCenter → HotKeyManager.perform → AppCore's onTogglePalette closure
                                                              ↓
                                          PaletteCoordinator.togglePalette()
                                                              ↓
                                          PaletteWindowController.show()
                                            · records previousApp (the paste / focus target)
                                            · resolves PasteTarget once per summon
                                            · resolves the screen anchor once per summon
                                            · captures the input source to restore, once per summon
                                            · positions, lays out off-screen, orders front
                                                              ↓
                                                    RootPaletteView.body
                                            · focuses the search field
                                            · applies the configured source to its input context
```

Everything resolved "once per summon" is resolved there deliberately, not per render. `AppCore` holds
only the closure wiring; the behaviour is `PaletteCoordinator`'s.

## Screens

`PaletteState` (mode / query / selection / `focusToken`) is the bridge between the panel and the app.
Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a UUID) so the
SwiftUI search field re-focuses.

Each `PaletteMode` maps to one type conforming to `PaletteScreen`, and the protocol is what keeps the
selection invariant honest: a screen exposes `rows` as its single source of visible order, and the
palette indexes into it. Adding a mode means adding a conformer, not a branch in `RootPaletteView`.

| Mode | Screen | Inner list |
| --- | --- | --- |
| `.launcher` | `LauncherScreen` | `LauncherList` |
| `.clipboard` | `ClipboardScreen` | `ClipboardList` + preview |
| `.calculatorHistory` | `CalculatorHistoryScreen` | `CalculatorHistoryList` |
| `.emoji` | `EmojiScreen` | `EmojiGridView` |
| `.fileSearch` | `FileSearchScreen` | `FileSearchList` (see [file-search.md](file-search.md)) |
| `.uninstall` | `UninstallScreen` | `UninstallList` (see [uninstall.md](uninstall.md)) |
| `.quicklinks` | `QuicklinkListScreen` | `QuicklinkList` |
| `.quicklinkArguments` | `QuicklinkArgumentsScreen` | `QuicklinkArgumentsView` (see [quicklinks.md](quicklinks.md#the-argument-prompt)) |
| `.extensionCommand` | `ExtensionCommandScreen` | `ExtensionCommandView` (see [extensions.md](extensions.md)) |

Every mode but `.launcher` is a sub-screen that backs out to the launcher. **Tab cycles launcher ↔
clipboard and nothing else** unless the selected row declares arguments, in which case it walks those
fields first (see below); the rest are reached by a command or a global hotkey, and Uninstall only
from a launcher app's Actions menu, scoped to that app.

The argument screen is the one mode where the search field is not a search field: it _is_ the current
argument's input, so its placeholder names that argument and ↵ submits rather than activating a row.
Its own state lives on `AppCore.quicklinkArguments`, the way `.uninstall`'s target lives on
`UninstallSession`, and leaving the mode cancels the pending open. A bare backspace steps back an
argument before it falls through to the usual exit-to-launcher.

### Inline command arguments

An extension command can declare arguments, and they are typed **in the header, beside the search
field** — not on a screen of their own. That costs the header its one simple rule, so it holds two
invariants:

- The search field sits at **one structural position, always**. It is never moved inside an `if`:
  flipping the branch tears down its text view, which drops first responder mid-navigation. Only
  its *width* changes — it shrinks to the width of the typed text so the argument chips sit right
  after it, as they do in Raycast.
- Argument focus is its own `@FocusState`, `argumentFocused`, keyed by argument name. Moving the
  selection hands focus back to the search field first, because the row that owned those fields is
  about to stop being selected. ↵ on a blank required argument focuses it instead of launching.

The typed values live on `PaletteState.commandArguments`, keyed by
`PaletteState.argumentKey(entryID, name)`, and are cleared with the rest of the screen.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the inline calculator card at index 0 when present (see
[calculator.md](calculator.md)).

## Window placement

`PaletteWindowController` resolves an anchor (left edge + top edge) **once per summon** and reuses it
for every compact↔expanded resize, so only the height changes and the top edge never drifts. The
anchor is dropped on hide, so the next summon re-resolves for wherever the user is then.

All of the arithmetic lives in `PalettePlacement`, which is CoreGraphics-only and takes every screen
fact as a parameter, so `palette-placement-test` drives the shipped rules rather than a copy of them.

### Drag to reposition

**Drag to reposition** (`AppSettings.paletteDraggable`, off by default) is the only thing that moves a
panel already on screen. `WindowDragHandle` claims mouse-down on the top strip and on the header's
margins and inter-item gaps (`RootPaletteView.headerGutter`) — everywhere in the header no control
occupies. The search field is a handle too, but only past its visible text:
`TextTrailingDragHandle` measures the query in `Theme.Typography.searchFieldNSFont` and claims the
hit-test only beyond it, so clicking or dragging the text still edits and selects, matching Spotlight.

AppKit moves the frame without going through the controller, so `windowDidMove` writes the new top-left
back into the anchor — otherwise the next compact↔expanded resize would snap the panel back to the
position it was summoned at. That write is idempotent, since `positionPanel` places the frame at exactly
the anchor and its own `setFrame` round-trips the same values.

**The handle tracks the gesture itself rather than calling `performDrag(with:)`.** That method hands the
drag to the window server and returns immediately, so it can say when a drag *starts* but never when it
ends — the mouse-up arrives long after it has returned. `DragView.mouseDown` instead runs
`trackEvents(matching:timeout:mode:)` over `.leftMouseDragged` / `.leftMouseUp`, moving the window by
the `NSEvent.mouseLocation` delta, which puts the whole gesture inside one call. It brackets that with
`PaletteCoordinator.beginPaletteDrag()` / `endPaletteDrag()`, and the controller holds a `DragSession`
for exactly that span. **Only a move inside a session is a user drag**; without that flag every
programmatic resize would be recorded as one.

### The drop guides

While a drag is in flight, `PaletteDropGuideController` puts a click-through borderless panel over the
display the panel is on, one level under `.floating` so it never covers the panel being dragged. It
draws three dotted lines through the default placement — both panel edges full height, the top edge full
width — which turn `Theme.Colors.dropGuideArmed` once the anchor is within `Theme.Size.paletteSnapDistance`
of home. Releasing while armed snaps the panel there.

The guides wait for the first `windowDidMove` of a session rather than appearing on mouse-down, so a
bare click on a handle never flashes them. Crossing to another display re-points them at that display's
default placement, which is what a snap would then land on.

### Remembering where it was left

A drop that isn't a snap writes the anchor to `AppSettings.palettePosition`, and the next summon reopens
there — across relaunches, since it is a persisted setting. **A remembered position outranks the display
setting below**; `PalettePlacement.restored` drops it only when no display still shows
`Theme.Size.paletteMinimumVisible` of the compact bar, which is what a disconnected screen or a
resolution change leaves behind. Snapping onto the guides clears the stored position, so the guides
double as the way back to default behaviour.

The position is deliberately **not** in a settings backup — it is machine-local geometry, the same
reason the Settings window autosaves its frame instead ([backup.md](backup.md)).

Which display an *unremembered* palette anchors to depends on the **Follow the cursor across displays**
setting (`AppSettings.openOnCursorScreen`, on by default):

- **On** — the screen holding `NSEvent.mouseLocation`, i.e. the display under the pointer.
- **Off** — `NSScreen.main`.

`NSScreen.main` alone can't implement the follow-the-cursor case: it is documented as the _key window's_
screen, and an accessory app driving a non-activating panel has no key window on the display the user is
looking at, so `main` resolves to the menu-bar display regardless of where the pointer is.

The hit test is `NSMouseInRect(mouse, screen.frame, false)`, **not** `CGRect.contains`. A mouse location
is the CoreGraphics cursor position flipped about the primary display's height, so a screen's rows land
in the half-open interval `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains` excludes,
while that same value is the `minY` of the display stacked above. `contains` would therefore hand a
pointer parked at the top of one display to its neighbour. `NSMouseInRect` exists for precisely this.

## The search field is Tinycast's

The search field is **not** a SwiftUI `TextField`. `PaletteSearchField` wraps `PaletteSearchTextView`,
an `NSTextView` the palette owns outright, and that view draws the query *and* the placeholder.

**Why it is not an `NSTextField`.** An `NSTextField` has two things that draw the same string: the
cell draws it unfocused, and the window's shared field editor draws it once focus lands. AppKit sizes
that editor a point taller than the field (measured: a 24pt editor in a 23pt field), and the two paths
round the baseline differently, so the same glyphs sat **one point higher** while focused. The editor
is created lazily and then cached on the window, so the step showed only on the first summon after
launch — and only where the eye could track it, when the outgoing and incoming strings share a leading
word. A SwiftUI `TextField` is the same machinery, and its field editor is force-cast to a private
subclass, so a corrected one cannot be vended.

An `NSTextView` **is** its own editor. There is no second renderer, so there is no step to compensate
for, focused or not. **Do not go back to a `TextField` here**, and do not reintroduce a `prompt:`.

**The placeholder.** `draw(_:)` renders it when `string` is empty, at `textContainerOrigin` plus the
container's `lineFragmentPadding` — the exact origin TextKit gives the first real glyph, so the two
cannot disagree by construction rather than by a tuned constant. It draws under the caret and is not a
hit target, because it is not a view. `PaletteMode.placeholder` is still the one source of the strings.

**IME composition.** Marked text lands in the view's own storage, so `string` stops being empty the
moment composition starts and the placeholder goes with it — no overlap with in-flight pinyin or kana.
`textDidChange` refuses to publish while `hasMarkedText()`, so `PaletteState.query` still changes only
on commit and a half-typed romanisation never reaches a search.

**Vertical centring** is `textContainerInset.height`, recomputed in `layout()` against the view's own
bounds. One number, one owner. The field still fills the header row's height so `topDragStrip` meets it
with no gap.

**`lineFragmentPadding` is `fieldEditorPadding`, not zero.** macOS draws the caret as an
`NSTextInsertionIndicator` layer 2pt wide **centred** on the insertion point, so a text box flush with
its clip view loses the caret's left half at column 0 — it renders 1pt until the first glyph pushes it
clear. AppKit's own `NSTextField` field editor pads by exactly this for the same reason (a bare
`NSTextView` uses 5). **Do not set it to zero to simplify the placeholder origin**: that origin adds
the padding back, which is what keeps the two aligned.

**Keys.** `doCommand(by:)` hands ↑ ↓ ← → ↵ ⇥ and Escape to `RootPaletteView.handleSearchKey` first and
falls through to the caret on `false` — that is what keeps ← and → stepping the emoji grid while they
stay with the caret everywhere else. The matching `onKeyPress` handlers are still on the root view and
share the same methods: they serve the inline argument fields, which are SwiftUI's and hold focus
themselves. `keyDown` records the modifier flags because a selector does not carry the chord that
produced it.

## The panel settles the pointer itself

`PalettePanel.applyCursorPolicy` sets the cursor after every mouse event: the I-beam inside the search
field's frame, the arrow everywhere else. Without it the palette's pointer sticks as an I-beam over the
whole window and flickers along the field's edge — the two AppKit mechanisms that claim a cursor here
disagree, and neither yields.

- SwiftUI's `HostingClipView` claims the **arrow** across the entire window as a *cursor rect*.
- The search text view claims the **I-beam** from its own *tracking area*.

Both fire on the same crossings, so the cursor alternates while the pointer is over the field, and the
last claim simply stays put once it leaves — nothing re-evaluates a cursor rect until the pointer
crosses one, and the arrow rect spans the window, so leaving the field crosses nothing.

One measured detail the policy depends on:

- **The field publishes its own frame.** `RootPaletteView` reports it into `PaletteState.searchFieldFrame`
  via `onGeometryChange`, and the panel does a containment test against that. Hit-testing for the field
  instead does not work: SwiftUI rebuilds it as it re-renders, and a hit test taken mid-rebuild misses
  it and reads as *the pointer left the field*. The frame only moves on layout, so it never lies.
  It arrives top-left-down and is flipped into AppKit's bottom-left-up window space.

The rect used to be outset by 2pt, because AppKit's field editor overhung the field it served. The
owned `NSTextView` is exactly the published frame, so the slack is gone. Do not add it back to paper
over a cursor flicker — a flicker now means the published frame is wrong.

The policy runs after `super.sendEvent`, so it has the last word, and it writes only when the cursor
actually differs. It must stay **symmetric**: an earlier version left the field alone and only forced
the arrow outside it, and AppKit's own alternation over the field came straight back.

## One menu at a time

`RootPaletteView` holds a single `OpenMenu?` rather than a flag per menu, so "at most one is open" is
structural instead of a pair of `onChange` handlers pushing each other closed. Three cases today —
the ⌘K Actions menu (`.bottomTrailing`), the app menu (`.bottomLeading`) and the clipboard type
filter (`.topTrailing`, hung under its header button). `menuContent` resolves the open case to one
`PopoverMenuContent`, which is what lets ↑/↓, plain ↵, Esc and the click-away catcher serve every
menu without knowing which is up. Every open path goes through `open(_:highlighting:)` and states
where the highlight starts: the first row, except the type filter, which opens on the active filter.

## Menu-open input freeze

While a popover menu (⌘K Actions / app menu / clipboard type filter) is open the search field reads as inert but
**never resigns first responder**. Input is frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteState.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌃ chords
  and menu-nav keys through to the search text view and `onKeyPress`), which is how ⌘. and ⌃X still
  reach their rows.
- The caret is hidden by clearing the focused text view's `insertionPointColor`.

The original reason for never resigning is gone: it was the `NSTextField` cell/field-editor swap
shifting the text a point or two, and the owned `NSTextView` has no swap. The freeze is kept as-is
because it also preserves selection and typing state, but it is now a **candidate for simplification**
rather than a constraint — resigning first responder here is no longer a visual regression.

## Chords `onKeyPress` never sees

Most ⌘/⌃ chords reach SwiftUI's `onKeyPress` fine. Three kinds do not, and all of them are handled in
`PalettePanel.sendEvent` before `super` hands the event to the responder chain:

- **A bare backspace** — the search text view consumes it as an edit (`onBareBackspace`).
- **Chords with no main menu item** — ⌘, and ⌘w, which an app with a menu bar would never see here.
- **Chords AppKit has already bound to a selector.** `⌘.` is the one that bites: AppKit binds it to
  `cancelOperation:` alongside Escape, so `interpretKeyEvents` hands it to the search text view and
  `onKeyPress(keys: ["."])` never fires. Pin (⌘.) therefore arrives through `onCommandShortcut`,
  which bumps `PaletteState.pinChordToken`; `RootPaletteView` observes that and resolves the row
  through the current screen, so **which** row gets pinned still comes from `screen.rows` alone.

Adding a chord that "does nothing" is almost always one of these three — check `sendEvent` before
assuming the handler is wrong.

## Emacs navigation chords

⌃N/⌃P and ⌃F/⌃B navigate exactly as ↓/↑ and →/← do — on the emoji grid all four step the selection,
and everywhere else the horizontal pair falls through to the caret, which is what a native search field
does.

None of them navigate on their own: AppKit's key-binding table hands the search text view
`moveDown:` / `moveUp:` / `moveForward:` / `moveBackward:` first, and in a one-line field the vertical
pair walks the caret to the end or the start rather than moving anything.

`PalettePanel.sendEvent` therefore rewrites each chord into its arrow and re-dispatches, ahead of every
other rule it applies. Nothing else changes: the arrow handlers in `RootPaletteView` are the only
navigation code, so the compact bar's expand-on-↓, the grid's row and column steps, menu highlight
movement and the scroll-into-view intent all follow for free. The caret keeps ⌃F/⌃B off the grid
because `moveHorizontally` declines →/← there, and the text view then moves by a character exactly as
the chord natively would. A chord carrying any modifier beyond ⌃ — ⌃⇧Q, say — is left alone.

## Focus restoration (load-bearing)

`PaletteWindowController` records `previousApp` (the frontmost app) on show. Paste then targets that
app:

- `Paster.paste` activates it and posts a synthetic ⌘V via `CGEvent`.
- `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the palette can
  stay open and frontmost (used by "paste keeping window open").

Both require the Accessibility permission (`Permissions.ensureAccessibility()`).

The same show also mirrors that app into `PaletteState.pasteTarget` (a `PasteTarget`: localized
name + bundle path), so Clipboard and Emoji can name it — the footer pill reads "Paste to Notes" and
the ⌘K paste rows carry the app's icon. Resolved once per summon, never per render, and deliberately
not cleared by `prepare` (pop-to-root resets the screen, not the target).
