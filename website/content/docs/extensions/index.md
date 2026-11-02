---
title: Extensions
description: Tinycast runs Raycast extensions natively, rendered with SwiftUI.
---

Tinycast runs Raycast extensions: the same `package.json` and the same built command files, rendered
natively in the palette.

Tinycast doesn't run Electron, a browser or Node.js. Extensions run in JavaScriptCore, which is
already part of macOS, so supporting them adds **nothing to the app's size**.

Turn extensions on in **Settings → Extensions**. They're **off** by default, and Tinycast asks for
confirmation when you turn them on, because extensions are code written by other people.

| Setting           | Default |
| ----------------- | ------- |
| Enable extensions | **Off** |
| Show in launcher  | On      |

The switch is never included in [backups](/docs/reference/backup), so importing a backup can't turn
extensions on.

While extensions are off, Tinycast doesn't scan any folders, nothing appears in the launcher, and no
JavaScript engine runs.

## Memory use

**Only one foreground command runs at a time, and it keeps a JavaScript engine in memory until you
leave it.** Menu bar commands use their own short-lived engine, which is released when a refresh
finishes or the menu closes.

Starting a command stops the previous one and discards its engine, so nothing carries over between
runs. Once warmed up, a command starts in about 7 ms.

The only exception is [background refresh](/docs/extensions/customising#background-refresh), which
briefly runs a command on a schedule, and only if you turn it on.

## Menu bar commands

Run a menu bar command once, or turn on **Show in menu bar** in its
[settings](/docs/extensions/customising), to turn it on. Its icon and title then stay in the menu
bar, and the interval in its manifest controls how often it refreshes in the background. Opening the
menu reloads the command, and closing it releases the engine once any running action finishes. Saved
items come back after a restart without running the extension.

To stop a menu bar command, turn off **Show in menu bar** in the command's configuration. Installing
an extension doesn't turn on its menu bar commands.

## Where to go next

- [Installing extensions](/docs/extensions/installing): the four ways to install, updates and
  package managers
- [What works](/docs/extensions/compatibility): what's supported, and the known gaps
- [Configuring one](/docs/extensions/customising): preferences, icons, aliases and background
  refresh

## In the launcher

An extension's commands appear in the **Extensions** section. Searching for the extension's name
also finds its commands, so `lucide` finds Lucide's **Search Icons**.

Global shortcuts are assigned to individual **commands**, not to whole extensions. See
[Hotkeys](/docs/reference/hotkeys).

When a command takes arguments, small fields appear after what you typed. <kbd>tab</kbd> moves from
the search field through each field and back, and <kbd>return</kbd> in any of them runs the command.
If a required field is empty, the command doesn't run and the cursor moves to that field.

Every argument is sent, as an empty string if you left it blank. Raycast does the same, and
extensions rely on it.

## Moving around

<kbd>esc</kbd> clears the search field first. When the field is empty, <kbd>esc</kbd> and
<kbd>delete</kbd> go back through the extension's **own** screens, and only leave the command from
its first screen.

Screens keep their state when you go back to them, so you return to where you left off.

An extension's actions appear in the palette's <kbd>⌘</kbd><kbd>K</kbd> menu. <kbd>return</kbd> runs
the first action, and each action's own shortcut works.

## Appearance

A running command keeps the [appearance](/docs/palette#appearance) it started with, and a theme
change applies the next time it opens. Icons and colors made for light and dark mode switch along
with the palette.
