---
title: The palette
description: The one window Tinycast has — how to move around it, and where it appears.
---

Everything Tinycast does happens in one floating panel. Each feature is either the root launcher
screen or a screen you reach from it, and every screen backs out to the launcher.

## Moving around

| Key                       | Does                                                  |
| ------------------------- | ----------------------------------------------------- |
| <kbd>↵</kbd>              | The primary action for whatever is selected           |
| <kbd>⌘</kbd><kbd>↵</kbd>  | The secondary action — usually Show in Finder or Copy |
| <kbd>⌘</kbd><kbd>K</kbd>  | Open the Actions menu for the selection               |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move the selection                                    |
| <kbd>⇥</kbd>              | Cycle between the launcher and clipboard              |
| <kbd>⎋</kbd>              | Leave a screen, or dismiss the palette                |
| <kbd>⌫</kbd>              | On an empty field, step back one screen               |
| <kbd>⌘</kbd><kbd>,</kbd>  | Open Settings                                         |
| <kbd>⌘</kbd><kbd>W</kbd>  | Close the window                                      |

**<kbd>⌘</kbd><kbd>K</kbd> is how you learn the app.** Every screen lists its full action set there,
with each action's shortcut printed beside it. The full table is in
[Keyboard shortcuts](/docs/reference/shortcuts).

### Emacs chords

If you have the muscle memory, these work anywhere in the palette:

| Chord                    | Same as      |
| ------------------------ | ------------ |
| <kbd>⌃</kbd><kbd>N</kbd> | <kbd>↓</kbd> |
| <kbd>⌃</kbd><kbd>P</kbd> | <kbd>↑</kbd> |
| <kbd>⌃</kbd><kbd>F</kbd> | <kbd>→</kbd> |
| <kbd>⌃</kbd><kbd>B</kbd> | <kbd>←</kbd> |

On the [emoji grid](/docs/features/emoji) all four move the selection. Everywhere else the
horizontal pair falls through to the text caret, because moving a caret is what you usually mean
there. A chord with any extra modifier — <kbd>⌃</kbd><kbd>⇧</kbd><kbd>Q</kbd>, say — is left alone.

### Tab is narrower than it looks

<kbd>⇥</kbd> cycles the launcher and clipboard, and nothing else. Calculator History, Search
Quicklinks and Uninstall stay out of the cycle deliberately — they are destinations you chose, not
places to land in by accident.

The exception: when the selected row declares arguments — a
[quicklink](/docs/launcher/quicklinks) or an [extension command](/docs/extensions) that takes input
— <kbd>⇥</kbd> walks those fields first.

## Where it opens

**Settings → General → Appearance** holds both placement settings.

**Follow the cursor across displays** (on by default) opens the palette on whichever display the
pointer is on. Turn it off to always use the display with the menu bar.

**Drag to reposition** (off by default) lets you move the panel. Grab the thin strip just above the
search field, the header margins, or the search field past the end of its text — clicking on the
text still edits it, the way Spotlight behaves.

While you drag, dotted guides mark the default position and light up when you are close enough to
snap. Release there and it snaps home and forgets any remembered position; release elsewhere and
that position persists across restarts.

A remembered position outranks the display setting. It is dropped only when no connected display can
show the palette any more — you unplugged a monitor, or changed resolution. It is deliberately left
out of settings backups, since window geometry does not travel between machines.

## Input source

**Settings → General → Auto-switch input source** picks a keyboard source to apply while the palette
is open.

If you type Japanese or Chinese most of the day but your app names are Latin, this saves a switch
every single time you open the launcher. Tinycast captures the source when the palette opens, applies
your choice, and restores the original on hide — but only if the palette is still on the source it
applied, so a switch you made yourself while it was open is respected.

## Appearance

**Settings → General → Appearance → Theme** offers **System**, **Light** and **Dark**.

System follows macOS live. Light is the same design with the ink inverted — nothing about the
layout, type, motion or behaviour changes between them.

The [Toggle System Appearance](/docs/launcher/system-actions) action changes _macOS itself_.
Tinycast follows that only while its own theme is set to System.

## Compact mode

**Settings → General → Appearance → Compact mode** opens the launcher as a slim search bar that
expands into the full list as you type. <kbd>↓</kbd> expands it and selects the first row.

With **Show favorites in compact mode** on, your favorite app icons sit at the right of the bar and
<kbd>⌘</kbd><kbd>1</kbd> through <kbd>⌘</kbd><kbd>5</kbd> launch them; a **…** button appears past
five to expand into the rest. The same numbers work in the expanded list. See
[Favorites](/docs/launcher/favorites).

## Pop to root

**Settings → General → Pop to Root Search** decides how long after the window closes Tinycast resets
to the launcher: **Immediately** (default), or after 5, 15, 30, 60 or 90 seconds.

Raise it if you often dismiss the palette and come straight back to the same screen.

The delay covers dismissing the palette yourself. An extension command that closes the window as it
finishes — opening a project, say — resets to the root immediately whatever the delay says, so you
come back to a fresh search rather than a command you are done with. An extension can also ask to
keep its screen, and that request is honoured.
