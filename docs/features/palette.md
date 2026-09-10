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
- **The search field is never mounted conditionally.** A screen that owns the keyboard itself hides it
  through `PaletteScreen.hidesSearchField` — opacity and hit testing, never an `if` — because
  flipping a branch around it tears its field editor down. The header is simply left empty, and an
  extension's `Form` is the one screen that does this today.
- **Focus restoration is load-bearing.** Paste targets the recorded `previousApp` and requires the
  Accessibility permission (`Permissions.ensureAccessibility()`).
- **Input-source switching is a palette session.** The source active at summon time is captured before
  the panel becomes key, the configured source is applied through `PalettePanel.fieldEditorContext`, and
  the captured source is restored on hide and on termination — but only when the palette is still on the
  source it applied, so a switch made since, by the user or another app, stands. Never applied globally:
  the panel does not activate, so a global switch would land on whichever app is still frontmost.

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
                                                              ↓
                                            PalettePanel.makeFirstResponder
                                            · applies the configured source to the field editor
```

Everything resolved "once per summon" is resolved there deliberately, not per render. `AppCore` holds
only the closure wiring; the behaviour is `PaletteCoordinator`'s.

## Screens

`PaletteState` (mode / query / selection / `focusToken`) is the bridge between the panel and the app.
Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a UUID) so the
SwiftUI search field re-focuses. `prepare` is one of four motions over the screen — see
[Navigation](#navigation).

Hiding schedules Pop to Root Search, and `PaletteWindowController.popToRoot` is its only path: the
palette returns to the launcher *and* chat starts a new conversation, at once or after
`popToRootTimeout`, unless a re-summon inside that window consumes the pending reset first. An
unfinished chat is a thing being done, exactly like a typed query, so the screen and the conversation
are reset together rather than the screen alone. A reply still streaming is the one exception — it was
asked for, and resetting would throw the answer away. Nothing is lost either way: a conversation is
written to Chat History as soon as it has a message.

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
| `.schedule` | `ScheduleScreen` | `ScheduleList` (see [calendar.md](calendar.md)) |
| `.uninstall` | `UninstallScreen` | `UninstallList` (see [uninstall.md](uninstall.md)) |
| `.quicklinks` | `QuicklinkListScreen` | `QuicklinkList` + preview (see [quicklinks.md](quicklinks.md#search-quicklinks)) |
| `.snippets` | `SnippetsScreen` | `SnippetsList` + preview (see [snippets.md](snippets.md#search-snippets)) |
| `.customCommandArguments` | `CustomCommandArgumentsScreen` | `CustomCommandArgumentsView` (see [custom-commands.md](custom-commands.md#arguments)) |
| `.extensionCommand` | `ExtensionCommandScreen` | `ExtensionCommandView` (see [extensions.md](extensions.md)) |

**Tab rings the three surfaces a reader opens directly — launcher → AI chat → clipboard → launcher**
— unless the screen claims it through `tabTarget(from:backwards:)` (an extension's `Form` walks its
own fields), or the selected row declares arguments, in which case it walks those fields first (see
below); every other mode stays off the ring, and is reached by a command or a global hotkey, with
Uninstall only from a launcher app's Actions menu, scoped to that app. Chat is skipped whole when
`aiEnabled` is off, which leaves the launcher ↔ clipboard flip the ring replaced.

### Navigation

**The summon decides where a screen sits, not the mode.** `PaletteCoordinator.navigate(to:)` is the
one rule: a palette already on screen is being *navigated*, so the current screen is pushed and
becomes the step back; a hidden one is being *summoned*, so the new screen is a root with nothing
behind it. Every mode command and every global hotkey funnels through `showPalette`, which calls it —
so typing "Clipboard History" at the root and pressing ↵ leaves a step back to the search that found
it, while the Clipboard History hotkey does not. Nothing per-feature encodes this.

`PaletteState` holds the screens below `mode` as `[PaletteFrame]` — mode, query and selection, enough
that returning looks like never having left — and offers four motions over it:

| Motion | Meaning |
| --- | --- |
| `prepare(mode:)` | become the root: open fresh, drop the stack |
| `replace(mode:)` | swap the screen, keep what it was opened over (a new chat, not a new root) |
| `push(mode:)` | open over the current screen, which a back step returns to |
| `pop()` | restore the screen underneath; `false` when this one is the root |

`pop()` bumps `followToken` rather than `resetToken`: the reset token exists to snap a list to the
top, which would throw away the very selection being restored.

**Escape clears a non-empty query before it leaves the screen**, so one press clears and the next
leaves: an extension screen exits itself first (it keeps a stack the palette cannot see), then a
pushed screen pops, and a root hides the palette. A focused inline argument field is a rung above the
query, so Escape hands focus back to the search field first — the query that found the command is
still there to be cleared by the next press. A bare backspace in an empty field takes the same step,
and ⌘⎋ skips the whole stack for a fresh root search without closing the window.

`EscapeKeyBehavior` (General settings) can trade the walk back for the old behavior: under
`closeAndPopToRoot` an empty field closes the window and resets it immediately, whatever Pop to Root
Search says. Clearing the query is still the first press either way.

The header draws a back chevron on **every** screen but the launcher: leaving is what the icon
slot means once you are off the root, and a slot that changed shape with provenance would read
as two different controls. Where the click lands still depends on the stack — a pushed screen
pops, a root one closes — so `backHelp` says which, rather than promising a step that is really
a close. It lights to `textPrimary` under the pointer over `Theme.Duration.hover`, and
`HeaderBackButton` keeps that hover state to itself so the header around it never re-renders.

The launcher advertises the first hop in the header — `AI Chat` beside a `⇥` cap, the footer's own
pairing of a label with its key. It is drawn only when Tab really would open chat, a condition read
back out of `PaletteTabAction` rather than restated, so a hint can never promise a destination the
key does not go to: an argument field to walk takes Tab first, and the hint steps aside for it.

`PaletteTabAction` decides where Tab goes *and* what happens to the typed text. The clipboard hands
the query over, since one search narrows either list. **From the launcher, Tab `.ask`s** — chat opens
fresh with the typed text already sent, so one key turns a search into a question. Leaving chat is
still a `.freshScreen`: that field holds a half-written message rather than a query, and a draft
dropped into a filter matches nothing. `.ask` is its own case rather than a `carryQuery(.ai)` because
the text is submitted, not seeded, and the hint reads the case back out (`== .ask`) instead of
restating the rule.

`.customCommandArguments` — `PaletteMode.isArgumentForm` — is the one mode where the search field is
not a search field: it _is_ the current argument's input, so its placeholder names that argument and ↵
submits rather than activating a row. It has no rows, which is why `isArgumentForm` is what keeps the
↵ pill drawn. Its state lives on `AppCore.customCommandArguments`, the way `.uninstall`'s target lives
on `UninstallSession`, and leaving the mode cancels the pending run. A bare backspace steps back an
argument before it falls through to the usual back step; Escape erases the half-typed answer
first, and a second press hides the palette, ending the pending work with it. **Quicklinks used to be
the other half of this pair and no longer are** — they collect their values in the header instead, so
one surface asks for a row's arguments rather than two.

### Inline row arguments

A selected row can declare arguments, and they are typed **in the header, beside the search field** —
not on a screen of their own. Two features answer this way, each owning its own strip: an extension
command through `ExtensionArgumentsAccessory`, a quicklink through `QuicklinkArgumentsAccessory`. The
palette knows neither: `PaletteScreen.headerAccessory(at:focus:)` hands back a `PaletteHeaderAccessory`
— a width, the field names in Tab order, the first field still owed a value, a menu for a field that is
chosen rather than typed, and an opaque view. That costs the header its one simple rule, so it holds
these invariants:

- The search field sits at **one structural position, always**. It is never moved inside an `if`:
  flipping the branch tears down its field editor, which drops first responder mid-navigation. Only
  its *width* changes — it is sized to its own text so the chips sit right after it, as they do in
  Raycast.
- **`Placement` is what a strip does to the field beside it.** `.afterQuery` (root search) drops the
  prompt and squeezes the field to the typed text, so the chips follow what was typed and a glyph
  anchors them to the row. `.besideSearchField` (a screen of its own, where that row is already
  listed) keeps the prompt and sizes the field to it, so an empty field reads "Search quicklinks…"
  with the chip after it and no glyph repeating the row below. One measurement serves both: the
  field's own text, which is the prompt when nothing is typed and "" under `.afterQuery`.
- Argument focus is its own `@FocusState`, `argumentFocused`, keyed by argument name. Every way out
  of its ring — moving the selection, Escape, Tab past the last field, or an arrow at its edge — goes through
  `returnFocusToSearchField()`, because the row that owned those fields is about to stop being
  selected and a field that unmounts while focused leaves the panel with no first responder at all.
  ↵ on a blank required argument focuses it instead of launching.
- **Never read a `@FocusState` back in the tick that writes it.** It still reports the old field, so
  `searchFocused = argumentFocused == nil` resolved to `false` and Tab out of the last argument
  focused nothing; AppKit's key-view loop then answered the next presses instead. Both writes come
  from one local value.
- Returning focus this way leaves the query selected, because AppKit selects the whole string as the
  field editor comes back — here that is the wanted reset rather than the hazard it is under ↵.
- A field declaring `options=` is **chosen, not typed**: it hands back a `PopoverMenuContent` and the
  palette opens it as `OpenMenu.argumentOptions`, the same window every other menu uses. There is no
  second dropdown control to keep in step, which is the whole reason the accessory vends a menu rather
  than a view of its own.

The typed values live on `PaletteState.commandArguments`, keyed by
`PaletteState.argumentKey(entryID, name)`, and are cleared with the rest of the screen.
`PaletteState.pendingArgumentEntryID` is how a *shortcut* reaches them: a quicklink opened with values
still missing shows its own screen and names the row, and the header focuses that row's first empty
field instead of the search field. It is set **after** `showPalette`, since `prepare` clears it.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the card at index 0 when present — the calculator's (see
[calculator.md](calculator.md)) or the meeting join card (see [calendar.md](calendar.md)), never both.

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

- **On** — `NSScreen.underCursor`: the screen holding `NSEvent.mouseLocation`, i.e. the display under
  the pointer.
- **Off** — `NSScreen.primary`: the screen at the global origin, i.e. the one with the menu bar.

**Neither case may use `NSScreen.main`**, which is documented as the screen of the window with keyboard
focus — the frontmost app's, wherever the user last clicked. It therefore follows the user across
displays, which is the wrong answer for both settings and made the off case do exactly what turning it
off was meant to stop ([#270](https://github.com/abue-ammar/tinycast/issues/270)). The menu-bar display
is the one whose `frame.origin` is `.zero`, which is what `primary` looks for.

The cursor hit test is `NSMouseInRect(mouse, screen.frame, false)`, **not** `CGRect.contains`. A mouse
location is the CoreGraphics cursor position flipped about the primary display's height, so a screen's
rows land in the half-open interval `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains`
excludes, while that same value is the `minY` of the display stacked above. `contains` would therefore
hand a pointer parked at the top of one display to its neighbour. `NSMouseInRect` exists for this.

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

### IME composition

A hand-drawn placeholder has one cost the real prompt does not. An IME composes into the field
editor's own storage, so the bound `query` stays empty for the whole romanisation and the placeholder
would sit under the in-flight pinyin. `PalettePanel` publishes the editor's `hasMarkedText()` as
`PaletteState.isComposing`, and the placeholder is gated on `query.isEmpty && !isComposing`.

The observation follows first responder, since SwiftUI hands the window's one field editor to
whichever field holds focus, and it watches `NSTextView.didChangeSelectionNotification`. Measured,
that is the **only** notification a marked-text change posts: `NSText.didChangeNotification` fires on
the commit alone, which is the whole composition too late.

`trackComposition()` re-reads the editor rather than assuming, and `windowDidBecomeKey` calls it as
well as `makeFirstResponder`: a key transition can commit or drop marked text without posting
anything, and a re-summon inside the Pop to Root window skips `prepare(mode:)` and never moves first
responder, so neither of the other two paths would fire.

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

## One menu at a time

`RootPaletteView` holds a single `OpenMenu?` rather than a flag per menu, so "at most one is open" is
structural instead of a pair of `onChange` handlers pushing each other closed. The ⌘K Actions menu
hangs `.bottomTrailing`, the app menu `.bottomLeading`, and everything drawn as a header control —
the clipboard type filter, the AI model and effort menus, an `options=` argument field's choices and
a running command's `searchBarAccessory` dropdown — hangs `.belowHeaderTrailing`, under its own
button. `menuContent` resolves the open case to one `PaletteMenuContent` — a row count, a row action
and a view built on demand — so ↑/↓, plain ↵, Esc and the click-away catcher serve every menu without
knowing which is up. A screen supplies its rows as a `PopoverMenuContent` through `actions(at:)` and
the default `menuContent` wraps them; a screen whose rows the palette's menu can't express overrides
`menuContent` and hands over its own view instead — `ExtensionCommandScreen` is the only one, for
both its ⌘K panel and its search-bar dropdown, and the reason the seam exists (see
[extensions.md](extensions.md)). The view is a closure because `moveMenu` resolves the open menu on
every arrow key and needs the row count alone. Every open path goes through `open(_:highlighting:)`
and states where the highlight starts: the first row, except the pop-up-shaped menus — the type
filter, the AI model and effort menus, an extension's search-bar dropdown — which open on the choice
they already hold.

Every row closes the menu behind it — `activateMenuItem` is the one path, and a row that reorders the
list under itself (Move Favorite Up/Down) is no exception, so no row ever runs against a rebuilt menu.

`PopoverMenuItem.startsSection` draws a separator in the existing gap above a row. It takes no
layout space or selection index, so the menu keeps its row positions, dimensions, and navigation.
Built-in action menus mark boundaries between opening or copying, managing the item, settings, and
deletion. Menus offering one kind of action, such as calculator copies, color formats, or emoji
transfers, keep their rows in one group.

### The menu's own window

A menu is **not** an overlay inside the palette: `MenuPanelController` hosts it in a `MenuPanel`, a
borderless non-activating `NSPanel` added as a **child window** of the palette's, which is what makes
it follow a palette drag and vanish with it. Glass renders against the desktop rather than inside an
already-blurred, clipped panel, and no menu can be cropped by `RootPaletteView`'s `clipShape` however
long it grows. `MenuPanel.canBecomeKey` is `false` so the palette keeps key status and its
`onKeyPress` handlers keep driving the highlight, and `MenuPanel.sendEvent` mirrors `PalettePanel`'s
hover arming — rows light on real pointer movement, never on a scroll under a still cursor.

The panel is a second SwiftUI hierarchy, so it observes nothing of `RootPaletteView`'s `@State`:
`syncMenuPanel` pushes a rebuilt tree on every `openMenu` or `menuSelection` change, and
`paletteEnvironment` injects the same stores into both hierarchies so they cannot drift.
`WindowReader` reports the palette's `NSWindow`, which the menu's frame is placed against.

`PaletteMenuContent` opts into `clipsToMenuCorners` when wrapping a native `PopoverMenu`. Its hosting
view's backing layer uses the continuous `menuPanel` corner with edge antialiasing. AppKit draws the
window shadow from that outline, refreshed after layout and display on show and resize. Custom
extension panels keep their original hosting setup. Switching between native and custom content
replaces the hosting view so layer styling stays with the menu that requested it.

## Menu-open input freeze

While a popover menu (⌘K Actions / app menu / clipboard type filter) is open the search field reads as inert but
**never resigns first responder** — resigning makes the `NSTextField` swap between its field-editor
and cell rendering, shifting the text / placeholder a point or two, so focus stays put. Input is
frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteState.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌃ chords
  and menu-nav keys through to SwiftUI `onKeyPress`), which is how ⌘. and ⌃X still reach their rows.
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## ↵ never commits the search field

Plain ↵ is claimed by `RootPaletteView`'s own `onKeyPress` whenever the search field holds focus, and
`activateSelection` runs from there — the field carries no `onSubmit`. Letting the field submit ends
editing, and AppKit tears the field editor down and selects the whole string when focus returns, so a
screen opened with a carried query (the Search Files fallback) came up with that query selected. An
IME's composition and any other focused field — the inline argument fields, an extension form — are
left alone: the handler returns `.ignored` for them, and their own `onSubmit` still commits.

## Chords `onKeyPress` never sees

Most ⌘/⌃ chords reach SwiftUI's `onKeyPress` fine. Several kinds do not. All but the last are
handled in `PalettePanel.sendEvent` before `super` hands the event to the responder chain:

- **A bare backspace** — the field editor consumes it as an edit (`onBareBackspace`).
- **Chords with no main menu item** — ⌘, and ⌘w, which an app with a menu bar would never see here.
- **The physical number-row slots.** `FavoriteSlots` matches ⌘1…⌘0 by key code before fixed command
  chords, then publishes the resolved position to the active screen. Only the launcher and clipboard
  screens intercept these slots; other screens keep their own ⌘-number shortcuts. The launcher's
  compact visibility setting is visual only and does not disable its favorite slots.
- **Chords AppKit has already bound to a selector.** `⌘.` is the one that bites: AppKit binds it to
  `cancelOperation:` alongside Escape, so `interpretKeyEvents` hands it to the field editor and
  `onKeyPress(keys: ["."])` never fires. Pin (⌘.) therefore arrives through `onCommandShortcut`,
  which bumps `PaletteState.pinChordToken`; `RootPaletteView` observes that and resolves the row
  through the current screen, so **which** row gets pinned still comes from `screen.rows` alone.
- **Chords the window server keeps for itself.** ⌘⎋ is the one that bites: macOS binds it before any
  app sees it, so unlike ⌘. there is no keystroke left for `sendEvent` to intercept — a handler in
  the responder chain compiles, runs never, and looks like a palette bug. `CommandEscapeTap` takes it
  at the head of the HID stream instead, the one place earlier than the system's own binding, and
  `prepare(mode: .launcher)`s: one chord back to the root search from any depth, window still open.
  The tap is enabled only while the palette is on screen, watches `keyDown` alone, and declines the
  chord whenever the panel is not key, so nothing else on the system loses ⌘⎋ to it. It is a
  modifying tap, so it needs Accessibility — without that grant the chord is simply unavailable,
  which is the only path this codebase has to it.

Adding a chord that "does nothing" is almost always one of these — check `sendEvent`, and then
whether macOS has claimed the chord, before assuming the handler is wrong.

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

Character shortcut handlers accept every key so SwiftUI still calls them when the active input
source produces a non-ASCII character. Inside the callback, `ASCIIKeyboardLayout` resolves
`NSApp.currentEvent.keyCode` through the current ASCII-capable layout before comparing the shortcut.
Panel-owned chords use the same translation directly. A ⌘ chord translates through the layout's own
Command table, so "Dvorak – QWERTY ⌘" keeps giving QWERTY positions while Command is held; a ⌃ chord
translates without it, since only Command is remapped. A non-ASCII input source or IME therefore
cannot turn ⌘K into a different logical key, while Dvorak and other ASCII layouts keep their own
letter positions. No replacement event is synthesized, and unmodified typing stays on the active
input source and follows the normal composition path.

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
