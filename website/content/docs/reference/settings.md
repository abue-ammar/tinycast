---
title: Settings
description: Every Settings pane, what's in it, and the defaults.
---

Open Settings with <kbd>⌘</kbd><kbd>,</kbd> from the palette, the **Tinycast Settings** command or
the menu bar icon. It's a regular, resizable window.

**The search field finds any setting by name**, and also by related words that aren't in its title:
`ocr` finds **Search text in images and PDFs**, and `caps lock` finds **Hyper Key**. Choosing a
result takes you straight to that setting.

There are 23 panes in four groups.

## General

### General

| Setting       | Default  |
| ------------- | -------- |
| Show Launcher | **None** |

| Setting                           | Options                                                                                                                                                                                           | Default                                                                    |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Language                          | English, Deutsch, Español, Français, 日本語, 한국어, Português, Русский, 简体中文                                                                                                                 | Your Mac's language if Tinycast has it, otherwise **English**              |
| Launch at login                   | On · Off                                                                                                                                                                                          | Off                                                                        |
| Show in menu bar                  | On · Off                                                                                                                                                                                          | **On**                                                                     |
| Automatically check for updates   | On · Off                                                                                                                                                                                          | **On**                                                                     |
| Pop to Root Search                | Immediately · After 5, 15, 30, 60 or 90 seconds                                                                                                                                                   | **Immediately**                                                            |
| Escape Key Behavior               | Navigate back or close window · Close window and pop to root                                                                                                                                      | **Navigate back or close window**                                          |
| Auto-switch input source          | None, or any keyboard input source you have                                                                                                                                                       | **None**                                                                   |
| Appearance                        | System · Light · Dark                                                                                                                                                                             | **System**                                                                 |
| Show animations                   | On · Off                                                                                                                                                                                          | **On**                                                                     |
| Interface size                    | Default · Large · Larger                                                                                                                                                                          | **Default**                                                                |
| Window mode                       | Compact · Expanded                                                                                                                                                                                | **Compact**                                                                |
| Compact Shortcuts                 | Up to four, in your order, from Clipboard History, Search Emoji & Symbols, Search Files, Search Quicklinks, Search Snippets, Show Notes, My Schedule and Quick AI. Shown when Compact is selected | Clipboard History, Search Emoji & Symbols, Search Files, Search Quicklinks |
| Follow the cursor across displays | On · Off                                                                                                                                                                                          | **On**                                                                     |
| Drag to move the launcher         | On · Off                                                                                                                                                                                          | Off                                                                        |
| Hyper Key                         | None · Caps Lock · Left or Right Control, Shift, Option or Command                                                                                                                                | **None**                                                                   |
| Quick Press                       | Does Nothing · Trigger Caps Lock · Trigger Escape (Caps Lock only)                                                                                                                                | **Does Nothing**                                                           |
| Include Shift (⇧)                 | On · Off                                                                                                                                                                                          | **On**                                                                     |
| Secure Input Compatibility        | On · Off (Caps Lock only)                                                                                                                                                                         | **Off**                                                                    |
| Number format                     | System · English                                                                                                                                                                                  | **System**                                                                 |
| Show suggestions                  | On · Off                                                                                                                                                                                          | **On**                                                                     |
| Search sensitivity                | Low · Medium · High                                                                                                                                                                               | **Medium**                                                                 |
| Learned ranking                   | **Reset…** clears all learned ranking                                                                                                                                                             |                                                                            |

