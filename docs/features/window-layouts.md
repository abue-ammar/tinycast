# Window Layouts

A **Window Layout** is a saved, declarative arrangement: these apps, at these sizes, at these
positions, on these displays. Running it from the launcher or a global shortcut opens whatever isn't
running and places every window in one pass.

It rides on Window Management's switch, its Accessibility grant and its gap setting, and adds no
dependency and no permission. Sizes are stored as fractions of `visibleFrame`, so a layout is
resolution-independent by construction.

## Invariants

- **`WindowLayoutGeometry.resolve` is the only thing that decides where a window goes**, and its
  inverse `describe` lives beside it so the two cannot drift. The editor's preview calls the same
  `resolve` the runner does; a view that derived a rect itself would draw a lie.
- **`resolve(describe(frame)) == frame` for any whole-point frame inside the box.** That identity is
  what makes Capture trustworthy, and `window-layout-test` sweeps it over four displays and three
  gaps. The converse does **not** hold — `resolve` clamps and floors — so only idempotence
  (`resolve(describe(resolve(e))) == resolve(e)`) is asserted for degenerate entries.
- **A display is matched by `CGDisplayCreateUUIDFromDisplayID` and nothing else.** No name fallback,
  no ordinal guess, no fall-back-to-primary: an entry whose display is absent is *skipped*. Guessing
  would pile a three-monitor layout onto the laptop, which is worse than doing nothing.
- **The runner never touches `WindowActionMemory`.** Recording a layout's writes would make the next
  Left Half press read as "the user moved it", and would overwrite the single-level restore point.
  The visible consequence: Restore after a layout run returns the frame from before the last *window
  command*, not from before the layout.
- **Capture always writes `usesPreferredGap: false` and describes against the raw `visibleFrame`.**
  Capturing against the gapped box would bake the current gap into every fraction and residual, so
  changing `windowGap` in Settings would move every window in every captured layout.
- **`Model/` stays Foundation + CoreGraphics.** `CGDisplayCreateUUIDFromDisplayID` lives in
  ColorSync, so the UUID string is produced in `Service/AXScreens` and injected. `WindowLayoutAnchor`
  maps onto `WindowPlacementEngine.Anchor` rather than doing its own arithmetic; its SwiftUI
  `Alignment` lives in the view, not the model, or the purity grep would catch it.

## Layout

| File | Imports | Role |
| --- | --- | --- |
| `Model/WindowLayout.swift` | Foundation + CoreGraphics | **Pure.** The record, its entry, and their sanitising |
| `Model/WindowLayoutAnchor.swift` | CoreGraphics | **Pure.** The 3×3 grid's persisted spelling |
| `Model/WindowLayoutDisplay.swift` | Foundation | **Pure.** The stored display identity |
| `Model/WindowLayoutGeometry.swift` | Foundation + CoreGraphics | **Pure.** `resolve` and its inverse |
| `Model/WindowLayoutPlan.swift` | Foundation + CoreGraphics | **Pure.** What a run will do, decided before any write |
| `Model/WindowLayoutStore.swift` | Foundation | The library, as JSON in `UserDefaults` |
| `Model/WindowLayoutDraft.swift` | Foundation + CoreGraphics | One in-flight edit, owned by the sheet |
| `Service/AXWindowAccess.swift` | AppKit + ApplicationServices | Every `AXUIElement` call, shared with the mover |
| `Service/AXScreens.swift` | AppKit + ColorSync | `AXGeometry`, and displays with their UUIDs |
| `Service/WindowInventory.swift` | AppKit + ApplicationServices | What is on screen, read once per gesture |
| `Service/WindowLayoutRunner.swift` | AppKit | Applies a plan; opens what isn't running |
| `UI/WindowLayoutCoordinator.swift` | AppKit | The one run funnel, the library, the editor handoff |
| `Settings/WindowLayout*.swift` | SwiftUI | The pane's section and the editor sheet |

The first seven compile into `Tests/window-layout-test.swift`, so none of them may gain an AppKit,
SwiftUI or `NSScreen` dependency.

## Geometry

