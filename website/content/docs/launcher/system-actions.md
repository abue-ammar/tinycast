---
title: System actions
description: 32 built-in actions for your Mac, like lock, sleep, volume, microphone mute, Bluetooth and the Trash.
---

System actions control your Mac itself, like locking the screen or emptying the Trash. You can search
for each one, and each one can have a global shortcut.

They have their own **System Actions** section in the launcher and their own pane in
**Settings → System Actions**.

## The full list

**Session** · Lock Screen · Sleep · Sleep Displays · Restart · Shut Down · Log Out ·
Show Screen Saver

**Media** · Play / Pause · Next Track · Previous Track

**Volume** · Toggle Mute · Turn Volume Up · Turn Volume Down · Set Volume… ·
Set Volume to 0% · 25% · 50% · 75% · 100%

**Desktop** · Show Desktop · Toggle System Appearance · Toggle Stage Manager ·
Hide All Apps Except Frontmost · Unhide All Hidden Apps · Quit All Applications ·
Dismiss Notifications

**Files** · Open Trash · Empty Trash · Eject All Disks · Toggle Hidden Files

**Hardware** · Toggle Bluetooth

**Microphone** · Toggle Microphone Mute

## Confirmation

Five actions ask for confirmation first, because running them by accident would be costly:

Restart · Shut Down · Log Out · Empty Trash · Quit All Applications

<kbd>return</kbd> runs the action and <kbd>esc</kbd> cancels. Each dialog shows the action's icon,
so you can see what you're about to do. **Quit All Applications** also tells you how many apps it
will quit.

**Empty Trash follows your Finder setting.** It only asks while **Show warning before emptying the
Trash** is on in Finder ▸ Settings ▸ Advanced. If you turn that off, Empty Trash runs without a
dialog.

**The same confirmation appears when you use a shortcut.** You can't skip it, and holding down a
shortcut never opens more than one dialog.

## What you see afterward

Actions without a visible effect show a short message with the result, like `Trash Emptied`,
`Hidden Files Shown`, `Dark Appearance`, `Bluetooth Off` or `3 Disks Ejected`.

A green check means something changed. A plain dot means there was nothing to do. For example,
`Trash Is Already Empty` isn't an error, and neither are similar messages from Eject All Disks,
Dismiss Notifications and Unhide All Hidden Apps.

## A few details

**Volume.** Turn Volume Up and Turn Volume Down move in **5% steps**: from 37%, up goes to 40% and
down goes to 35%. Tinycast shows its own volume indicator, because macOS only shows one for the
hardware media keys. It shows the level as a number, shows `Muted` instead of `0%`, and fades out
after 1.6 seconds.

**Eject All Disks** ejects external and removable drives, including a hard drive connected through a
dock. It never ejects internal or network volumes.

**Toggle Microphone Mute** changes the default input device's own mute setting. If your microphone
doesn't support software mute, or its mute control is managed externally, Tinycast explains why it
couldn't change it.

When you run **Hide All Apps Except Frontmost** or **Quit All Applications** from a shortcut with the
palette closed, they act on the app that's actually in front. Quit All Applications leaves Finder and
Tinycast running and asks apps to quit normally, so apps with unsaved work still ask you to save.

**Toggle System Appearance** changes the appearance of **macOS itself**, not only Tinycast. Tinycast
follows the change only while its own [theme](/docs/palette#appearance) is set to System.

## Permissions

Some actions need Automation, Accessibility or Bluetooth access. Tinycast asks the first time you run
an action that needs it, never in advance. If you decline, you see a message with a link to the right
System Settings pane, so the action never fails silently.

## Settings

**Settings → System Actions** has **Enable System Actions** at the top and a row for each action,
with a launcher checkbox, a shortcut recorder and an alias field. Use the filter field at the top to
find an action among the 32 rows.

Turning off **Enable System Actions** removes every action from search and turns off their
shortcuts. Clearing a single row's checkbox only hides that action from search, which is the same as
pressing <kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> on it in the launcher.
