---
title: Hotkeys
description: Recording global shortcuts, modifier keys on their own, and the Hyper key.
---

**Tinycast doesn't come with any shortcuts.** You record every global shortcut yourself.

## What can have a shortcut

- The palette itself (**Show Launcher**, in Settings → General)
- Every built-in command, except Open in Browser, Run Shell Command and Quit Tinycast. See
  [Commands](/docs/launcher/commands).
- Every app and every System Settings pane
- Every quicklink, snippet, custom command, custom Quick Action, Apple Shortcut and extension command
- All 32 [system actions](/docs/launcher/system-actions)
- All 35 [window commands](/docs/features/window-management), every
  [custom size](/docs/features/window-management#custom-sizes), every
  [window layout](/docs/features/window-layouts) and every [room](/docs/features/rooms)
- [Dictation](/docs/features/dictation), in Settings → Dictation

You record each shortcut on the item's row in its Settings pane, and it appears as keycaps on the
item's launcher row.

Most commands that open a screen work as toggles: press the shortcut once to open and again to
close. [Switch Windows](/docs/features/navigation#switch-windows) uses repeated presses to cycle
through windows instead.

## Recording one

The recorder isn't a regular text field. Click it, then press the keys you want.

A small bubble above the field shows a prompt, then the modifiers you're holding. If the shortcut is
already used by another Tinycast action, it rejects the new binding and shows a warning naming
that action. Your existing shortcut stays saved.

A key combination needs <kbd>⌘</kbd>, <kbd>⌥</kbd>, <kbd>⌃</kbd> or Globe (🌐︎). Only the function
keys, F1 to F20, work without one. Press <kbd>esc</kbd> to stop recording, or <kbd>delete</kbd> to
clear the shortcut.

Recording a shortcut **doesn't need any permissions**. Only _using_ some kinds of shortcuts does.

## Modifier keys on their own

Instead of a key combination, a shortcut can be a single tap or a double tap of one <kbd>⌃</kbd>,
<kbd>⌥</kbd>, <kbd>⇧</kbd>, <kbd>⌘</kbd> or Globe (🌐︎) key. To record one, tap the key once or twice.
The recorder waits a moment after the first tap in case a second one follows.

**Tinycast remembers which side you pressed.** A shortcut on Right <kbd>⌘</kbd> doesn't run when you
tap Left <kbd>⌘</kbd>. A single-tap shortcut shows a small L or R on its keycap. A double-tap shortcut
shows only the two modifier symbols, but it keeps its side.

The rules:

- A **tap** is a press of exactly one modifier key, with no other key held and no click, released
  within **250 ms**.
- A **double tap** is a second tap of the same key that starts within **300 ms** of releasing the
  first.
- **The shortcut runs when you release the key, not when you press it.** The key is already up when
  the action runs, and holding the key down does nothing.
- If one key has both a single-tap and a double-tap shortcut, the single tap waits until the time for
  a second tap is over.

<kbd>⇧</kbd> works here, even though <kbd>⇧</kbd> plus a letter can't be a shortcut. Caps Lock can't
be used this way; use the Hyper key for that. Having Caps Lock _on_ doesn't interfere.

macOS can run its own action when you press Globe. If that gets in the way, set **Press 🌐︎ key to**
to **Do Nothing** in **System Settings → Keyboard**.

This needs [Accessibility](/docs/permissions), but **Tinycast never asks for it on its own**. The
shortcut is saved anyway, the recorder shows a warning that opens System Settings, and the shortcut
starts working as soon as you grant access.

For Dictation in **Hold to talk** mode, a single modifier starts listening after 250 ms and
releasing it finishes. Double-tap bindings use toggle mode. See [Dictation](/docs/features/dictation).

Tinycast only listens for modifier taps **while at least one shortcut uses one**, so if you don't
use them, they cost nothing.

## Hyper key

**Settings → General → Hyper Key** turns one physical key into <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd>,
or into <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd> with **Include Shift** on.

You can choose **Caps Lock**, or the **Left** or **Right** side of **Control**, **Shift**,
**Option** or **Command**.

Function keys aren't available. Their media functions run before Tinycast sees the key press, and
catching them earlier would need Input Monitoring, which Tinycast never asks for.

Shortcuts you already use with those modifiers work with the Hyper key right away.

### The ✦ symbol

**Any shortcut that includes all the Hyper modifiers is shown as a single ✦.** For example,
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> is shown as `✦G`, or `✦⇧G` if it uses an extra
modifier.

This only changes how the shortcut is displayed. With no Hyper key set,
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> is shown as it is.

### Include Shift

Changing this setting **updates every saved shortcut**, so none of them stop working. If an update
would conflict with another shortcut, Tinycast skips it and that shortcut keeps its original keys.

The option is dimmed while Hyper Key is set to None. Changing the physical Hyper key resets
**Quick Press** to **Does Nothing**.

### Quick Press

**Settings → General → Quick Press** sets what happens when you press Caps Lock by itself while it's
your Hyper key: **Does Nothing** (default), **Trigger Caps Lock**, or **Trigger Escape**.

Many people who use Caps Lock as their Hyper key choose Escape.

### Caps Lock details

While Caps Lock is your Hyper key, it's remapped at the hardware level on **every keyboard**,
including one you plug in later. Any remapping another app made for a different key is kept.

The remapping is removed when you choose a different key or quit Tinycast, and it never persists
after a restart. If Tinycast is force quit or crashes, it stays until Tinycast opens again, which
removes it. It's also paused while your Mac sleeps, while the screen is locked, so Caps Lock
works in the login password field, and while another user account is active.

If a keyboard ever loses the remapping, one press there acts as plain Caps Lock. Tinycast then remaps
that keyboard again and turns Caps Lock back off.

The Hyper key needs Accessibility. Tinycast asks for it when you choose a key, keeps checking, and
starts working as soon as access is granted.

### Status and diagnostics

The **Status** row under the key shows a dot: green while the Hyper key works. Click **Diagnostics…**
to see what's running, which keyboards are remapped, and anything that conflicts. **Restart Hyper
Key** sets everything up again. If another app takes over a Caps Lock remapping, Status shows
**Taken Over** and identifies the affected keyboards. Tinycast leaves that app's mapping in place.

### Conflicts

- **Hyperkey** or **Superkey** running: they have their own Hyper key, so Tinycast's stays off and
  says so. It starts again by itself when you quit them.
- **BetterTouchTool** running: listed in Diagnostics as a possible conflict, nothing more.
- **Karabiner-Elements** remapping the same key: shown in Diagnostics.
- **System Settings → Keyboard → Modifier Keys** remapping Caps Lock: this blocks the Hyper key.
  Diagnostics names the keyboard and links to the setting.

### Secure Input

Password fields, password managers and some terminals turn on macOS **Secure Input**, which hides
every key press from apps like Tinycast. While it's on, the Hyper key can't work, and pressing it
shows a message saying why. Diagnostics names the app most likely holding Secure Input.

With Caps Lock as your Hyper key, turn on **Secure Input Compatibility** to keep **Tinycast's own**
Hyper shortcuts working there. Caps Lock then acts as **Right Control**, so while it's on, the Right
Control key also works as Hyper and its own shortcuts are reserved. Inside Secure Input, **Right
Control** plus a shortcut's key runs that Hyper shortcut. Left Control never triggers Hyper; existing
Tinycast Control shortcuts still work with Left Control. The Control combinations used by Hyper are
reserved while Secure Input lasts. Other apps' Hyper shortcuts still don't work there.

## Dictation key (🎤)

Press 🎤 (F5) while recording any shortcut to use it in Tinycast, push-to-talk included. While a
shortcut uses it, macOS Dictation doesn't; remove the shortcut to give it back. With standard function
keys on, press fn+🎤. Tinycast sends it as F20, so other apps' F20 shortcuts fire too.

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
