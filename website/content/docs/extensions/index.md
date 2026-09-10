---
title: Extensions
description: Tinycast runs Raycast extensions natively, rendered as SwiftUI.
---

Tinycast runs Raycast extensions — the same `package.json` and the same prebuilt command bundles —
rendered natively into the palette.

There is no Electron, no browser and no Node.js at runtime. JavaScriptCore ships with macOS, so this
costs **no extra binary size**.

**Settings → Extensions** holds the feature switch. It ships **off**, and turning it on asks for
confirmation, because enabling it is consent to run third-party code.

| Setting           | Default |
| ----------------- | ------- |
| Enable extensions | **Off** |
| Show in launcher  | On      |

`extensionsEnabled` is deliberately excluded from
[settings backups](/docs/reference/backup), so importing a file cannot switch it on.

While off, no directory is scanned, no launcher row is published and no JavaScript context exists.

## The one standing cost

**Exactly one command runs at a time, and a running command holds a JavaScript engine in memory
until you leave it.** That is the only continuous cost Tinycast has.

Starting a command stops the previous one and discards its context, so no state survives between
runs. A fresh boot takes about 7 ms once warm.

## Where to go next

- [Installing extensions](/docs/extensions/installing) — the three routes, registries and package
  managers
- [What works](/docs/extensions/compatibility) — the supported API surface and the known gaps
- [Configuring one](/docs/extensions/customising) — preferences, icons, aliases and storage

## Shortcuts and arguments

A global shortcut binds to a **command**, not to an extension. See
[Hotkeys](/docs/reference/hotkeys).

A command declaring arguments shows inline fields right after your typed text.
<kbd>⇥</kbd> walks from the search field through each argument and back; <kbd>↵</kbd> from any of
them runs the command. A blank required argument blocks the launch and focuses the field that is
missing.

Every declared argument is sent, as an empty string when unfilled.

## Navigation

<kbd>⎋</kbd> and a bare <kbd>⌫</kbd> pop the extension's **own** navigation stack first, and only
leave the command once it is at its root.

Pushed screens stay mounted, so popping back restores what was there.

An extension's action panel becomes the palette's <kbd>⌘</kbd><kbd>K</kbd> menu. The first action is
the primary <kbd>↵</kbd> action, and an action's own declared shortcut is honoured.

## Appearance

A running command keeps the [appearance](/docs/palette#appearance) it started with; a theme change
reaches it on the next launch. Icons and colors declared per-appearance re-render when the surface
flips.