An entry is a fraction of a **box**, then a 3×3 anchor, then a point offset. The box is the display's
`visibleFrame`, or `WindowPlacementEngine.canvas(visibleFrame, gap:)` when the layout opts into the
global gap — one expression covers both, since `sanitizedGap` returns 0 for a zero gap.

`resolve` composes, in this order and for these reasons:

1. Fractions clamp into 0…1; a non-finite one reads as full.
2. The size floors at **1 pt**, not at `WindowPlacementEngine`'s `max(200×150, 15%)`. That floor is
   tuned for *repeated* shrinking; a one-shot authored fraction is a different job, and a 120 pt floor
   would break the round trip for any genuinely small window.
3. `anchor.place(size, in: box)` — the size has to exist before it can be anchored.
4. The offset is added **before** the clamp: the nudge is intent, the clamp only a safety net.
   Clamping first would let the offset push the window back off the display.
5. `clamped` pins the leading edge without resizing, then `rounded` snaps the four edges.

`describe` is the inverse. It clamps the size into the box **before** taking the ratio, so a stored
fraction is always one `resolve` can reproduce. The anchor is chosen **per axis**: `place` derives x
from the horizontal axis alone and y from the vertical alone, so the nearest of nine collapses to
3 + 3, and a tie prefers `center` (then `min`, then `max`) so the choice is deterministic.

**The residual offset is kept exact, never rounded.** A centred anchor on an odd free space lands on
a half point; rounding the residual there moves the window by a whole point on the way back, which is
the one bug the round-trip sweep caught.

## Running

`WindowLayoutCoordinator.runWindowLayout(id:)` is the one funnel for a palette row, a global shortcut
and the pane's Run button alike, so the feature switch cannot be bypassed. It hides the palette with
`restoreFocus: false` — a layout activates the apps it places, and handing focus back first pulls a
different app forward mid-pass.

`WindowLayoutRunner.run` then:

1. Prompts for Accessibility once for the whole pass.
2. Takes **one** `AXGeometry` snapshot and one `WindowInventory` sweep. Mixing two anchors inside one
   run shears every rect, exactly as it would inside one command.
3. Builds the plan, which is pure and therefore the tested half.
4. Places every window that already exists, in one go with no `await` between them, so a
   multi-window layout lands in one visible step.
5. Opens what is missing, then waits for each window and places it.

**Binding windows to entries** is greedy nearest-centre: among the app's unclaimed windows, the one
whose centre is closest to the entry's target wins. An already-correct desktop is then a no-op and
nothing swaps displays, which reading order alone would not give. An entry carrying an **argument**
always opens rather than claiming an existing window — that is the only reliable way to get another
window out of most apps, and it is what the user asked for. Two entries naming the same app *and*
argument describe one window, so the second is reported as `duplicateTarget`.

`AXEnhancedUserInterface` is suppressed **per application**, not per window, and restored in a
`defer` — the flag is application-scoped, and restoring per group means a long launch wait never
leaves it off.

### The launch wait

Opening an app does not give you a window, and AX has no window-created notification without an
`AXObserver`. So the runner polls `WindowInventory` every 200 ms up to a 10 s deadline, inside the
gesture's own `Task`, honouring cancellation and storing nothing.

This is not the polling the feature rules out; that constraint is about **steady state**. Between
runs the feature holds no timer, no observer, no registration on any foreign process. Both
alternatives are worse: an `AXObserver` needs a registration per app *including apps not yet
running*, a run-loop source and teardown; and `didLaunchApplication` fires before any window exists,
so it would still need this same wait after it. The deadline is a `ContinuousClock` instant, so a
clock step or a sleep cannot shorten it.

**The plan is never recomputed mid-run.** A display appearing during the wait is ignored until the
next run — the honest reading of "no auto-apply on display change", and what keeps the single-snapshot
invariant true for every frame in the pass.

## Capture

**Create Layout from Current Windows** is `describe` applied to the desktop. It reads every window
that is `AXStandardWindow`, not minimized, not natively fullscreen, reports geometry, and is
positionable — a stricter filter than the mover's, because a Save sheet must never become an entry.
Candidates come from `AppLauncher.quitAllTargets()`'s rule, excluded **by pid** rather than by
activation policy, since opening About flips Tinycast itself to `.regular`.

