---
title: Window layouts
description: Save an arrangement of apps across your displays, then put every window back with one shortcut.
---

A window layout is a saved arrangement: these apps, at these sizes, in these places, on these
displays. Run it and Tinycast opens anything that is not running and puts every window where it
belongs, in one pass.

Layouts are part of [Window Management](/docs/features/window-management). They use its switch, its
Accessibility grant and its gap setting, and add nothing new to install or allow.

## Making a layout

In **Settings → Window Management → Window Layouts**:

- **New Layout** starts from scratch.
- **Create Layout from Current Windows** captures the windows you have open right now.

Both are also launcher commands: **Create Window Layout** and **Create Layout from Current Windows**.

A capture never saves on its own. It opens the editor so you can see it, remove windows you do not
want, and give it a name.

### The editor

The left side previews each display with the windows drawn on it. Tabs above it switch between
displays. The right side edits the selected window.

| Field             | What it sets                                                                 |
| ----------------- | ---------------------------------------------------------------------------- |
| App               | Which app the window belongs to                                              |
| Argument          | Optional. A file, folder, web address or quicklink to open                   |
| Bring to front    | Leave this window frontmost when the layout finishes. Only one per layout    |
| Size              | Width and height, as a share of the display                                  |
| Position          | Where it sits, on a 3 × 3 grid                                               |
| Offset            | A nudge in points from that position                                         |
| Use preferred gap | Inset the window by the gap from Window Management, like the tiling commands |

The preview moves as you type. **Save** is <kbd>⌘</kbd><kbd>return</kbd>, because plain <kbd>return</kbd>
belongs to the field you are typing in.

A layout remembers the displays it was built for, and still shows their tabs when they are
unplugged, so you can edit a desk layout on your laptop.

## Running a layout

Run a layout from the launcher, from its own global shortcut, or with the ▶ button in Settings.

1. Windows that are already open move into place together, in one step.
2. Apps that are not running are opened, and each window is placed once it appears. Tinycast waits
   up to 10 seconds per app.
3. The window marked **Bring to front**, if there is one, is focused once everything else is done.

A few rules make this predictable:

- **Existing windows are matched to the nearest slot**, so a desk that is already arranged stays
  put and nothing swaps displays.
- **An entry with an argument always opens a new window.** That is the only reliable way to get a
  second window out of most apps.
- **A missing display is skipped, never guessed.** If a monitor is unplugged, the windows meant for
  it are left alone instead of piling onto your laptop screen.
- Sizes are shares of the screen, so a layout still fits after you change resolution.

**Restore Window** does not undo a layout. It returns a window to where it was before the last window
command, not before the layout ran.

## Managing layouts

Each layout in Settings has a shortcut recorder, a launcher checkbox, and buttons to run, edit,
duplicate and delete it. **Show layouts in launcher** (on by default) takes every layout and the two
layout commands out of search at once, without affecting the other window commands.

Layouts and their shortcuts travel in [backups](/docs/reference/backup). On another Mac, entries for
displays it does not have are skipped, like any missing display.
