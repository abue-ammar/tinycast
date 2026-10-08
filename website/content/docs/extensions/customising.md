---
title: Configuring an extension
description: Preferences, launcher icons, aliases and background refresh for an extension.
---

Open **Settings → Extensions**, find the extension in the installed list, and click **Configure**.
In the launcher, <kbd>⌘</kbd><kbd>K</kbd> → **Configure Extension** on any of its commands opens the
same screen.

## Preferences

Any settings the extension defines appear as native controls: checkbox, dropdown, text field,
password field, file picker, folder picker or app picker.

They're saved separately for each extension in Tinycast's own folder and removed when you uninstall
the extension.

## Launcher icon

Replace an extension's own artwork with an **SF Symbol on a colored tile**, in one of 18 colors, or
choose **Use Original** to switch back.

The icon applies to **every command** in the extension.

The symbol picker starts with about 85 suggestions, but **search covers the full catalog** of about
6,500 symbols. It also understands Apple's search keywords, so "coffee" finds `cup.and.saucer`.

Symbols that Apple reserves for its own products, like iCloud, iPhone and AirPlay, aren't offered.

Icon choices **are** included in [backups](/docs/reference/backup).

## Command alias

Each command has an alias field next to its shortcut recorder. If you enter `si`, that command comes
first when you search for `si`, the same as an [app alias](/docs/launcher/aliases).

The field is dimmed when the command is hidden from launcher search.

## Background refresh

A `no-view` command that defines an `interval`, like `1m` or `12h`, can run in the background on that
schedule. Any subtitle it sets appears next to its name in the launcher. For example, Coffee's
**Caffeinate Status** updates every minute.

Background refresh is **off** for each command until you run the command yourself once, or turn it on
in the command's settings. The settings also show when it last refreshed and any error.

In the launcher, a small dot on the row means refresh is on, and a warning appears if the last run
failed. <kbd>⌘</kbd><kbd>K</kbd> offers **Enable Background Refresh** or
**Disable Background Refresh**, and **Refresh Now**.

To keep background refresh light:

- The shortest interval is one minute. After a failure, the wait gets longer each time, up to a day.
- A background run never interrupts a command you're using.
- A background run never shows toasts, dialogs or windows.

## Uninstalling

Uninstalling removes the extension and everything connected to it: storage, cache, preferences, its
support folder, the icon choice, command shortcuts, favorites, hidden items,
aliases and learned ranking.

<kbd>⌘</kbd><kbd>K</kbd> → **Uninstall Extension** in the launcher does the same.