See [The palette](/docs/palette), [Learned ranking](/docs/launcher#learned-ranking) and
[Hotkeys](/docs/reference/hotkeys#hyper-key).

### Permissions

Shows whether **Accessibility**, **Full Disk Access**, **Calendars** and **Microphone** access is
granted, and opens the right System Settings pane. See [Permissions](/docs/permissions).

## Launcher

| Pane            | What's in it                                                                                                                          |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Applications    | [Search Scopes](/docs/launcher#search-scopes), **Enable Applications**, and a row per app                                             |
| System Settings | **Enable System Settings**, and a row per pane                                                                                        |
| System Actions  | **Enable System Actions**, and a row per action                                                                                       |
| Commands        | **Enable Commands**, a row per built-in command, and [Custom Commands](/docs/launcher/commands#custom-commands)                       |
| Quicklinks      | [Quicklinks](/docs/launcher/quicklinks) switch, its commands, behavior, import and export                                             |
| Apple Shortcuts | [Apple Shortcuts](/docs/features/apple-shortcuts) switch (**Off**), a row per shortcut from the Shortcuts app, and **Open Shortcuts** |
| Fallbacks       | Which [fallbacks](/docs/launcher/fallbacks) show under a search, and their order                                                      |

Most rows have a launcher checkbox, a shortcut recorder and an [alias](/docs/launcher/aliases)
field. Long lists have a filter field.

The **Enable …** switch at the top of a pane turns off every row **and** every shortcut in it. A
row's checkbox only hides that row from search.

## Features

Everything here is **off** by default, except Clipboard and Emoji & Symbols.

| Pane                                                  | Switch                            | Other settings                                                                                                                                                                                                                                                                                                                                                         |
| ----------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Clipboard](/docs/features/clipboard)                 | Enable Clipboard History (**On**) | Clipboard commands, Keep history for (**3 Months**), Search text in images and PDFs (**Off**), Default action (**Paste**), Excluded Applications, Clear history                                                                                                                                                                                                        |
| [Snippets](/docs/features/snippets)                   | Enable snippets                   | Show in launcher, Default action (**Paste**), snippet commands, New Snippet, Snippets Folder                                                                                                                                                                                                                                                                           |
| [File Search](/docs/features/file-search)             | Enable File Search                | Show in launcher (**Off**), Full Disk Access, Indexed Items, Rebuild Index, Commands, Search Scopes, Ignore Patterns                                                                                                                                                                                                                                                   |
| [Window Management](/docs/features/window-management) | Enable window management          | Show in launcher, Cycling (**None**), Gap between windows (**0 pt**), Shortcut preset, [Window Layouts](/docs/features/window-layouts), [Rooms](/docs/features/rooms), Layout and Room Commands, Custom Sizes, window commands                                                                                                                                         |
| [Navigation](/docs/features/navigation)               | Enable navigation                 | Commands, Show Apple menu items (**Off**), Excluded Applications                                                                                                                                                                                                                                                                                                       |
| [Notes](/docs/features/notes)                         | Enable Notes                      | Render Markdown (**On**), Show Formatting Bar (**On**), Show in Menu Bar (**Off**), Notes Folder, Notes commands                                                                                                                                                                                                                                                       |
| [Calendar](/docs/features/calendar)                   | Join meetings from Tinycast       | Show in launcher, Upcoming meetings in launcher (**5 next**), Show the meeting card (**5 minutes**), Auto Join Meetings (**Off**), Camera Preview (**Off**), Open Meeting Links In (**Default Browser**), Calendar in Menu Bar (**Disabled**), Days to Show (**Today and Tomorrow**), other menu bar settings, Calendar commands, Calendars                            |
| [Emoji & Symbols](/docs/features/emoji)               | _(always on)_                     | Emoji commands, Column Count (**8**), Emoji Skin Tone (**Default**)                                                                                                                                                                                                                                                                                                    |
| [Dictation](/docs/features/dictation)                 | Enable Dictation                  | Shortcut behavior (**Press to start or stop**), Shortcut, Play sounds (**On**), Engine (**Parakeet**), Model (**Redux**) with Download and Remove, Language (Qwen only, **Auto**), Release model from memory (**1 minute**), Microphone (**System default**), When finished (**Paste in active app**), Insert while recording (**Off**), Adapt capitalization (**On**) |
| [AI](/docs/ai)                                        | Enable AI                         | Providers, AI commands, Default model, Reasoning effort, Web search, Suggested replies, Expand thinking, Tool call rounds, Opens to, Start a new conversation after, Keep conversations, System prompt, [MCP servers](/docs/ai/mcp)                                                                                                                                    |
| [Quick Actions](/docs/ai/quick-actions)               | Enable Quick Actions              | Actions (Replace or Preview, shortcut, prompt, model), Add Quick Action, Model, Reasoning effort, Translate to                                                                                                                                                                                                                                                         |
| [Extensions](/docs/extensions)                        | Enable extensions                 | Show in launcher, Search extensions, Install from GitHub, Import from Raycast, Add from folder, installed extensions, Compatibility, Leftover files                                                                                                                                                                                                                    |

## Advanced

**Backup.** Export a backup, import one, or
[import from Raycast](/docs/reference/import-from-raycast). See [Backup & restore](/docs/reference/backup).
**Sync settings file** (**Off**) keeps your settings in a JSON file you can edit. See
[Settings file](/docs/reference/backup#settings-file).

**About.** Version, license, **Check for Updates**, links to the project, and **Support**. See
[Updates](/docs/reference/updates).
