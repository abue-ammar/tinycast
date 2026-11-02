---
title: Rooms
description: Group a project's windows, then switch to them with one shortcut while everything else moves aside.
---

A room is a saved set of windows for one project, with a layout. When you enter a room, its windows
move to the display you're on and arrange themselves with the gap you chose. Apps that have no
windows in the room are hidden, and the room's apps' other windows move just off-screen. No window is
ever closed.

Rooms are part of [Window Management](/docs/features/window-management). They use its switch, its
Accessibility permission and its gap setting. The feature is based on
[Rooms](https://github.com/saragordic/rooms) by Sara Gordić, used with her permission under the MIT
license.

## Making a room

1. Open the windows the project needs.
2. Run **Switch Room**, type a name for the room, and choose **Create Room**.
3. Press <kbd>return</kbd> on each window you want in the room. To add an app that isn't open, type
   its name and select it, and it opens whenever you enter the room. The number shows the window's
   position, and 1 is the main window, which gets the largest space. The preview updates as you
   choose.
4. Press <kbd>⌘</kbd><kbd>return</kbd> to save. Tinycast switches to the new room right away.

**Create Room** in the launcher and **New Room** in Settings open the same picker.

## Switching rooms

Run **Switch Room**. The selected room is previewed over a blurred view of your desktop.

| Key                                         | What it does                                           |
| ------------------------------------------- | ------------------------------------------------------ |
| <kbd>↑</kbd> <kbd>↓</kbd>                   | Choose a room; the preview moves to it                 |
| <kbd>tab</kbd> / <kbd>⇧</kbd><kbd>tab</kbd> | Try the next or previous layout that fits this display |
| <kbd>return</kbd>                           | Enter the room                                         |
| <kbd>⌘</kbd><kbd>K</kbd>                    | Remember Arrangement, Choose Windows, Delete Room      |
| <kbd>⌘</kbd><kbd>N</kbd>                    | Create a room named after your search                  |
| <kbd>⌃</kbd><kbd>X</kbd>                    | Delete the room; its windows stay open                 |

Every room is also a launcher entry, and each one can have its own global shortcut and alias in
**Settings → Window Management → Rooms**. **Show rooms in launcher** (on by default) takes every room
and the two room commands out of search at once.

## Layouts

<kbd>tab</kbd> only offers layouts that fit the room's windows on the current display, and each
display remembers its own choice.

| Layout      | Arrangement                                                           |
| ----------- | --------------------------------------------------------------------- |
| Auto        | The first tidy layout where every window has enough room              |
| Focus       | The main window large on the left, the rest beside it                 |
| Stack       | Like Focus, with the side windows overlapping so each title bar shows |
| Columns     | Side by side                                                          |
| Grid        | An even grid                                                          |
| Custom      | Your own side-by-side arrangement, snapped to a grid with even gaps   |
| As Arranged | Exactly where you placed the windows                                  |

To use your own arrangement, place the windows by hand and choose **Remember Arrangement**. Tinycast
recognizes the layout and tidies it, or keeps your arrangement exactly as it is. Tinycast measures
apps that won't shrink as you go, so layouts leave enough room for them.

## Getting everything back

Quitting Tinycast, turning off Window Management, or reopening Tinycast after a crash returns every
moved window to where it was, because Tinycast saves each window's original position to disk before
moving it. Turning off Window Management while you're in a room also shows the apps it hid.

Rooms work with regular windows on the current Space. Full-screen windows aren't moved.
