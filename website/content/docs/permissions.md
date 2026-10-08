---
title: Permissions
description: What Tinycast asks for, why it needs it, and when it asks.
---

Tinycast asks for a permission **only when you use a feature that needs it**, never at launch. The
launcher, calculator, emoji picker and app search all work without any permissions.

**Settings → Permissions** shows the status of Accessibility and Calendars, and opens the right
System Settings pane for you.

## Accessibility

macOS describes this permission as "control your computer". Tinycast uses it to read from and write
to the window you were using before the palette opened.

Grant it in **System Settings → Privacy & Security → Accessibility**, or from
**Settings → Permissions**.

### What needs it

| Feature                                                                       | Why                                                    |
| ----------------------------------------------------------------------------- | ------------------------------------------------------ |
| [Clipboard](/docs/features/clipboard) and [emoji](/docs/features/emoji) paste | Puts the item into the app you were using              |
| [Snippets](/docs/features/snippets)                                           | Detects the keyword you type, then inserts the text    |
| [Quick Actions](/docs/ai/quick-actions)                                       | Reads your selected text and replaces it               |
| [Window management](/docs/features/window-management) and layouts             | Reads and sets other apps' window frames               |
| [Navigation](/docs/features/navigation)                                       | Lists open windows and clicks menu bar items           |
| [Hyper key](/docs/reference/hotkeys#hyper-key)                                | Turns one physical key into a modifier chord           |
| Double-tap modifier shortcuts                                                 | Detects the tap pattern                                |
| <kbd>⌘</kbd><kbd>esc</kbd> back to the root search                            | macOS uses this shortcut unless Tinycast intercepts it |
| `getSelectedText` in [extensions](/docs/extensions)                           | Reads the selection from the frontmost app             |

### Snippets and keystroke matching

Snippet keyword expansion is the only feature that reads what you type, so these are the rules it
follows:

- Snippets are **off** by default. Turning them on shows an explanation first, and turning on the
  switch counts as your consent. There's no separate prompt.
- Matching happens **only on your Mac**. Keystrokes are never stored or sent anywhere.
- The typing buffer holds at most 256 characters. It resets when you switch apps, press a shortcut
  with a modifier, turn on Secure Event Input, or stop typing for 15 seconds.
- Tinycast uses a **listen-only** event tap under the Accessibility permission. It doesn't use Input
  Monitoring.
- **Restoring a settings backup can't turn snippets on**, so importing a file someone sent you can
  never enable keystroke listening.

## Calendars

The [Calendar](/docs/features/calendar) feature reads your events to find meeting links.

When you turn it on, Tinycast shows its own explanation first, then the macOS prompt. The feature is
only on once macOS grants access. If you declined earlier, **Settings → Permissions** opens the
System Settings pane where you can change it.

Events are read on your Mac and never leave it.

## Camera

**Open Camera** and the optional camera preview before a meeting ask for camera access the first
time you use them. The camera isn't used before then, and it turns off as soon as the preview closes.

## Automation and Bluetooth

A few actions show their own macOS prompt the first time you run them:

- **Show Info in Finder** in the [uninstaller](/docs/launcher/uninstall), and some
  [system actions](/docs/launcher/system-actions), control other apps through Apple Events, which
  shows the standard Automation prompt.
- **Toggle Bluetooth** shows the Bluetooth prompt.

If you decline, Tinycast tells you and links to the right System Settings pane, so the action never
fails silently.

## Folders

[File Search](/docs/features/file-search) reads the names of files in your search scopes the first
time you type a search. macOS protects **Desktop**, **Documents**, **Downloads** and **iCloud Drive**,
so it asks once whether Tinycast may read each one that's in your scopes. Nothing is asked while File
Search is off, or before you type.

Tinycast only reads names and dates, never what's inside your files, and keeps them in memory only.
If you decline a folder, File Search leaves it out and searches everything else. You can change your
answer in **System Settings → Privacy & Security → Files & Folders**.

## Full Disk Access

Tinycast **checks** whether it has Full Disk Access but **never asks** for it.

The [uninstaller](/docs/launcher/uninstall) checks in the background to work out which files it can
move. Without Full Disk Access, protected folders like `~/Library/Containers`,
`~/Library/Group Containers` and `~/Library/Cookies` appear as locked rows. At worst, you remove
those by hand.

## What Tinycast never needs

- **Full Disk Access for File Search.** Folders it can't read are left out rather than asked for.
- **Screen Recording.** The window switcher reads window titles through Accessibility.
- **Location.** The calculator picks your currency from your Mac's region setting.
- **Input Monitoring.** Snippets listen through Accessibility, as described above.
