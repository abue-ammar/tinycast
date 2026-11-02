---
title: Window layouts
description: Save an arrangement of apps across your displays, then restore every window with one shortcut.
---

A window layout is a saved arrangement of apps, with each window's size, position and display. When
you run a layout, Tinycast opens any apps that aren't running and moves every window into place.

Layouts are part of [Window Management](/docs/features/window-management). They use its switch, its
Accessibility permission and its gap setting, and need nothing else.

## Making a layout

In **Settings → Window Management → Window Layouts**:

- **New Layout** starts from scratch.
- **Create Layout from Current Windows** saves the windows you have open right now.

Both are also available as launcher commands: **Create Window Layout** and **Create Layout from
Current Windows**.

Creating a layout from your current windows doesn't save it right away. It opens the editor so you
can review it, remove windows you don't want, and name it. When you create it from the launcher, the
window you were working in is marked **Bring to front**.

### The editor

The left side shows a preview of each display with its windows. Use the tabs above it to switch
displays. The right side edits the selected window.

| Field             | What it sets                                                                    |
| ----------------- | ------------------------------------------------------------------------------- |
| App               | Which app the window belongs to                                                 |
| Argument          | Optional. A file, folder, web address or quicklink to open                      |
| Bring to front    | Puts this window in front when the layout finishes. Only one per layout         |
| Size              | Width and height, as a fraction of the display                                  |
| Position          | Where it sits, on a 3 × 3 grid                                                  |
| Offset            | An adjustment in points from that position                                      |
| Use preferred gap | Insets the window by the gap set in Window Management, like the tiling commands |

**Use preferred gap** applies to the whole layout. Layouts captured from current windows start with
it off, so running the captured layout preserves the positions you reviewed.

The preview updates as you type. Press <kbd>⌘</kbd><kbd>return</kbd> to **Save**, because plain
<kbd>return</kbd> is used by the field you're typing in.

A layout remembers the displays it was made for and keeps showing their tabs when they're
disconnected, so you can edit a desk layout on your laptop.

## Running a layout

Run a layout from the launcher, with its own global shortcut, or with the ▶ button in Settings.

1. Windows that are already open all move into place at once.
2. Apps that aren't running are opened, and each window is placed as soon as it appears. Tinycast
   waits up to 10 seconds in all for their windows.
3. The window marked **Bring to front**, if any, is focused once everything else is done. If you
   switched to another app while Tinycast was waiting, your choice is kept.

A few rules keep the results predictable:

- **Open windows are matched to the nearest position in the layout**, so an arrangement that's
  already correct keeps the same window in each position.
- **An entry with an argument opens that destination in its app**, then Tinycast waits for a new
  window. Whether the app creates one depends on the app. Repeated entries for the same app and
  argument are opened only once.
- **Windows for a missing display are skipped.** If a monitor is disconnected, its windows are left
  alone instead of piling up on your laptop screen.
- Sizes are fractions of the screen, so a layout still fits after you change the resolution.

**Restore Window** doesn't undo a layout. It returns a window to where it was before the last window
command, not before the layout ran.

## Managing layouts

Each layout in Settings has an alias field, a shortcut recorder, a launcher checkbox, and buttons
to run, edit, duplicate and delete it. **Show layouts in launcher** (on by default) removes all layouts and the
two layout commands from search at once, without affecting the other window commands.

Layouts and their shortcuts are included in [backups](/docs/reference/backup). On another Mac,
entries for displays that Mac doesn't have are skipped, the same as any missing display.
