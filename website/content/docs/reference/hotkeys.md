---
title: Hotkeys
description: Recording global shortcuts, double-tap modifiers, and the Hyper key.
---

**Tinycast ships with nothing bound.** Every global shortcut is one you record.

## What can have a shortcut

- The palette itself (**App Launcher**, in Settings → General)
- Every built-in command, except Open in Browser, Run Shell Command and Quit Tinycast. See
  [Commands](/docs/launcher/commands).
- Every app, and every System Settings pane
- Every quicklink, custom command, custom Quick Action and extension command
- All 31 [system actions](/docs/launcher/system-actions)
- All 35 [window commands](/docs/features/window-management), every
  [window layout](/docs/features/window-layouts) and every [room](/docs/features/rooms)

Each shortcut is recorded on the item's row in its Settings pane, and shows as keycaps on its
launcher row.

A command that opens a screen is a toggle. Press its shortcut once to open the screen, and again to
close it.

## Recording one

The recorder is not a normal text field. Click it, then press the keys you want.

A small bubble above the field shows the prompt, then the modifiers you are holding, then a warning if
the shortcut is already taken, naming exactly what uses it.

Recording needs **no permission**. Only _using_ some kinds of shortcut does.

## Double-tap modifiers

Any shortcut can instead be a double tap of one lone <kbd>⌃</kbd>, <kbd>⌥</kbd>, <kbd>⇧</kbd> or
<kbd>⌘</kbd>.

The exact rules:

- A **tap** is a press of exactly one of those four keys, with nothing else held, no other key and no
  click, released within **250 ms**.
- A **double tap** is a second tap of the same key starting within **300 ms** of the first release.
- **It fires when you let go the second time, not when you press.** The key is already up when the
  action runs, and "double-tap and hold" does nothing on purpose.

<kbd>⇧</kbd> works as a double tap, even though <kbd>⇧</kbd> alone cannot be a normal shortcut. Caps
Lock cannot be used this way; that is what the Hyper key is for. Having Caps Lock _on_ does not get in
the way.

This needs [Accessibility](/docs/permissions), and **never asks for it on its own**. The shortcut is
saved anyway, the recorder shows a warning that opens System Settings, and the shortcut starts working
the moment you grant access.

Tinycast only watches for double taps **while at least one shortcut uses one**, so if you never do,
it costs nothing.

## Hyper key

**Settings → General → Hyper Key** turns one physical key into <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd>,
or <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd> with **Include Shift** on.

You can choose **Caps Lock**, **Right Control**, **Right Shift**, **Right Option** or
**Right Command**.

Function keys are not offered. Their media functions fire before Tinycast can see them, so turning F1
into Hyper would still dim your screen.

Shortcuts you already use with those modifiers work with Hyper right away.

### The ✦ symbol

**Any shortcut that includes all the Hyper modifiers shows as a single ✦.** So
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> shows as `✦G`, or `✦⇧G` when an extra modifier is
left over.

This is simply how it is written, not a setting. With no Hyper key set,
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> shows as itself.

### Include Shift

Switching this **updates every saved shortcut**, so nothing breaks. If an update would clash with
another shortcut, that one is skipped and keeps its original keys.

The option is greyed out while Hyper Key is set to None.

### Quick Press

**Settings → General → Quick Press** decides what pressing the Hyper key on its own does:
**Does Nothing** (default), the key's original job, or **Trigger Escape**.

Escape is the favorite choice for Caps Lock users.

### Caps Lock details

While Caps Lock is your Hyper key, it is remapped at the hardware level. The remap is removed when you
pick another key, when Tinycast quits, and it never survives a restart.

In the brief moment before the remap takes hold, the Caps Lock light can still switch. That is the
hardware, not something Tinycast can stop.

Hyper needs Accessibility and never asks for it on its own. Tinycast keeps checking, starts working as
soon as access is granted, notices if access is removed, and clears a key that looks stuck. When you
switch to another user, it pauses until you are back.

## Hidden, switched off, and turned off

**Hiding a row does not turn off its shortcut.** Unticking a row's checkbox, or
<kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> in the launcher, only changes what search shows.

**A section's switch does turn off its shortcuts.** **Enable Applications**, **Enable System
Settings**, **Enable System Actions** and **Enable Commands** each stop every shortcut in their pane.

**Turning a feature off turns off its shortcuts.** File Search, Notes, AI, Quick Actions, Navigation,
Calendar, window commands, quicklinks, custom commands and extensions all check their switch before
doing anything. Turn the feature back on and your shortcuts work again.

A [system action's confirmation](/docs/launcher/system-actions#confirmation) comes up for its shortcut
exactly as it does in the palette.

## Keeping them

Shortcuts are included in [backups](/docs/reference/backup), except for custom Quick Actions.

Shortcuts for things you deleted while Tinycast was not running are cleaned up the next time it
starts.
