---
title: Settings
description: Every setting, its default, and the pane it lives in.
---

Settings opens with <kbd>⌘</kbd><kbd>,</kbd> from the palette, or the **Settings** command. It is a
normal resizable window, and each pane is a standard macOS form.

Sixteen panes in four groups.

## General

### Global Shortcuts

| Setting      | Default  |
| ------------ | -------- |
| App Launcher | **None** |

### Search

| Setting                 |                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------- |
| Learned ranking → Reset | Clears every learned choice. See [learned ranking](/docs/launcher#learned-ranking)  |
| Search Scopes           | Folders indexed for applications. See [search scopes](/docs/launcher#search-scopes) |

### Hyper Key

| Setting           | Options                                                                       | Default          |
| ----------------- | ----------------------------------------------------------------------------- | ---------------- |
| Hyper Key         | None · Caps Lock · Right Control · Right Shift · Right Option · Right Command | **None**         |
| Quick Press       | Does Nothing · the original key · Trigger Escape                              | **Does Nothing** |
| Include Shift (⇧) | —                                                                             | **On**           |

See [Hotkeys](/docs/reference/hotkeys#hyper-key).

### Appearance

| Setting                           | Options               | Default    |
| --------------------------------- | --------------------- | ---------- |
| Theme                             | System · Light · Dark | **System** |
| Compact mode                      | —                     | Off        |
| Show favorites in compact mode    | —                     | On         |
| Follow the cursor across displays | —                     | **On**     |
| Drag to reposition                | —                     | Off        |

### General

| Setting                  | Options                                     | Default               |
| ------------------------ | ------------------------------------------- | --------------------- |
| Launch at login          | —                                           | Off                   |
| Show in menu bar         | —                                           | **On**                |
| Pop to Root Search       | Immediately · 5 · 15 · 30 · 60 · 90 seconds | **Immediately**       |
| Escape Key Behavior      | Pop back or close · Close and pop to root   | **Pop back or close** |
| Auto-switch input source | None, plus every enabled keyboard source    | **None**              |

Shortcuts keep working with the menu-bar icon hidden.

## Permissions

Shows the Accessibility status and opens the right System Settings pane. See
[Permissions](/docs/permissions).

## Launcher panes

**Applications** · **System Settings** · **System Actions** · **Commands** · **Quicklinks**

Each is a list with a **Show in launcher** master toggle and, per row, a visibility checkbox, a
shortcut recorder and an [alias](/docs/launcher/aliases) field. Longer lists have a filter field.

**Commands** additionally holds the [Custom Commands](/docs/launcher/commands#custom-commands)
switch, and **Quicklinks** holds the [Quicklinks](/docs/launcher/quicklinks) switch.

## Feature panes

Seven features, all off by default.

| Pane                                                  | Switch                   | Other settings                                                              |
| ----------------------------------------------------- | ------------------------ | --------------------------------------------------------------------------- |
| [File Search](/docs/features/file-search)             | Enable File Search       | Search Scopes, Ignore Patterns                                              |
| [Notes](/docs/features/notes)                         | Enable Notes             | Per-command visibility and shortcut                                         |
| [Snippets](/docs/features/snippets)                   | Enable snippets          | Show in launcher, New Snippet, Snippets Folder                              |
| [Window Management](/docs/features/window-management) | Enable window management | Show in launcher, Cycle sizes on repeat, Gap (0–64 pt, default 0)           |
| [Clipboard](/docs/features/clipboard)                 | _(always on)_            | Keep history for (**3 Months**), Disabled Applications, Clear history       |
| [Emoji & Symbols](/docs/features/emoji)               | _(always on)_            | Emoji Skin Tone (**Default**)                                               |
| [Extensions](/docs/extensions)                        | Enable extensions        | Show in launcher, package manager, registries, custom search paths, Storage |

Clipboard and Emoji have no feature switch — they are part of the palette itself.

## Advanced

**Backup** — export and import Tinycast settings, and
[import from Raycast](/docs/reference/import-from-raycast). See
[Backup](/docs/reference/backup).

**About** — version, license and links.

## What is never in a backup

| Excluded                                                   | Why                                   |
| ---------------------------------------------------------- | ------------------------------------- |
| `snippetsEnabled`                                          | It is consent to keystroke matching   |
| `extensionsEnabled`                                        | It is consent to run third-party code |
| Extension registries, package manager, custom search paths | Machine-specific                      |
| Palette position                                           | Machine-specific geometry             |
| Per-snippet confirmation flags                             | —                                     |

**A backup can never grant a capability.** That is a deliberate security control, not an oversight.
