---
title: Hotkeys
description: Recording global shortcuts, double-tap modifiers, and the Hyper key.
---

**Tinycast ships with nothing bound.** Every shortcut is one you record.

## What can take a shortcut

- The palette itself (**App Launcher**)
- The built-in commands: Search Files, Clipboard History, Search Emoji & Symbols, Open Camera,
  Show Notes, Create Note, Search Notes
- Every application, and every System Settings pane
- Every quicklink, custom command and extension command
- All 31 [system actions](/docs/launcher/system-actions)
- All 30 [window commands](/docs/features/window-management)

A built-in command's shortcut appears in two panes — Settings → Commands and its own feature pane —
but it is **one binding, not two settings**.

## Recording one

The recorder is not a focusable control. Click it, then press the combination you want.

A callout above the field shows the prompt, then your held modifiers live, then a conflict message
if the chord is taken — naming the action that owns it, exactly as that action's own row does.

Recording needs **no permission and no event tap**. Only _using_ certain kinds of binding does.

## Double-tap modifiers

Any action can be bound to a double-tapped lone <kbd>⌃</kbd>, <kbd>⌥</kbd>, <kbd>⇧</kbd> or
<kbd>⌘</kbd>.

The exact rules:

- A **tap** is a press from no modifiers held, exactly one of the four, no <kbd>fn</kbd>, no other
  key and no mouse click, released within **250 ms**.
- A **double-tap** is a second tap of the same modifier starting within **300 ms** of the first
  release.
- **It fires on the second release, not the second press** — so the modifier is already up when the
  action runs, and "double-tap and hold" is deliberately a non-event.

<kbd>⇧</kbd> is bindable this way even though a bare <kbd>⇧</kbd> combo is rejected. Caps Lock is not
eligible — that is what the Hyper key is for. Caps Lock being _on_ does not disqualify taps.

This needs [Accessibility](/docs/permissions), and **never prompts for it**. The binding records
regardless, the recorder shows an inline warning that opens System Settings, and the listener
installs the moment the grant lands.

The event tap is installed **only while something is bound to a double-tap**, so if you never use
one, you pay nothing.

## Hyper key

**Settings → General → Hyper Key** turns one physical key into <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd>,
or <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd> with **Include Shift** on.

Candidates: **Caps Lock**, **Right Control**, **Right Shift**, **Right Option**, **Right Command**.

Function keys are deliberately not offered — the top-row media functions fire below the level this
works at, so binding F1 would still dim the display.

Existing combo hotkeys fire from Hyper + key with no extra registration.

### The ✦ notation

**Any combo whose modifiers are a superset of the Hyper chord renders as a single ✦.** So
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> shows as `✦G`, and `✦⇧G` when a modifier survives.

This is notation, not a preference — there is no toggle. With no Hyper key configured, a literal
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> renders as itself.

### Include Shift

Flipping this **re-points every stored combo**, so nothing breaks. A re-point that would collide with
another action's chord is skipped, and that row keeps its literal keycaps.

The row is disabled while Hyper Key is None.

### Quick Press

**Settings → General → Quick Press** decides what a Hyper key press with no other key does:
**Does Nothing** (default), the original key, or **Trigger Escape**.

Escape is the popular choice for Caps Lock users.

### Caps Lock specifics

While Caps Lock serves as Hyper it is remapped at the hardware level. That is cleared when you unbind
it and when Tinycast quits, and it never survives a reboot.

During the brief moment before the remap takes hold, the Caps Lock LED can still toggle. That is
hardware behaviour, not something Tinycast can prevent.

Hyper needs Accessibility and never prompts. A watchdog retries installation until the grant lands,
notices revocation, revives a tap macOS has disabled, and clears a stuck key. On fast user switching
it stops until the session is active again.

## Enabled, hidden and disabled

**Hiding a launcher row does not disable its shortcut.** Hiding changes what search shows.

**Disabling a feature does disable its shortcuts.** File Search, Notes, window commands, quicklinks,
custom commands and system actions all re-check their feature switch before running, so a registered
shortcut for a disabled feature does nothing.

A [system action's confirmation](/docs/launcher/system-actions#confirmation) applies to its hotkey
exactly as it does in the palette.

## Lifecycle

Bindings are carried in [settings backups](/docs/reference/backup), but only export → import within
one build is guaranteed to round-trip.

Bindings for items deleted while Tinycast was not running are pruned at launch.
