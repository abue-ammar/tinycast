---
title: Getting started
description: What Tinycast is and how to set it up.
---

Tinycast is a small, native launcher for macOS that lives in your menu bar. Press your shortcut and a
palette opens over whatever you're doing. Type what you want, press return, and the palette closes.

It's built with SwiftUI and AppKit, has no third-party dependencies, and uses less than 100 MB of
memory. It doesn't use Electron, and there's no account, sign-in or telemetry.

## Set it up

The first time you open Tinycast, a short welcome walks you through these steps. You can skip any of
them and come back later.

### 1. Pick a shortcut

Tinycast doesn't come with a shortcut, so it can't take over a key combination you already use.
Until you choose one, open the launcher from the menu bar icon, or open Tinycast again from Finder or
Spotlight.

The welcome screen asks for a shortcut. To change it later, go to
**Settings → General → Global Shortcuts → Show Launcher**, click the field and press the keys you
want. Many people use <kbd>⌥</kbd><kbd>Space</kbd>.

You can also double-tap a modifier key, like pressing <kbd>⌘</kbd> twice. See
[Hotkeys](/docs/reference/hotkeys).

This step also has a **Launch at login** switch, so Tinycast is ready after you restart your Mac.

### 2. Allow pasting (optional)

Tinycast asks for Accessibility access so it can paste a clip or an emoji into the app you were
using. The launcher itself doesn't need any permissions. See [Permissions](/docs/permissions).

### 3. Bring your Raycast setup (optional)

If you used Raycast, choose its `.rayconfig` export and enter the passphrase you set when you
exported it. You choose what to bring: shortcuts, favorites, aliases, snippets, quicklinks,
clipboard history and a few settings. See [Import from Raycast](/docs/reference/import-from-raycast).

When you finish, **Get Started** opens the launcher.

Tinycast uses your Mac's language if it has a translation for it, and English otherwise. To change
it, go to **Settings → General → Language**.

## Turn on what you want

Most features are off when you install Tinycast. A feature that's off does nothing: it doesn't scan,
index or use memory. That's how the app stays small with a long feature list.

| Feature                                               | Where to turn it on          |
| ----------------------------------------------------- | ---------------------------- |
| [AI Chat](/docs/ai)                                   | Settings → AI                |
| [Quick Actions](/docs/ai/quick-actions)               | Settings → Quick Actions     |
| [File Search](/docs/features/file-search)             | Settings → File Search       |
| [Notes](/docs/features/notes)                         | Settings → Notes             |
| [Snippets](/docs/features/snippets)                   | Settings → Snippets          |
| [Navigation](/docs/features/navigation)               | Settings → Navigation        |
| [Window Management](/docs/features/window-management) | Settings → Window Management |
| [Calendar](/docs/features/calendar)                   | Settings → Calendar          |
| [Quicklinks](/docs/launcher/quicklinks)               | Settings → Quicklinks        |
| Apple Shortcuts                                       | Settings → Apple Shortcuts   |
| Dictation                                             | Settings → Dictation         |
| [Custom commands](/docs/launcher/commands)            | Settings → Commands          |
| [Extensions](/docs/extensions)                        | Settings → Extensions        |

[Clipboard history](/docs/features/clipboard) is the only feature that starts on. You can turn it
off in **Settings → Clipboard**.

## Learn one shortcut first

Everything happens in one window. Type to search, press <kbd>return</kbd> to act on the selection,
press <kbd>⌘</kbd><kbd>K</kbd> to see every other action, and press <kbd>esc</kbd> to go back.

<kbd>⌘</kbd><kbd>K</kbd> is the one to remember. Every screen lists all of its actions there, each
with its shortcut, so it's the fastest way to learn the app.

Next, read about [the palette](/docs/palette), or [install Tinycast](/docs/install) if you haven't
yet.
