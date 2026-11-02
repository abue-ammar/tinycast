---
title: The palette
description: Move around Tinycast's floating palette and adjust its appearance and behavior.
---

The launcher, search tools and Quick AI share one floating panel. AI Chat, Notes, Camera and command
output also have their own windows. The launcher is the palette's root screen. <kbd>esc</kbd> takes
you back one screen at a time.

## Moving around

| Key                           | Does                                                  |
| ----------------------------- | ----------------------------------------------------- |
| <kbd>return</kbd>             | The main action for the selection                     |
| <kbd>⌘</kbd><kbd>return</kbd> | The second action, usually Show in Finder or Copy     |
| <kbd>⌘</kbd><kbd>K</kbd>      | Open the Actions menu for the selection               |
| <kbd>↑</kbd> <kbd>↓</kbd>     | Move the selection                                    |
| <kbd>tab</kbd>                | Move between the launcher, Quick AI and the clipboard |
| <kbd>esc</kbd>                | Clear the search, then go back a screen, then close   |
| <kbd>⌘</kbd><kbd>esc</kbd>    | Go back to the root search from any screen            |
| <kbd>delete</kbd>             | In an empty search field, go back one screen          |
| <kbd>⌘</kbd><kbd>,</kbd>      | Open Settings                                         |
| <kbd>⌘</kbd><kbd>W</kbd>      | Close the window                                      |

<kbd>⌘</kbd><kbd>K</kbd> is the best way to learn the app. Every screen lists all of its actions
there, with shortcuts beside actions that have them. Type in the menu to filter its actions;
<kbd>esc</kbd> clears the menu search first, then closes the menu. The full list is in
[Keyboard shortcuts](/docs/reference/shortcuts).

Every screen except the launcher has a back arrow in the top-left corner. Hover over it to see
whether clicking goes back a step or closes the window.

<kbd>⌘</kbd><kbd>esc</kbd> needs the [Accessibility permission](/docs/permissions), because macOS
uses that shortcut itself unless Tinycast intercepts it first.

### Emacs chords

These work anywhere in the palette:

| Chord                    | Same as      |
| ------------------------ | ------------ |
| <kbd>⌃</kbd><kbd>N</kbd> | <kbd>↓</kbd> |
| <kbd>⌃</kbd><kbd>P</kbd> | <kbd>↑</kbd> |
| <kbd>⌃</kbd><kbd>F</kbd> | <kbd>→</kbd> |
| <kbd>⌃</kbd><kbd>B</kbd> | <kbd>←</kbd> |

On the [emoji grid](/docs/features/emoji), all four move the selection. Everywhere else,
<kbd>⌃</kbd><kbd>F</kbd> and <kbd>⌃</kbd><kbd>B</kbd> move the text cursor, which is what you
usually want in a search field. In the collapsed compact bar, they select Search or a shortcut.
Chords with an extra modifier, like
<kbd>⌃</kbd><kbd>⇧</kbd><kbd>Q</kbd>, are ignored.

Letter shortcuts use your ASCII keyboard layout, so a Japanese, Russian or other non-Latin input
source keeps them working. ASCII layouts such as Dvorak keep their own letter positions, including
the Command positions of Dvorak–QWERTY ⌘. While an input method is composing text, its candidate
selection keys keep their normal behavior.

## Tab moves between three screens

<kbd>tab</kbd> cycles through three screens: **launcher → Quick AI → clipboard → launcher**.

- From the launcher, <kbd>tab</kbd> sends whatever you typed to [Quick AI](/docs/ai) as a question.
  When this will happen, the header shows a **Quick AI** hint next to a <kbd>tab</kbd> key.
- From the clipboard, your search text carries over to the launcher.
- <kbd>esc</kbd> goes back through the screens in reverse.

Quick AI is skipped while [AI](/docs/ai) is off, and the clipboard is skipped while
[clipboard history](/docs/features/clipboard) is off.

Other screens, like Calculator History or Search Quicklinks, aren't part of the cycle. On screens
that don't use <kbd>tab</kbd> themselves, it returns to the launcher with your search text. Rooms
uses it to try layouts, and forms use it to move between fields.

