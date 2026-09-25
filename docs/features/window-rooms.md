# Rooms

A **room** is a project you walk into: a named set of windows, in order, and how they lay out.
Entering one brings its windows to the display you are on, tiles them with Window Management's
gap, and steps everything else back — apps with nothing in the room hide, and other windows of
the room's apps park just off-screen. Nothing is ever closed.

The palette's **Switch Room** screen lists the rooms; the selected one is previewed over a blurred
desk, and **Tab** tries its next layout while the cards glide there. Rooms ride on Window
Management's switch, its Accessibility grant and its `windowGap`, and add no dependency.

Adapted from [Rooms](https://github.com/saragordic/rooms) by Sara Gordić, with her permission and
under its MIT licence; [NOTICE.md](../../NOTICE.md) lists the adapted files.

## Invariants

- **A window's way back is on disk before it moves.** `RoomParkingLedger.record` writes
  synchronously and returns false when the write fails, and then the window is not parked. An
  entry is forgotten only once its window is confirmed back — mostly inside its room spot, or
  within 16 pt of its saved frame — so a busy app keeps its way back for the next try.
- **Every parked window comes home** on quit (`prepareForTermination`, which is synchronous for
  that reason), when the feature switch turns off, and at the next launch after a crash
  (`recoverParkedWindows`). Switching the feature off also unhides the apps rooms hid, and only
  those: neither it nor a launch may undo a ⌘H the user made themselves. Entering another room returns any parked
  window whose app it hides.
- **Parking needs the window-server number.** `AXWindowAccess.windowID(of:)` resolves the private
  `_AXUIElementGetWindow` at run time; without it the room still lays out and hides other apps,
  but no window parks. This reverses [Navigation](navigation.md#recency-without-a-private-symbol)'s
  call for rooms only, because a ledger entry must outlive every `AXUIElement`.
- **`RoomPlan` decides everything before the first write, and is pure.** Matching, frames, what
  parks and which apps stay visible come out of one call the harness pins; `RoomRunner` only
  carries the plan out.
- **A layout that no longer fits falls back to Auto** instead of overlapping or leaving the screen:
  a stored Focus, Columns or Grid is re-checked with `fits` on every enter, `.custom` needs every
  room window present and a clean draw, `.saved` must fit the visible frame.
- **One gap, one convention.** `RoomLayoutEngine.Area` sanitizes `windowGap` with
  `WindowPlacementEngine.sanitizedGap` and tiles inside `WindowPlacementEngine.canvas`, so a room
  and a snapped half sit on the same lines. Gap 0 tiles edge to edge.
- **Window work runs one at a time, in order.** `RoomCoordinator.inTurn` chains every enter and
  every restore: two passes at once would each hide what the other just showed.
- **The runner never touches `WindowActionMemory`**, exactly as layouts do not.
- **`Model/` stays Foundation + CoreGraphics.** Screens arrive as `WindowLayoutScreen`, windows as
  handle-based `RoomLiveWindow`s, minimum sizes as a dictionary; `window-room-test` compiles the
  shipped files.

## Layout

| File | Role |
| --- | --- |
| `Model/Room.swift`, `RoomWindow.swift`, `RoomLayoutKind.swift` | The record: windows in order, a layout, per-display layouts, recency |
| `Model/RoomLayoutEngine.swift` | **Pure.** Focus, Stack, Columns, Grid and Auto, honouring minimum sizes |
| `Model/RoomGrid.swift` | **Pure.** A room's own arrangement on a 12 × 12 grid with even gaps |
| `Model/RoomArrangement.swift` | **Pure.** Reads a hand-made arrangement; rebuilds a room from open windows |
| `Model/RoomWindowMatcher.swift` | **Pure.** Which open window fills which room window |
| `Model/RoomParking.swift` | **Pure.** The parking corner and the way back on a connected display |
| `Model/RoomPlan.swift` | **Pure.** What entering does, and the layouts Tab offers |
| `Model/RoomStore.swift` | The library, as JSON in `UserDefaults` (`windowRooms`) |
| `Model/RoomMinimumSizeStore.swift` | Minimum sizes learned by trying (`roomMinimumWindowSizes`) |
| `Model/RoomParkingLedger.swift` | Parked windows' ways back, `room-parking.json` in Application Support |
| `Service/RoomWindowSweep.swift` | One AX sweep, minimized and hidden apps' windows included |
| `Service/RoomRunner.swift` | Enters a room; returns parked windows |
| `Service/RoomSession.swift` | The Rooms screens' state while open |
| `UI/RoomCoordinator.swift` | The one funnel, the preview, the picker, the library, cleanup |
| `UI/RoomsScreen.swift`, `RoomsList.swift` | Switch Room |
| `UI/RoomPickerScreen.swift`, `RoomPickerList.swift` | Choosing a room's windows |
| `UI/RoomPreviewController.swift`, `RoomPreviewView.swift` | The gliding preview |
| `Settings/RoomsSection.swift` | The Rooms section of Settings › Window Management |

## Layouts

`RoomLayoutKind.allCases` is Tab's order: Auto, Focus, Stack, Columns, Grid, Custom, As Arranged.

- **Focus** puts the main window left — 60% of the width, or 50% when that is what fits — and the
  rest in the right column, one to three across. When one app needs the width, its window may move
  to the last row, which spans the column.
- **Stack** is Focus with the side windows overlapping, offset 32 pt so each title bar shows.
- **Columns** tries up to four across, then fewer; **Grid** tries √n columns, then one more or less.
- **Auto** takes the first tidy layout (Focus, Columns, Grid for up to four windows; Grid first
  beyond) where every side window gets at least 480 × 360, and Stack only when nothing tidy fits.
- **Custom** is Remember Arrangement's reading of windows placed side by side by hand, snapped to
  the grid and filled so no hole remains. **As Arranged** keeps an overlapping arrangement exactly.

Every candidate is judged by `works` — on screen, every window at least 320 × 240 — before
anything is clamped. `distribute` splits a length into whole points that add up exactly, never
below an app's minimum; minimums that cannot all fit overflow, and the candidate that spills least
is pulled back on screen, because overlap beats off-screen.

AX reports no minimum size, so the runner learns one: a window that stays larger than its slot is
asked once more after 150 ms, and what it still refuses is kept per app. A new minimum re-plans
the room, at most twice — minimums only grow, so the loop ends.

## The Rooms screen

`PaletteMode.rooms`. Rooms are ranked by name and app names; with no query, the most recently
entered comes first, so the room you just left is one row away. Typing a new name offers
**Create Room “…”**, and an existing room's name offers **Choose Windows**.

- **↵** enters the selected room. **⇥ / ⇧⇥** step through `RoomPlan.layoutChoices` — the layouts
  that fit its open windows here, each drawn differently; Stack only when nothing tidier fits — and
  store the choice for this display. A single choice says so in a message.
- **⌘K** holds Enter Room, Next Layout, Remember Arrangement, Choose Windows… and Delete Room (**⌘⌫**, confirmed through `DialogController`). **⌘N** creates a room.
- The screen claims ⇥ through `PaletteScreen.tab(at:backwards:)`, asked before `tabTarget` and the
  palette's ring; every other screen keeps today's Tab.

`PaletteMode.roomWindows` is the picker, opened from a name typed on the Rooms screen (Create Room
with no name opens that screen first), so the search field filters. The windows you can see come
first, front to back, then parked, hidden and minimized ones; a query also lists installed apps with
no open window, which join the room as their app — a `RoomWindow` with no title and no ID, which
the matcher fills with any window of the app and the runner opens on entry. ↵ adds or removes the
selected member, whose number is its place (1 is the main window); ⌘↵ saves and walks in. Editing a
room starts with every member picked, a closed window standing as its app rather than dropped.

## The preview

`RoomPreviewController` owns one borderless, click-through, non-activating panel per display at
`.paletteDropGuide`, just under the palette, each hosting `RoomPreviewView`: the desk blurred
behind the window and dimmed, and one card per window — a title bar with the app and window name,
the app's icon, an accent stroke. The cards are keyed by the window's number, so a card that
exists before and after a change glides: `Theme.RoomMotion.glide`, 0.32 s on (0.2, 0, 0, 1). New
cards fade in over 0.2 s, removed ones fade out over 0.18 s. Reduce Motion drops every animation.

The screen previews its selected room on every change of selection, of the room's value (a Tab's
new layout rides in it) and of the desk read. After ↵ the preview stays while the windows move in
under it, then fades over 0.25 s. The card's icon moves out from under the palette. AX and SwiftUI
both grow downwards, so a card's frame is the AX rect offset by its display's AX origin, with no
flip. The panels are released on hide, so memory returns to baseline with the palette.

## Entering a room

`RoomCoordinator.enterRoom(id:)` is the one funnel for a Rooms row, a launcher entry, a shortcut
and Settings' Enter button. It hides the palette with `restoreFocus: false`, then `RoomRunner.enter`:

1. Prompts for Accessibility once, launches the room's apps that are not running, unhides the
   hidden ones and waits up to 600 ms for them to come back.
2. Sweeps and plans on the palette's display (`openOnCursorScreen` decides, as for the palette);
   a launched or just-unhidden app is waited on — 10 s or 600 ms — for its windows.
3. Places every window in one step, one `AXEnhancedUserInterface` suppression per app, through
   `AXWindowAccess.write`; learns minimum sizes and re-plans if one was new.
4. Parks the other windows of the room's apps — ledger first — and returns any parked window whose
   app is about to hide, then raises the room back to front, one app at a time 40 ms apart, and
   focuses the main window.
5. Hides every other app (`hide()`, falling back to the AX attribute); the desktop's own app parks
   instead, because it reappears whenever another app hides.
6. After 250 ms, re-places a window that applied its frame late or bounced — once, never a loop —
   and forgets the ledger entries of windows confirmed back.

A clean enter says nothing; a missing window names its app in a message, and a room with no open
window is a notice — and steps nothing back, since hiding everything around an empty room would
leave an empty desk. Switching the feature off unhides the apps rooms hid first and waits for them
to come back before returning parked windows.

## Wiring

- **`AppEntry.Kind.windowRoom`**, entries `window-room:<uuid>`, published by `AppIndex.setWindowRooms`
  between the window-layout and window-command slices; `LauncherList.rows` mirrors that order.
- **`HotKeyAction.windowRoom(id:)`**, persisted under `hotkey.windowRoom.<uuid>` with a
  `boundWindowRoomIDs` index, dispatched to `enterRoom(id:)`.
- **Commands**: Switch Room and Create Room, owned by
  `SettingsTab.windowManagement` and gated with the feature.
- **Settings**: `windowRoomsShowInLauncher` (on). Rooms and their shortcuts ride in settings
  backups; learned minimum sizes and the ledger do not — one is a cache, the other this Mac's state.

## Testing

`Tests/window-room-test.swift` covers the engine (every layout on laptop and monitor fixtures,
minimum sizes, Auto's choice, Stack's peeks, a sampled sweep that a fitting layout never overlaps
or leaves the canvas), gap 0 and gapped tiling, absurd and non-finite gaps, the grid and its hole
filling, arrangement reading and learning, window matching, parking corners and ways back, the
plan's placements, parks and fallbacks, Tab's choices, the record's Codable, and all three stores
with a scratch suite and a temporary directory.

`RoomWindowSweep`, `RoomRunner` and the preview need the manual sweep in
[testing.md](../testing.md#manual-regression-sweep): make a room from the palette; Tab through its
layouts and watch the cards glide; enter it and check other apps hide and extra windows park; quit,
`kill -9` then relaunch, and turning the feature off must each bring every window home; repeat with gap 0 and 16, on two displays, and with Reduce Motion on.
