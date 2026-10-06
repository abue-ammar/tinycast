---
title: Hotkeys
description: Recording global shortcuts, double-tap modifiers, and the Hyper key.
---

**Tinycast doesn't come with any shortcuts.** You record every global shortcut yourself.

## What can have a shortcut

- The palette itself (**App Launcher**, in Settings → General)
- Every built-in command, except Open in Browser, Run Shell Command and Quit Tinycast. See
  [Commands](/docs/launcher/commands).
- Every app and every System Settings pane
- Every quicklink, snippet, custom command, custom Quick Action and extension command
- All 31 [system actions](/docs/launcher/system-actions)
- All 35 [window commands](/docs/features/window-management), every
  [window layout](/docs/features/window-layouts) and every [room](/docs/features/rooms)

You record each shortcut on the item's row in its Settings pane, and it appears as keycaps on the
item's launcher row.

A command that opens a screen works as a toggle. Press its shortcut once to open the screen, and
again to close it.

## Recording one

The recorder isn't a regular text field. Click it, then press the keys you want.

A small bubble above the field shows a prompt, then the modifiers you're holding. If the shortcut is
already in use, it shows a warning that names what uses it.

Recording a shortcut **doesn't need any permissions**. Only _using_ some kinds of shortcuts does.

## Editing individual keys

A recorded key combination stays open for editing. Click a modifier cap to cycle **Any Side → Left →
Right → Any Side**. Its glyph shows no prefix, `L`, or `R`; holding both sides does not count as one side.

Click a printable key to switch **Pos / Char**. **Pos** uses the same physical position when you change
keyboard layouts. **Char** follows the saved shortcut character in your ASCII-capable layout, including
its Command layout when <kbd>⌘</kbd> is held. This does not match IME text. Space, Return, arrows and
function keys stay physical-only. The bubble stays the same size; hover over a key or the info icon
for an explanation. Press Escape or click outside to finish.

Choosing a modifier side or **Char** needs [Accessibility](/docs/permissions) to run. The shortcut is
saved without prompting, and the recorder's warning opens System Settings if access is missing.
Ordinary any-side **Pos** shortcuts need no permission. In `settings.json`, Char is written with
its original physical key code, such as `cmd+key-40:character:k`, so switching back to Pos keeps the
same key after a layout change.

## Double-tap modifiers

Instead of a key combination, a shortcut can be a double tap of a single <kbd>⌃</kbd>,
<kbd>⌥</kbd>, <kbd>⇧</kbd> or <kbd>⌘</kbd> key.

The rules:

- A **tap** is a press of exactly one of those four keys, with no other key held and no click,
  released within **250 ms**.
- A **double tap** is a second tap of the same key that starts within **300 ms** of releasing the
  first.
- **The shortcut runs when you release the key the second time, not when you press it.** The key is
  already up when the action runs, and double-tapping and holding does nothing.

<kbd>⇧</kbd> works as a double tap, even though it can't be a regular shortcut on its own. Caps Lock
can't be used this way; use the Hyper key for that. Having Caps Lock _on_ doesn't interfere.

This needs [Accessibility](/docs/permissions), but **Tinycast never asks for it on its own**. The
shortcut is saved anyway, the recorder shows a warning that opens System Settings, and the shortcut
starts working as soon as you grant access.

Tinycast only listens for double taps **while at least one shortcut uses one**, so if you don't use
them, they cost nothing.

## Hyper key

**Settings → General → Hyper Key** turns one physical key into <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd>,
or into <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd> with **Include Shift** on.

You can choose **Caps Lock**, **Right Control**, **Right Shift**, **Right Option** or
**Right Command**.

Function keys aren't available, because their media functions run before Tinycast sees the key
press. Turning F1 into a Hyper key would still dim your screen.

Shortcuts you already use with those modifiers work with the Hyper key right away.

### The ✦ symbol

**Any shortcut that includes all the Hyper modifiers, without side restrictions, is shown as a single ✦.** For example,
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> is shown as `✦G`, or `✦⇧G` if it uses an extra
modifier.

This only changes how the shortcut is displayed. With no Hyper key set,
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> is shown as it is.

### Include Shift

Changing this setting **updates every saved shortcut**, so none of them stop working. If an update
would conflict with another shortcut, Tinycast skips it and that shortcut keeps its original keys.

The option is dimmed while Hyper Key is set to None.

### Quick Press

**Settings → General → Quick Press** sets what happens when you press the Hyper key by itself:
**Does Nothing** (default), the key's original function, or **Trigger Escape**.

Many people who use Caps Lock as their Hyper key choose Escape.

### Caps Lock details

While Caps Lock is your Hyper key, it's remapped at the hardware level. The remapping is removed when
you choose a different key or quit Tinycast, and it never persists after a restart.

In the brief moment before the remapping takes effect, the Caps Lock light can still turn on. That's
the hardware, and Tinycast can't prevent it.

The Hyper key needs Accessibility, and Tinycast never asks for it on its own. Tinycast keeps checking,
starts working as soon as access is granted, notices if access is removed, and releases a key that
seems stuck. When you switch to another user account, it pauses until you come back.

## Hiding versus turning off

**Hiding an item doesn't turn off its shortcut.** Clearing a row's checkbox, or pressing
<kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> in the launcher, only changes what search shows.

**A section's switch turns off its shortcuts.** **Enable Applications**, **Enable System Settings**,
**Enable System Actions** and **Enable Commands** each turn off every shortcut in their pane.

**Turning off a feature turns off its shortcuts.** File Search, Notes, AI, Quick Actions,
Navigation, Calendar, window commands, quicklinks, snippets, custom commands and extensions all check
their switch before doing anything. Turn the feature back on and its shortcuts work again.

A [system action's confirmation](/docs/launcher/system-actions#confirmation) appears when you use its
shortcut, the same as in the palette.

## Keeping them

Shortcuts are included in [backups](/docs/reference/backup), except for custom Quick Actions and
snippets.

Shortcuts for items you deleted while Tinycast wasn't running are removed the next time it starts.