There's one exception: when the selected row takes arguments, like a
[quicklink](/docs/launcher/quicklinks), a [custom command](/docs/launcher/commands#arguments) or an
[extension command](/docs/extensions), <kbd>tab</kbd> moves through its fields first.

## How screens stack

If you open a screen by typing its name in the launcher, it opens on top of the launcher, and
<kbd>esc</kbd> takes you back to your search.

If you open a screen with its own global shortcut while the palette is hidden, it opens by itself
with nothing behind it. If the palette is already visible, the new screen opens over the current
one. Press its shortcut again to close it;
Switch Windows uses repeated presses to move the selection.

**Settings → General → Escape Key Behavior** sets what <kbd>esc</kbd> does when the search is empty:

- **Navigate back or close window** (default): go back a screen, and close only at the root.
- **Close window and pop to root**: close right away, and start at the launcher next time.

In both cases, the first press clears any text you typed.

In compact mode, <kbd>esc</kbd> in the expanded launcher clears your text, then collapses the
palette, then closes it. This happens with either setting.

## Where it opens

Both placement settings are in **Settings → General → Appearance**.

**Follow the cursor across displays** (on by default) opens the palette on the display your pointer
is on. Turn it off to always use the display with the menu bar.

**Drag to move the launcher** (off by default) lets you move the panel. Drag the thin strip above
the search field, the empty space in the header, or the search field itself while it's empty.

While you drag, dotted guides show the default position and light up when you're close enough to
snap to it. Release there and the palette snaps back. Release anywhere else and Tinycast remembers
that position, even after a restart.

Tinycast forgets a saved position only when no display can show it anymore, for example after you
unplug a monitor. Positions aren't included in backups, since they don't carry over between Macs.

## Appearance

**Settings → General → Appearance** has these settings:

| Setting         | Options                  | Default     |
| --------------- | ------------------------ | ----------- |
| Appearance      | System · Light · Dark    | **System**  |
| Show animations | On · Off                 | **On**      |
| Interface size  | Default · Large · Larger | **Default** |
| Window mode     | Compact · Expanded       | **Compact** |

**Appearance.** System follows macOS whenever it changes. Light uses the same design with inverted
colors, and the layout, type and animations stay the same.

**Show animations.** Turn it off and every Tinycast window opens, closes and changes at once, with no
motion.

**Interface size** makes the palette and its floating windows 10% or 20% larger. The Settings window
stays the same size.

**Window mode.** **Compact** opens the launcher as a slim search bar that expands into the full list
as you type. In the slim bar, <kbd>←</kbd> and <kbd>→</kbd> select Search or a shortcut, stopping at
either end. <kbd>↓</kbd> on Search expands the list and selects its first row; on a shortcut it
opens that item. <kbd>return</kbd> opens a selected shortcut. Typing from any shortcut starts a
search. **Expanded** always shows the full list.

**Settings → General → Compact Shortcuts** appears when Compact is selected. Add, change, remove
and reorder up to four shortcuts, or remove them all for a search-only bar. The defaults are Clipboard
History, Emoji & Symbols, Search Files and Search Quicklinks. You can also choose Search Snippets,
Show Notes, My Schedule and Quick AI. Show Notes opens the Notes window. A disabled feature's shortcut
stays configured and marked Off in Settings, then reappears in its place when enabled again.

The [Toggle System Appearance](/docs/launcher/system-actions) action changes the appearance of
_macOS itself_. Tinycast follows it only while its own Appearance is set to System.

## Input source

**Settings → General → Auto-switch input source** picks a keyboard layout to use while the palette
is open.

This helps if you type Japanese or Chinese most of the day but your app names use Latin letters.
Tinycast switches layouts when the palette opens and switches back when it closes. If you changed
the layout yourself while the palette was open, Tinycast keeps your choice.

## Pop to root

**Settings → General → Pop to Root Search** sets how long after the window closes Tinycast returns
to the launcher: **Immediately** (default), or after 5, 15, 30, 60 or 90 seconds.

Use a longer delay if you often close the palette and then come back to the same screen.

AI Chat has its own setting for reopening a conversation. See
[AI Chat](/docs/ai#coming-back-to-a-chat).

## The menu bar

The Tinycast menu bar icon has **Open Tinycast**, **Clipboard History** (while clipboard history is
on), **Check for Updates…**, **Support Tinycast…**, **Settings…** and **Quit Tinycast**.

**Settings → General → Show in menu bar** hides the icon. Your shortcuts still work without it.
