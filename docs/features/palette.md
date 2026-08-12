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
                                            · positions, lays out off-screen, orders front
                                                              ↓
                                                    RootPaletteView.body
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
  flipping the branch tears down its field editor, which drops first responder mid-navigation. Only
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

## The placeholder is Tinycast's, not the field's

The search field is a SwiftUI `TextField` with **no `prompt`**; `RootPaletteView` draws the
placeholder itself as a leading-aligned background `Text`.

AppKit gives an `NSTextField` a field editor one point taller than the field (measured: a 24pt editor
in a 23pt field), and a `prompt` is rendered by whichever of the cell and the editor currently owns
the text. The same placeholder glyphs therefore sit **one point higher** once the field takes the
panel's shared field editor. That editor is created lazily and then cached on the window for its
lifetime, so the step was only ever visible on the first summon after launch — and only where the eye
could track it, when the outgoing and incoming placeholders share a leading word.

Drawing it in SwiftUI pins it to the layout instead: measured ink is identical in both focus states,
against a two-backing-pixel step for the real prompt. It is a **background**, not an overlay, so the
caret still draws over it, and it carries `allowsHitTesting(false)` so clicking the placeholder still
lands the caret. `PaletteMode.placeholder` is still the one source of the strings; the field takes an
explicit `accessibilityLabel` because the prompt used to supply it.

This is the same class of bug as the freeze below — both come from the cell/field-editor swap.

## The panel settles the pointer itself

`PalettePanel.applyCursorPolicy` sets the cursor after every mouse event: the I-beam inside the search
field's frame, the arrow everywhere else. Without it the palette's pointer sticks as an I-beam over the
whole window and flickers along the field's edge — the two AppKit mechanisms that claim a cursor here
disagree, and neither yields.

- SwiftUI's `HostingClipView` claims the **arrow** across the entire window as a *cursor rect*.
- The field editor claims the **I-beam** from its own *tracking area*.

Both fire on the same crossings, so the cursor alternates while the pointer is over the field, and the
last claim simply stays put once it leaves — nothing re-evaluates a cursor rect until the pointer
crosses one, and the arrow rect spans the window, so leaving the field crosses nothing.

Two measured details the policy depends on:

- **The field publishes its own frame.** `RootPaletteView` reports it into `PaletteState.searchFieldFrame`
  via `onGeometryChange`, and the panel does a containment test against that. Hit-testing for the field
  instead does not work: SwiftUI rebuilds it as it re-renders, and a hit test taken mid-rebuild misses
  it and reads as *the pointer left the field*. The frame only moves on layout, so it never lies.
  It arrives top-left-down and is flipped into AppKit's bottom-left-up window space.
- **The rect is outset by 2pt.** AppKit's field editor is a point taller than the field it serves — the
  same measurement the placeholder section above rests on — so its I-beam overhangs the published
  frame. Without the slack that 1pt band is a disagreement, and it flickers.

The policy runs after `super.sendEvent`, so it has the last word, and it writes only when the cursor
actually differs. It must stay **symmetric**: an earlier version left the field alone and only forced
the arrow outside it, and AppKit's own alternation over the field came straight back.

## Menu-open input freeze

While a footer popover menu (⌘K Actions / app menu) is open the search field reads as inert but
**never resigns first responder** — resigning makes the `NSTextField` swap between its field-editor
and cell rendering, shifting the text / placeholder a point or two, so focus stays put. Input is
frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteState.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌃ chords
  and menu-nav keys through to SwiftUI `onKeyPress`), which is how ⌘P and ⌃X still reach their rows.
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## Emacs navigation chords

⌃N/⌃P and ⌃F/⌃B navigate exactly as ↓/↑ and →/← do — on the emoji grid all four step the selection,
and everywhere else the horizontal pair falls through to the caret, which is what a native search field
does.

None of them reach `onKeyPress` on their own: AppKit's key-binding table hands the field editor
`moveDown:` / `moveUp:` / `moveForward:` / `moveBackward:` first, and in a one-line field the vertical
pair walks the caret to the end or the start rather than moving anything.

`PalettePanel.sendEvent` therefore rewrites each chord into its arrow and re-dispatches, ahead of every
other rule it applies. Nothing else changes: the arrow handlers in `RootPaletteView` are the only
navigation code, so the compact bar's expand-on-↓, the grid's row and column steps, menu highlight
movement and the scroll-into-view intent all follow for free. The caret keeps ⌃F/⌃B off the grid
because `moveHorizontally` leaves →/← `.ignored` there, and the field editor then moves by a character
exactly as the chord natively would. A chord carrying any modifier beyond ⌃ — ⌃⇧Q, say — is left alone.

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
