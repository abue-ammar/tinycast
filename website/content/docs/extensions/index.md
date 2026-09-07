---
title: Extensions
description: Tinycast runs Raycast extensions natively, drawn with SwiftUI.
---

Tinycast runs Raycast extensions: the same `package.json` and the same built command files, drawn
natively in the palette.

There is no Electron, no browser and no Node.js running inside Tinycast. Extensions run in
JavaScriptCore, which already ships with macOS, so this adds **nothing to the app's size**.

**Settings → Extensions** holds the switch. It ships **off**, and turning it on asks first, because
it means agreeing to run code someone else wrote.

| Setting           | Default |
| ----------------- | ------- |
| Enable extensions | **Off** |
| Show in launcher  | On      |

The switch is never included in [backups](/docs/reference/backup), so importing a file cannot turn it
on.

While it is off, no folder is scanned, nothing shows in the launcher and no JavaScript engine exists.

## The one ongoing cost

**One foreground command runs at a time, and it keeps a JavaScript engine in memory until you leave
it.** Menu-bar commands use their own short-lived engine, released once a refresh finishes or the
menu closes.

Starting a command stops the one before and throws its engine away, so nothing carries over between
runs. A fresh start takes about 7 ms once warm.

The one exception is [background refresh](/docs/extensions/customising#background-refresh), which
briefly runs a command on a schedule, and only if you turn it on.

## Menu bar commands

Run a menu-bar command once to activate it. Its icon and title stay in the menu bar, and its manifest
interval controls background refresh. Opening the menu reloads the command; closing it releases the
engine after any action finishes. Saved items return after restart without executing the extension.

Use **Remove from Menu Bar** in the menu or **Show in menu bar** in the command's configuration to
stop it. Installing an extension does not activate its menu-bar commands.

## Where to go next

- [Installing extensions](/docs/extensions/installing): the three ways in, registries and package
  managers
- [What works](/docs/extensions/compatibility): what is supported, and the known gaps
- [Configuring one](/docs/extensions/customising): preferences, icons, aliases and background
  refresh

## In the launcher

An extension's commands show in the **Extensions** section. The extension's own name also finds its
commands, so `lucide` finds Lucide's **Search Icons**.

A global shortcut belongs to a **command**, not to a whole extension. See
[Hotkeys](/docs/reference/hotkeys).

A command that takes arguments shows small fields right after what you typed. <kbd>tab</kbd> moves from
the search field through each field and back, and <kbd>return</kbd> from any of them runs the command. An
empty required field stops the launch and puts the cursor there.

Every argument is sent, as an empty string if you left it blank. Raycast does the same, and
extensions count on it.

## Moving around

<kbd>esc</kbd> clears the search field first. On an empty field, <kbd>esc</kbd> and <kbd>delete</kbd> go
back through the extension's **own** screens, and only leave the command once you are at its first
screen.

Screens you go back to keep their state, so you land where you left off.

An extension's actions become the palette's <kbd>⌘</kbd><kbd>K</kbd> menu. The first action is the
one <kbd>return</kbd> runs, and each action's own shortcut works.

## Appearance

A running command keeps the [appearance](/docs/palette#appearance) it started with. A theme change
reaches it the next time it opens. Icons and colors made for light and dark switch as the palette
does.
