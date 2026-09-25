---
title: Rooms
description: Keep a project's windows together, then walk into it with one shortcut while everything else steps back.
---

A room is a project you walk into: a set of windows and a layout. Enter one and its windows come to
the display you are on and lay themselves out, with the gap you chose. Apps with nothing in the room
hide, and other windows of the room's apps wait just off-screen. Nothing is ever closed.

Rooms are part of [Window Management](/docs/features/window-management). They use its switch, its
Accessibility grant and its gap setting. Rooms is based on [Rooms](https://github.com/saragordic/rooms)
by Sara Gordić, used with her permission under the MIT licence.

## Making a room

1. Open the windows the project needs.
2. Run **Switch Room**, type a name for the room, and choose **Create Room**.
3. Press ↵ on each window that belongs in it. To add an app that is not open, type its name and
   pick it: it opens whenever you enter the room. The number is the place, and 1 is the main
   window, which gets the largest spot. The preview shows the room as you pick.
4. Press ⌘↵ to save. You walk straight into the new room.

**Create Room** in the launcher and **New Room** in Settings open the same picker.

## Switching rooms

Run **Switch Room**. The selected room is previewed over your blurred desk.

| Key    | What it does                                                         |
| ------ | -------------------------------------------------------------------- |
| ↑ ↓    | Pick a room; the preview glides to it                                |
| ⇥ / ⇧⇥ | Try the next or previous layout that fits this display               |
| ↵      | Enter the room                                                       |
| ⌘K     | Remember Arrangement, Choose Windows, Show All Windows, Delete Room  |
| ⌘⌫     | Delete the room; its windows stay open                               |

Every room is also a launcher entry, and each can have its own global shortcut in
**Settings → Window Management → Rooms**.

## Layouts

Tab offers only the layouts that fit the room's windows on this display, and each display remembers
its own choice.

| Layout      | Arrangement                                                              |
| ----------- | ------------------------------------------------------------------------ |
| Auto        | The first tidy layout where every window is comfortable                  |
| Focus       | The main window large on the left, the rest beside it                    |
| Stack       | Focus, with the side windows overlapping so each title bar shows         |
| Columns     | Side by side                                                             |
| Grid        | An even grid                                                             |
| Custom      | Your own side-by-side arrangement, snapped to a grid with even gaps      |
| As Arranged | Exactly where you placed the windows                                     |

Arrange the windows by hand and choose **Remember Arrangement**: Tinycast recognises the layout and
tidies it, or keeps your arrangement exactly. Apps that refuse to shrink are measured as you go, so
the layouts make room for them.

## Getting everything back

**Show All Windows** brings back every parked window and every app a room hid. Quitting Tinycast,
turning Window Management off, or opening Tinycast again after a crash also brings parked windows
back: each one's way home is written to disk before it moves.

Rooms work with ordinary windows on the current Space. Full-screen windows are left alone.