Only Accessibility is needed: `AXPosition` and `AXSize` are AX attributes. Screen Recording gates
window *titles*, which nothing here reads.

Capture never saves silently — the draft opens in the editor so it can be seen, trimmed and named.

## The editor

A settings sheet at `Theme.Size.layoutEditorSheet`, presented from the Window Management pane so the
two launcher commands can open it too. Two columns: a read-only preview, and the inspector.

- **The preview is handed its screens once** by the sheet and re-reads them only on
  `didChangeScreenParameters`. Resolving displays inside `body` would cost an AX round trip per
  keystroke.
- **The plate is the display**, drawn at its own aspect ratio and letterboxed inside the box — fit,
  never fill, or every rect inside it is misdrawn. It stays dark in both appearances, so its token is
  `adaptive`, never `ramp`.
- **No coordinate flip in the view.** `resolve` works in AX space (top-left origin, +Y down) and
  SwiftUI's y also points down. This is the one place the two conventions agree.
- **The tabs sit on the caption row, not over the canvas**, so a tab can never cover a window rect.
  The row shows a tab for every connected display *plus* any display an entry names, so a layout
  authored at a desk is still editable on the laptop. The entry picker is deliberately **not** scoped
  by the tab, for the same reason.
- **A number field never holds a bad value**: out of range clamps and shows the clamped number,
  nonsense reverts. The inline error slot is therefore only for what a field cannot prevent — an
  empty or duplicate name, or a refused write.
- **Save is `⌘↵`, not `.defaultAction`.** Plain ↵ belongs to whichever field has focus. The footer
  draws the cap because here the cap and the behaviour come from one `.keyboardShortcut`, so the
  drift `docs/ui.md`'s no-caps-on-buttons rule guards against cannot happen.

A **quicklink argument is copied as its link text, not referenced.** A run is one non-interactive
pass, so a quicklink that later grows a `{placeholder}` would have nothing to prompt with; copying
also removes a whole failure class and any run-time dependency on `QuicklinkStore`.

## Wiring

- **`AppEntry.Kind.windowLayout`** — entries are `window-layout:<uuid>`, published by
  `AppIndex.setWindowLayouts(_:)` immediately **before** the window-command slice.
  `LauncherList.rows` mirrors that position; the slice order is the flat-selection invariant, and its
  `assert` proves membership but **not** order, so the two arrays must move together.
- **`HotKeyAction.windowLayout(id:)`** — persisted under `hotkey.windowLayout.<uuid>` with a
  `boundWindowLayoutIDs` index, the shape quicklinks and custom commands use. `WindowLayoutStore`
  decodes in `init`, so its live IDs are known by the time `hotKeys.start` prunes.
- **Settings** — one new key, `windowLayoutsShowInLauncher` (on). Its own flag rather than sharing
  `windowManagementShowInLauncher`: 34 command rows and three named layouts are different amounts of
  launcher noise, and wanting the layouts without the commands is the likelier preference. Layouts
  and their bindings ride in settings backups.
- **Two commands** — `Create Window Layout` and `Create Layout from Current Windows`, both dropped
  from the launcher with the feature.

## Testing

`Tests/window-layout-test.swift` covers the record and its entry id, the anchor grid and the
AX-orientation lock, exact resolver frames, off-origin and negative-coordinate displays, offsets and
their clamping, degenerate fractions, gap arithmetic, `describe` at every anchor, the round-trip
identity, per-axis anchor independence, absent-display skipping, window binding and its determinism,
Codable round trips including a minimal hand-written payload, store CRUD, validation, sanitisation and
persistence, and a fuzz sweep over every anchor × fraction × offset × gap × display.

`AXWindowAccess`, `AXScreens`, `WindowInventory` and `WindowLayoutRunner` are not compiled into the
harness and have no automated coverage, exactly as `WindowMover` and `SpaceSwitcher` do not. They need
the manual sweep in [testing.md](../testing.md#manual-regression-sweep).
