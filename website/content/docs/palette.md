---
title: The palette
description: The one window Tinycast has, how to move around it, and how to make it yours.
---

Almost everything Tinycast does happens in one floating panel. Each feature is either the launcher,
which is the root screen, or a screen you open from it. <kbd>esc</kbd> walks back the way you came.

## Moving around

| Key                           | Does                                                 |
| ----------------------------- | ---------------------------------------------------- |
| <kbd>return</kbd>             | The main action for what is selected                 |
| <kbd>⌘</kbd><kbd>return</kbd> | The second action, usually Show in Finder or Copy    |
| <kbd>⌘</kbd><kbd>K</kbd>      | Open the Actions menu for the selection              |
| <kbd>↑</kbd> <kbd>↓</kbd>     | Move the selection                                   |
| <kbd>tab</kbd>                | Move between the launcher, AI Chat and the clipboard |
| <kbd>esc</kbd>                | Clear the search, then go back a screen, then close  |
| <kbd>⌘</kbd><kbd>esc</kbd>    | Jump back to the root search from any screen         |
| <kbd>delete</kbd>             | In an empty search field, go back one screen         |
| <kbd>⌘</kbd><kbd>,</kbd>      | Open Settings                                        |
| <kbd>⌘</kbd><kbd>W</kbd>      | Close the window                                     |

**<kbd>⌘</kbd><kbd>K</kbd> is how you learn the app.** Every screen lists all of its actions there,
with each shortcut printed beside it. The full list is in
[Keyboard shortcuts](/docs/reference/shortcuts).

Every screen except the launcher shows a back arrow in the top-left corner. Hover it to see whether
a click goes back a step or closes the window.

<kbd>⌘</kbd><kbd>esc</kbd> needs the [Accessibility permission](/docs/permissions), because macOS
keeps that chord for itself unless Tinycast catches it first.

### Emacs chords

If your fingers know them, these work anywhere in the palette:

| Chord                    | Same as      |
| ------------------------ | ------------ |
| <kbd>⌃</kbd><kbd>N</kbd> | <kbd>↓</kbd> |
| <kbd>⌃</kbd><kbd>P</kbd> | <kbd>↑</kbd> |
| <kbd>⌃</kbd><kbd>F</kbd> | <kbd>→</kbd> |
| <kbd>⌃</kbd><kbd>B</kbd> | <kbd>←</kbd> |

On the [emoji grid](/docs/features/emoji), all four move the selection. Everywhere else,
<kbd>⌃</kbd><kbd>F</kbd> and <kbd>⌃</kbd><kbd>B</kbd> move the text cursor, because that is what you
usually want in a search field. A chord with an extra modifier, like <kbd>⌃</kbd><kbd>⇧</kbd><kbd>Q</kbd>,
is left alone.

Shortcuts follow key positions, not the characters your input source types. If you write in
Japanese, Russian or another non-Latin layout, <kbd>⌘</kbd><kbd>K</kbd> is still
<kbd>⌘</kbd><kbd>K</kbd>.

## Tab moves between three screens

<kbd>tab</kbd> goes round a small loop: **launcher → AI Chat → clipboard → launcher**.

- **From the launcher, <kbd>tab</kbd> asks.** Whatever you typed is sent to a fresh AI chat as a
  question, so one key turns a search into a question. The header shows an **AI Chat** hint beside a
  <kbd>tab</kbd> key when this will happen.
- From the clipboard, your search text comes with you to the launcher.
- <kbd>esc</kbd> walks back out the way <kbd>tab</kbd> came in.

AI Chat drops out of the loop while [AI](/docs/ai) is off, and the clipboard drops out while
[clipboard history](/docs/features/clipboard) is off.

Everything else, like Calculator History or Search Quicklinks, stays out of the loop. Those are
places you chose to go, not places to land in by accident.

The one exception: when the selected row takes arguments, like a
[quicklink](/docs/launcher/quicklinks) or an [extension command](/docs/extensions),
<kbd>tab</kbd> walks through its fields first.

## How screens stack

Open a screen by typing its name in the launcher and it stacks on top, so <kbd>esc</kbd> takes you back
to the search that found it.

Open the same screen with its own global shortcut and it opens on its own, with nothing behind it.
Press that shortcut again and it closes.

**Settings → General → Escape Key Behavior** changes what <kbd>esc</kbd> does once the search is empty:

- **Navigate back or close window** (default): go back a screen, and close only at the root.
- **Close window and pop to root**: close straight away, and start at the launcher next time.

Either way, the first press clears any text you typed.

## Where it opens

**Settings → General → Appearance** holds both placement settings.

**Open on** offers **Mouse display**, **Focused window display**, and **Primary display**. Focused
Mouse display remains the default; saved cursor/primary choices are preserved. Focused window uses the
external window with the greatest overlap. Its first use per launch asks for
Accessibility, and that summon falls back to the mouse while macOS waits for approval. Without usable
focus or access, it uses the mouse display, then primary.

**Drag to reposition** (off by default) lets you move the panel. Grab the thin strip above the search
field, the empty space in the header, or the search field itself while it is empty.

While you drag, dotted guides show the default position and light up when you are close enough to
snap. Let go there and it snaps home. Let go anywhere else and Tinycast remembers that spot, even
after a restart.

A remembered spot is only dropped when no screen can show the palette any more, say after you unplug
a monitor. It is not included in backups, because window positions do not travel between Macs.

## Appearance

**Settings → General → Appearance** has these:

| Setting                        | Options                                | Default     |
| ------------------------------ | -------------------------------------- | ----------- |
| Theme                          | System · Light · Dark                  | **System**  |
| Interface size                 | Default · Large · Larger               | **Default** |
| Background transparency        | A slider from Less to More, with Reset | Middle      |
| Compact mode                   | On · Off                               | Off         |
| Show favorites in compact mode | On · Off                               | On          |

**Theme.** System follows macOS as it changes. Light is the same design with the colors inverted.
The layout, type and motion are identical.

**Interface size** makes the palette and its floating windows 10% or 20% larger. Settings itself
stays the same size.

**Background transparency** changes how much of the desktop shows through the glass. **Reset** puts
it back to the original look.

**Compact mode** opens the launcher as a slim search bar that grows into the full list as you type.
<kbd>↓</kbd> expands it and selects the first row. With **Show favorites in compact mode** on, your
favorite apps sit at the right of the bar; see [Favorites](/docs/launcher/favorites).

The [Toggle System Appearance](/docs/launcher/system-actions) action changes _macOS itself_. Tinycast
follows it only while its own theme is set to System.

## Input source

**Settings → General → Auto-switch input source** picks a keyboard layout to use while the palette
is open.

If you type Japanese or Chinese most of the day but your app names are in Latin letters, this saves
a switch every time you open the launcher. Tinycast switches when the palette opens and switches back
when it closes. If you changed the layout yourself while it was open, your choice stays.

## Pop to root

**Settings → General → Pop to Root Search** decides how long after the window closes Tinycast goes
back to the launcher: **Immediately** (default), or after 5, 15, 30, 60 or 90 seconds.

Raise it if you often close the palette and come straight back to the same screen.

AI Chat has its own rule for whether a conversation reopens; see [AI Chat](/docs/ai#coming-back-to-a-chat).

## The menu bar

The Tinycast menu bar icon has **Open Tinycast**, **Clipboard History**, **Settings…**,
**Check for Updates…**, **Support Tinycast…** and **Quit Tinycast**.

**Settings → General → Show in menu bar** hides the icon. Your shortcuts keep working without it.
