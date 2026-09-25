---
title: Settings
description: Every Settings pane, what it holds, and its defaults.
---

Open Settings with <kbd>⌘</kbd><kbd>,</kbd> from the palette, the **Settings** command, or the menu bar
icon. It is a normal, resizable window.

**The search field finds any setting by name**, and also by words that are not in its title: `ocr`
finds **Search text in images and PDFs**, and `caps lock` finds **Hyper Key**. Picking a result jumps
straight to that row.

There are 21 panes in four groups.

## General

### General

| Setting      | Default  |
| ------------ | -------- |
| App Launcher | **None** |

| Setting                           | Options                                                                       | Default                           |
| --------------------------------- | ----------------------------------------------------------------------------- | --------------------------------- |
| Learned ranking                   | **Reset…** clears everything learned                                          | —                                 |
| Hyper Key                         | None · Caps Lock · Right Control · Right Shift · Right Option · Right Command | **None**                          |
| Quick Press                       | Does Nothing · the original key · Trigger Escape                              | **Does Nothing**                  |
| Include Shift (⇧)                 | On · Off                                                                      | **On**                            |
| Theme                             | System · Light · Dark                                                         | **System**                        |
| Interface size                    | Default · Large · Larger                                                      | **Default**                       |
| Background transparency           | Less to More, with Reset                                                      | Middle                            |
| Compact mode                      | On · Off                                                                      | Off                               |
| Show favorites in compact mode    | On · Off                                                                      | **On**                            |
| Follow the cursor across displays | On · Off                                                                      | **On**                            |
| Drag to reposition                | On · Off                                                                      | Off                               |
| Launch at login                   | On · Off                                                                      | Off                               |
| Show in menu bar                  | On · Off                                                                      | **On**                            |
| Pop to Root Search                | Immediately · After 5, 15, 30, 60 or 90 seconds                               | **Immediately**                   |
| Escape Key Behavior               | Navigate back or close window · Close window and pop to root                  | **Navigate back or close window** |
| Auto-switch input source          | None, or any keyboard input source you have                                   | **None**                          |

See [The palette](/docs/palette), [Learned ranking](/docs/launcher#learned-ranking) and
[Hotkeys](/docs/reference/hotkeys#hyper-key).

### Permissions

Shows whether **Accessibility** and **Calendars** are granted, and opens the right System Settings
pane. See [Permissions](/docs/permissions).

## Launcher

| Pane            | What is in it                                                                                                   |
| --------------- | --------------------------------------------------------------------------------------------------------------- |
| Applications    | [Search Scopes](/docs/launcher#search-scopes), **Enable Applications**, and a row per app                       |
| System Settings | **Enable System Settings**, and a row per pane                                                                  |
| System Actions  | **Enable System Actions**, and a row per action                                                                 |
| Commands        | **Enable Commands**, a row per built-in command, and [Custom Commands](/docs/launcher/commands#custom-commands) |
| Quicklinks      | [Quicklinks](/docs/launcher/quicklinks) switch, its commands, behavior, import and export                       |
| Fallbacks       | Which [fallbacks](/docs/launcher/fallbacks) show under a search, and their order                                |

A row usually has a launcher checkbox, a shortcut recorder and an [alias](/docs/launcher/aliases)
field. Long lists have a filter field.

The **Enable …** switch at the top of a pane turns off every row **and** every shortcut in it. A row's
checkbox only hides that row from search.

## Features

Everything here ships **off**, except Clipboard and Emoji & Symbols.

| Pane                                                  | Switch                            | Other settings                                                                                                                                                                                                                                |
| ----------------------------------------------------- | --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [AI](/docs/ai)                                        | Enable AI                         | Providers, Default model, Reasoning effort, Web search, Tool call rounds, Opens to, Start a new conversation after, Keep conversations, System prompt, [MCP servers](/docs/ai/mcp), AI commands                                               |
| [Quick Actions](/docs/ai/quick-actions)               | Enable Quick Actions              | Actions (Replace or Preview, shortcut, prompt, model), Add Quick Action, Model, Translate to                                                                                                                                                  |
| [File Search](/docs/features/file-search)             | Enable File Search                | Commands, Search Scopes, Ignore Patterns                                                                                                                                                                                                      |
| [Notes](/docs/features/notes)                         | Enable Notes                      | Notes commands                                                                                                                                                                                                                                |
| [Snippets](/docs/features/snippets)                   | Enable snippets                   | Show in launcher, snippet commands, New Snippet, Snippets Folder                                                                                                                                                                              |
| [Navigation](/docs/features/navigation)               | Enable navigation                 | Commands, Show Apple menu items (**Off**), Disabled Applications                                                                                                                                                                              |
| [Window Management](/docs/features/window-management) | Enable window management          | Show in launcher, Cycling (**None**), Gap between windows (**0**), window commands, [Window Layouts](/docs/features/window-layouts), [Rooms](/docs/features/rooms)                                                                                                           |
| [Clipboard](/docs/features/clipboard)                 | Enable Clipboard History (**On**) | Clipboard commands, Keep history for (**3 Months**), Search text in images and PDFs (**Off**), Default action (**Paste**), Disabled Applications, Clear history                                                                               |
| [Emoji & Symbols](/docs/features/emoji)               | _(always on)_                     | Emoji commands, Emoji Skin Tone (**Default**)                                                                                                                                                                                                 |
| [Calendar](/docs/features/calendar)                   | Join meetings from Tinycast       | Show in launcher, Upcoming meetings in launcher (**5 next**), Include Tomorrow's Events (**On**), Show the join card (**5 minutes**), Auto Join Meetings (**Off**), Camera Preview (**Off**), menu bar settings, Calendar commands, Calendars |
| [Extensions](/docs/extensions)                        | Enable extensions                 | Show in launcher, Compatibility, installed extensions, Install, Registries, Package manager, Storage                                                                                                                                          |

## Advanced

**Backup.** Export a backup, import one, or
[import from Raycast](/docs/reference/import-from-raycast). See [Backup & restore](/docs/reference/backup).

**About.** Version, license, **Check for Updates**, links to the project, and **Support**. See
[Updates](/docs/reference/updates).
