---
title: Window management
description: 35 commands for halves, quarters, thirds, sizing, nudges, displays and fast Space switching.
---

Move and resize the window you were last using, without installing another app.

**It doesn't need any new permissions.** It uses the same [Accessibility](/docs/permissions)
permission as clipboard pasting.

Turn it on in **Settings → Window Management**. It's **off** by default. While it's off, the
launcher has no window commands, and shortcuts you recorded don't move anything.

The same pane also has [window layouts](/docs/features/window-layouts), which are saved arrangements
of several windows across your displays.

## The commands

**Halves** · Left Half · Right Half · Top Half · Bottom Half

**Quarters** · Top Left Quarter · Top Right Quarter · Bottom Left Quarter · Bottom Right Quarter

**Fourths** · First Three Fourths · Last Three Fourths

**Thirds** · First Third · Center Third · Last Third · First Two Thirds · Last Two Thirds

**Sizing** · Maximize · Almost Maximize · Reasonable Size · Maximize Height · Maximize Width ·
Center · Center Half · Center Two Thirds · Make Larger · Make Smaller · Restore Window

**Moving** · Move Left · Move Right · Move Up · Move Down · Move to Next Display · Move to Previous Display

**Fullscreen** · Toggle Fullscreen

**Spaces** · Switch to Previous Space · Switch to Next Space

## Settings

| Setting                  | Options                                  | Default  |
| ------------------------ | ---------------------------------------- | -------- |
| Enable window management | On · Off                                 | **Off**  |
| Show in launcher         | On · Off                                 | On       |
| Cycling                  | None · Cycle ½, ⅓ and ⅔ · Cycle displays | **None** |
| Gap between windows      | 0 to 64 points, in steps of 2            | **0**    |

Each command's shortcut, alias and launcher checkbox are in the same pane. To turn off a single
command, clear its shortcut and its checkbox. There's no separate switch for each command.

**Shortcut preset** fills in the window shortcuts of **Rectangle / Magnet** or **Spectacle**. Choose
one and click **Apply**. Commands the preset doesn't cover keep their shortcuts, and if it would
replace a shortcut you recorded, Tinycast asks first. A key that something else in Tinycast already
uses is skipped. Every shortcut stays editable afterward.

## How sizes are calculated

**Gaps.** Edges next to the screen border get the full gap, and edges between two windows get half,
so two windows side by side have exactly one gap between them, and every screen edge is inset by one
gap. Edges are rounded so thirds never overlap or leave a one-point line between them.

**Make Larger and Make Smaller** change the size by 5% of the _screen_, not the window, so each one
exactly undoes the other. The largest size is the full screen. The smallest is 200 × 150 points or
15% of the screen, whichever is larger. Beyond those limits, they do nothing.

**Reasonable Size** is 60% of the screen, centered, and never larger than 1025 × 900 points, so on a
large 5K display you get a comfortably sized window. Pressing it again doesn't change anything.

**Center Half** is half the screen's width at full height, centered. **Center Two Thirds** is the
same at two thirds of the width.

A window that's too large or partly off-screen is always moved back onto the display. The usable
area already excludes the menu bar, the Dock and the notch.

## Custom sizes

When no built-in size suits your screen, make your own. In
**Settings → Window Management → Custom Sizes**, click **New Custom Size** and give it a name, a
width and a height. Each is in points or a percentage of the screen. Then choose a position on a
3 × 3 grid, with an optional offset in points.

A custom size works like a built-in command. It has its own launcher entry, shortcut, alias and
checkbox, and it follows **Show in launcher**. It resizes the window you were last using, on the
display it's already on, so one shortcut works on your laptop and at your desk. A size larger than
the screen fills the screen instead.

Restore Window undoes a custom size. Custom sizes never cycle.

## Cycling and Restore

**Cycling** only applies to the four halves and Center Half, and it's off by default. With cycling
off, pressing Left Half again leaves the window where it is. The two cycling modes work like this:

- **Cycle ½, ⅓ and ⅔** changes the width with each press, keeping the same side. Top Half and Bottom
  Half cycle through heights instead. Center Half stays centered as its width changes.
- **Cycle displays** moves the window through every half of every display, so one shortcut can reach
  your whole setup. With two displays, Left Half goes from Display 1 left → Display 2 right →
  Display 2 left → Display 1 right, then starts over. With one display, it does nothing. Center Half
  stays where it is in this mode.

The cycle starts over when you move or resize the window yourself (by more than 2 points), use a
different command, or move the window to a different display. Waiting between presses doesn't reset it.

**Restore Window returns to the saved starting position.** Left Half → Maximize → Top Right
Quarter → Restore Window puts the window back where it **started**, not where it was before the last
command.

Tinycast saves the starting position before its first change. Restore Window does nothing until
Tinycast has moved that window. Moving or resizing the window yourself gives the next command a
new starting position. Tinycast remembers up to 64 windows, forgets an app's windows when the app
quits, and never saves this information to disk.

## Fullscreen

**Toggle Fullscreen** first asks the window to enter fullscreen, then tries clicking its green
button. If neither works, it does nothing.

It never sends <kbd>⌃</kbd><kbd>⌘</kbd><kbd>F</kbd>, because apps can use that shortcut for
something else, and triggering the wrong command would be worse than doing nothing.

It resets the cycle but keeps the Restore point.

## Spaces

**Switch to Previous Space** and **Switch to Next Space** switch between macOS Spaces
**without the sliding animation**. A switch takes about 56 ms, compared with about a second for the
system's own <kbd>⌃</kbd><kbd>←</kbd> and <kbd>⌃</kbd><kbd>→</kbd>.

They send the same trackpad swipe macOS uses to switch Spaces, fast enough that the switch completes
without animating. Both desktop Spaces and fullscreen Spaces are included.

If you hold down the shortcut, presses that arrive during a switch are ignored, so a long press
never skips too far. At the first or last Space, macOS behaves as it normally does.

## When a window won't move

Minimized windows, sheets, popovers, windows already in native fullscreen, and windows that don't
report a position or size are skipped.

A window that can move but can't be resized keeps its size and moves to the command's position.
A window that can't move is left untouched. If an app won't let its window shrink, Tinycast aligns
the window to the correct side **once** instead of retrying.
