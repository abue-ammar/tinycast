# Window Management

Rectangle-style window actions — halves, quarters, fourths, thirds, sizing, nudging, display moves,
native fullscreen and Space switching — searchable in the palette and bindable to global shortcuts.
34 commands, no new dependencies and no new permission: they reuse the Accessibility grant clipboard
paste already needs.

Ships **off**. Settings › Window Management is the switch, and while it is off there are no launcher
entries and a still-registered shortcut moves nothing.

## Invariants

- **`WindowPlacementEngine` works exclusively in AX space**, and `AXScreens.AXGeometry` is the only place that
  converts — anchored on the **primary** display, never the window's own screen. See
  [Coordinate space](#coordinate-space); getting this wrong is invisible on one monitor and wrong on
  every mixed-size setup.
- **Nothing in this feature touches `backingScaleFactor`.** All three of `NSScreen.frame`, `visibleFrame`
  and AX coordinates are in points, so mixed-DPI correctness is automatic.
- **`WindowCommand.swift`, `WindowPlacementEngine.swift`, `WindowActionMemory.swift` and `SpaceGesture.swift`
  stay Foundation + CoreGraphics and pure** — no AX, no `NSScreen`, no clock (`WindowActionMemory`
  takes `now` as a parameter, `SpaceGesture` takes `timestamp`). Every `AXUIElement` call and the
  Cocoa↔AX flip live in `Service/`; every `CGEvent` call lives in `SpaceSwitcher.swift`.
- **`AXWindowAccess` is the one AX layer**, shared by the mover and the layout runner. Its `write` is
  the size → position → size sequence: two copies of it would land a stubborn app two ways.
- **A Space command never reaches `WindowMover`.** `WindowPlacementEngine.placement` answers only for
  `.geometry` and `.restore`, and `WindowCommandCoordinator` branches on `SpaceDirection` first — the
  mover requires a target app and a resolvable AX window, and a Space switch has neither.

## Layout

| File                                             | Imports                      | Role                                                                |
| ------------------------------------------------ | ---------------------------- | ------------------------------------------------------------------- |
| `Model/WindowCommand.swift`          | Foundation                   | Catalog: id, name, symbol, kind, group, `cyclesOnRepeat`, `resizes` |
| `Model/WindowPlacementEngine.swift`  | Foundation + CoreGraphics    | **Pure.** Every frame the commands produce                          |
| `Model/WindowActionMemory.swift`     | Foundation + CoreGraphics    | **Pure.** Per-window cycle position and restore point               |
| `Model/SpaceGesture.swift`           | Foundation                   | **Pure.** The Dock-swipe field tables and the IOHID payload bytes   |
| `Service/AXWindowAccess.swift`       | AppKit + ApplicationServices | `@MainActor`. Every `AXUIElement` call, and the one write sequence  |
| `Service/AXScreens.swift`            | AppKit + ColorSync           | `@MainActor`. `AXGeometry`, the one coordinate flip                 |
| `Service/WindowMover.swift`          | AppKit + ApplicationServices | `@MainActor`. Command policy: cycle, restore, fullscreen            |
| `Service/SpaceSwitcher.swift`        | CoreGraphics                 | `@MainActor`. Every `CGEvent` call and the payload splice           |
| `UI/WindowCommandCoordinator.swift`  | AppKit                       | The one funnel from a palette row or a global hotkey                |

The feature also owns **[Window Layouts](window-layouts.md)** — saved multi-display arrangements
applied in one pass. They share this feature's switch, its Accessibility grant and its gap setting.

The first three compile into `Tests/window-command-test.swift` and `SpaceGesture.swift` compiles into
`Tests/space-gesture-test.swift`, so none of them may gain an AppKit, SwiftUI or `NSScreen`
dependency, and all must stay pure — `WindowActionMemory` takes `now` as a parameter rather than
reading a clock. CoreGraphics is needed only because `CGRect`'s `Equatable` conformance lives in that
overlay rather than in Foundation.

Adding a command is four edits in `WindowCommand.swift` (a case in `ID`, plus `name`, `symbol` and
`group` arms), an arm in `WindowPlacementEngine.placement` or `tileFractions`, and bumping
`commands.count == 34` and its group count in the harness. A command opening a new family also needs
a `Group` case and its `title` arm; `ID.allCases` stays in group order.

## Coordinate space

**`WindowPlacementEngine` works exclusively in AX space**: global coordinates, top-left origin, +Y pointing
_down_. `WindowMover.AXGeometry` is the only place that converts to and from Cocoa's bottom-left space.
The visible consequence is that Top Half has `minY == visibleFrame.minY`, which the harness asserts
specifically to stop a bottom-left convention creeping back in.

The flip is anchored on the **primary** display's height — the display whose Cocoa frame origin is
`(0, 0)` — never on the window's own screen. Both global spaces are anchored on the primary; flipping
through the window's own screen height shears every rect on a differently-sized display by the height
difference. That bug is invisible on a single monitor and wrong on every mixed-size multi-monitor
setup, so it is worth stating twice.

`AXGeometry` is snapshotted once per command: `NSScreen.screens` can change between calls on hotplug,
wake or a resolution change, and mixing two anchors inside one command corrupts the result.

Nothing here touches `backingScaleFactor`. `NSScreen.frame`, `NSScreen.visibleFrame` and AX
coordinates are all in points, so mixed-DPI correctness is automatic; a scale factor appearing anywhere
in this feature is a bug. `visibleFrame` already excludes the menu bar, the Dock and the notch.

## Geometry

**Tiles** come from fractional bounds of `visibleFrame`. Gaps use one rule that composes across every
family: an edge sitting on the screen boundary takes the full gap, an interior edge takes half. Two
adjacent tiles therefore leave exactly `gap` between them and every screen edge is inset by `gap`, with
no per-family special cases. Rects are rounded on their four **edges**, not origin + size, so two tiles
sharing a fractional boundary (480.333 for thirds of 1441) round it identically — no overlaps, no
one-point seams.

**Free-floating commands** (Maximize, Almost Maximize, Reasonable Size, Center, Make Larger/Smaller,
the nudges) work in
`canvas = visibleFrame.insetBy(gap)` instead: a centred window has no neighbour to gutter against.

**Make Larger / Make Smaller** step by 5% of the _screen_, not of the window, and the step is forced
even so each edge moves a whole point. That makes the two commands exactly invertible — `size × 0.95 ×
1.05 ≠ size`, so a size-relative step would shrink a little on every round trip — and it feels the same
at any window size. Both directions saturate into exact no-ops: the ceiling is the canvas, the floor is
`max(200×150, 15% of canvas)`.

**Reasonable Size** is 60% of the canvas, centred, capped at 1025×900 points. The cap is what makes it
display-independent — a laptop gets the fraction, a 4K or 5K display gets a moderate window instead of
a 2304×1296 one. It ignores the window's current size entirely, so it is idempotent.

**Center Half** is half the screen's _area_: half width, full height, horizontally centred — the family
sibling of Center Third.

An oversized or off-screen window is always clamped back onto the display; `clamped` pins the leading
edge rather than shoving the window off the far side. Maximize Height and Maximize Width keep the
untouched axis's position but clamp it, so a window sitting off the display doesn't come back
full-height and still off-screen.

## Cycling and Restore

Both reduce to one question — _has the user moved this window themselves since our last action?_ — so
`WindowActionMemory` answers it once. It is generic over the key so it stays Foundation-only: the app
keys by `AXUIElement` (via `CFEqual`/`CFHash` plus the pid), the harness keys by `Int`.

`decide` is a pure query returning the cycle step, which is then fed into `WindowPlacementEngine.Input.step` —
cycle state is never hidden inside the geometry. Its rules, in order:

1. No record → step 0, capture the current frame as the restore point, `canRestore: false`.
2. The frame drifted from `appliedFrame` by more than 2 pt → step 0, **and refresh** the restore point.
3. A different command, a different display, cycling disabled, a non-cycling command, or a lapsed
   `cycleTimeout` → step 0.
4. Otherwise → `(step + 1) % 3`.

Two details carry their weight:

- **Rule 2 compares against the frame we observed, never the one we asked for.** Terminal resizes in
  whole character cells and never lands exactly on target; comparing against the target would read as
  "the user moved it" on every press and break both cycling and Restore for such apps.
- **Restore is single-level, not a stack.** Left Half → Maximize → Top Right → Restore lands on the
  original frame, because rule 1 captures once and the intermediate actions never overwrite it. A stack
  has no defensible answer for what a _second_ Restore press should do.

Rule 1 also delivers the "works for windows Tinycast never moved" requirement: the capture happens in
`WindowMover.perform` before a single write.

**Cycling covers the four halves only** (½ → ⅓ → ⅔), and is off by default. Top and Bottom Half cycle
through _vertical_ thirds, which have no commands of their own — the Thirds group is horizontal — so
they are expressed as fractions rather than other command IDs.

Growth is bounded three ways: an LRU cap of 64, an `NSWorkspace.didTerminateApplicationNotification`
observer (the house `NotificationToken` RAII idiom) dropping a quit app's keys, and lazy invalidation
when a read fails. Nothing is persisted.

## Applying a placement

`WindowMover.perform(_:target:gap:cycleOnRepeat:)` is the only entry point. `target` is **explicit**
because the palette is frontmost when a command dispatches from it — `WindowCommandCoordinator` passes
`windowController.previousApp`, the same recorded app the paste path targets, and restores focus to it
rather than dropping it. It is synchronous: every AX call is a bounded mach round trip capped by a 1s
messaging timeout, and `await` would only add reentrancy between a held hotkey's repeats. The timeout
is set on the application element _and again_ on the window element — it is per-element and never
inherited.

The write sequence is **size → position → size**. Whichever single order you pick is wrong in one
direction: growing first fails when the source display is smaller than the target size, shrinking first
leaves the window shrunken after a cross-display move. Writing the size on both sides of the position
write costs one extra round trip and makes both directions correct with no branching; one of the two is
always a no-op.

**Failing quietly** is a requirement, not a nicety, and has three distinct paths:

- Position not settable → return with **zero** writes; the window is untouched.
- Size not settable → the move-only branch: one position write placing the size it already has inside
  the slot per the placement's anchor. One coherent move, never a half-applied one.
- The position write fails after the shrink → roll the size back. Net visible effect: nothing.

The frame is read back **once** afterwards, for three reasons: to detect an app-imposed minimum size
(AX exposes no attribute for it, so the read-back is the only way to learn it), to record a truthful
`appliedFrame`, and to report whether anything actually changed. When the app refused to shrink, the
window is re-placed per the placement's `anchor` so a left half stays left-aligned instead of drifting
centre. **One correction, no loop** — iterating against an app that fights back just makes the window
visibly jitter.

**Toggle Fullscreen** uses the undocumented `AXFullScreen` attribute, falling back to pressing
`AXFullScreenButton`, then a quiet no-op. There is deliberately no synthetic ⌃⌘F third attempt: it is
app-rebindable and could fire an unrelated menu command. It does not read geometry back — the
transition is animated and asynchronous, so any frame read there is a mid-animation value — and it
clears the cycle chain while keeping the restore point, since macOS restores the pre-fullscreen frame
itself but the user's original frame is still the right Restore target.

Windows that are minimized, not `AXWindow`-roled (sheets, popovers), already natively fullscreen, or
that report no position or size are rejected before any work happens.

`AXEnhancedUserInterface` is cleared for the duration of the writes and restored immediately, because
some apps reinterpret frame writes while it is on — but never while VoiceOver is running, which would
break the screen reader. **This mitigation is inherited convention and unverified on macOS 26**; if a
stock Electron app tiles correctly without it, delete the helper rather than keep it.

## Switching Space

Switch to Next/Previous Space does not move a window at all. It synthesises the **trackpad Dock swipe**
macOS switches Spaces with, at a velocity high enough that the WindowServer completes the transition
instead of animating it — about 56 ms against roughly 1100 ms for the system's own ⌃← / ⌃→.

Everything else was measured and rejected: `CGSManagedDisplaySetCurrentSpace` updates the bookkeeping
but never performs the transition, so you keep looking at the same windows; a synthetic ⌃← is ignored
because the Space hotkey only accepts real HID events; and driving System Events costs the full
animation. The gesture is the only path that both works and skips the slide, and it needs no private
framework linkage and no SIP change — only public `CGEvent` calls carrying undocumented field numbers.

`SpaceSwitcher` posts three phases — began, changed, ended — to `.cgSessionEventTap`. A two-phase
gesture is ignored. Fields 55 (`DockControl`), 110 (dock-swipe HID type), 132 (phase), 123 (horizontal
motion) and 124 (progress) are common to both encodings; **positive is always "next"**. Progress is
deliberately the smallest representable nudge: a real distance makes the WindowServer draw the slide.

**macOS 27 changed the contract.** Through macOS 26 the public fields are enough, and velocity (129 and
130) rides on every phase. From macOS 27 the Dock validates the gesture against a raw IOHID queue
payload that no setter can reach, so `SpaceSwitcher` serialises the event with `CGEventCreateData`,
appends the payload as a field-4205 record, and reparses it with `CGEventCreateFromData`. That path
also adds fields 134, 138, 169 and 125, and carries velocity **only** on the ended phase — velocity
earlier makes the Space slide back before it settles. `SpaceGesture` owns both tables so the two
encodings can never drift apart, and the runtime OS selects between them: the SDK cannot, because a
build made on 26 still has to work on 27.

Three details are load-bearing and each was expensive to learn:

- **Phases are paced ~10 ms apart on macOS 27.** Posted back-to-back they coalesce and the Dock moves
  two Spaces. That pacing is why `perform` is asynchronous rather than a straight-line call.
- **Velocity is momentum, not latency.** 2000 overshoots by two Spaces; 1000 lands exactly one, and
  lowering it does not make the switch slower.
- **The Dock ignores a gesture from a short-lived process.** The calls all report success and nothing
  happens. Tinycast is a resident menu-bar app, so this is free — but it is why a one-shot CLI cannot
  be used to reproduce a bug here.

Boundaries are left to macOS. The private `CGSGetActiveSpace` lags behind the Dock after a synthetic
switch, so a pre-check returns stale answers during exactly the rapid switching it would exist to
protect; skipping it also means this feature links no private symbol at all. A second gesture arriving
while one is in flight is dropped rather than queued, for the same reason the phases are paced.

The serialized `CGEvent` format is a big-endian tagged record list behind a version word, which
`SpaceSwitcher` checks is `2` before splicing; a bumped version makes the command a quiet no-op rather
than posting a corrupt event. The payload itself is packed little-endian with 16.16 fixed-point
scalars, which is why `SpaceGesture.fixed1616` floors to ±1 — the tiny progress value would otherwise
quantize to zero and the gesture would do nothing.

## Wiring

- **`AppEntry.Kind.windowCommand`** — entries are `window-command:<id>`, published by
  `AppIndex.setWindowCommandsVisible(_:)` between the system-action and custom-command slices.
  `LauncherView.rows` mirrors that position with a "Window Management" section; the slice order is the
  flat-selection invariant, so the two must move together.
- **`HotKeyAction.windowCommand(id:)`** — persisted under
  `hotkey.windowCommand.<raw-id>`, matching the shared `HotKeyAction.defaultsKey` convention. Unlike
  custom commands there is no bound-ID index to maintain: the catalog is fixed, so `HotKeyManager.start`
  and `conflictOwner` iterate `WindowCommand.ID.allCases` and `register` no-ops on an unbound command.
- **`WindowCommandCoordinator.runWindowCommand(id:)`** is the one funnel for both palette activation and the global
  hotkey, so the feature switch cannot be bypassed by either. A Space command branches out of it first
  and hides the palette with `restoreFocus: false`: restoring focus reactivates the recorded previous
  app, and activating an app that lives on another Space pulls that Space forward — a race against the
  gesture that can land on the opposite Space from the one asked for.
- **Settings** — `windowManagementEnabled` (off), `windowManagementShowInLauncher` (on), `windowGap`
  (0) and `windowCycleOnRepeat` (off). All four ride in settings backups: unlike `snippetsEnabled` they
  grant no permission class of their own.
- **Per-command visibility** reuses `VisibilityStore` as-is; clearing a recorded shortcut is how a
  hotkey is disabled, so there is no separate per-command enabled flag. Window commands deliberately
  get **no** launcher-category pane of their own — they are managed inside Settings › Window
  Management, the same call already made for snippets.

## Testing

`Tests/window-command-test.swift` (357 assertions) covers the catalog, the AX-space convention lock,
tiling on divisible and non-divisible screens, off-origin and negative-coordinate displays, gap
arithmetic including degenerate values, sizing, the Make Larger/Smaller round trip, nudges, display
moves and wrapping, restore recovery, every `WindowActionMemory` rule, and a fuzz sweep over every
command × gap × screen × degenerate window frame checking for non-finite output, negative dimensions,
off-screen results, non-determinism and drift on repeat.

`Tests/space-gesture-test.swift` (121 assertions) covers the other pure half: the fixed-point encoding
and its ±1 floor, both field tables and the sign convention shared between them, the ended-only fling
on the augmented path, the payload's size, record offsets and every scalar in it, and the big-endian
framing of the field-4205 record.

Everything runs headless because the layer is pure. `WindowMover` and `SpaceSwitcher` are not compiled
into either harness and have no automated coverage — the AX and `CGEvent` paths need manual
verification, particularly:

1. A non-resizable window (System Information) must fail silently, left untouched rather than
   half-moved.
2. **A mixed-resolution multi-monitor setup** — the coordinate-flip bug appears nowhere else. Tile on
   the secondary display, then round-trip Next/Previous Display.
3. Toggle Fullscreen on a window that accepts it and one that refuses it.
4. Cycling: three presses of Left Half, then drag the window and confirm the next press restarts at ½.
5. Restore on a window Tinycast has never moved.
6. **Space switching, on the real desktop with three or more Spaces.** Next and Previous each move
   exactly one Space with no visible slide, in and out of a fullscreen Space, and a held shortcut does
   not wedge the Dock or land two Spaces at once. A Space switch is not observable until it settles —
   sampling sooner than about three seconds returns mid-transition state that reads as a dropped or
   doubled move, which will make a working build look broken.
