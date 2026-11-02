---
title: App launcher
description: One search across everything Tinycast knows about, and how it orders the results.
---

The launcher is the root screen. One search covers your apps, System Settings panes, commands,
quicklinks, Apple Shortcuts, snippets, system actions, window commands, layouts and rooms, custom
commands, Quick Actions, extension commands and upcoming meetings.

<kbd>return</kbd> opens the selection. <kbd>⌘</kbd><kbd>K</kbd> shows everything else you can do
with it.

## With nothing typed

[Favorites](/docs/launcher/favorites) come first, then upcoming Meetings and
[Suggestions](#suggestions), followed by each section in this order:

Applications → System Settings → Extensions → Quicklinks → Apple Shortcuts → Snippets → System
Actions → Window Layouts → Rooms → Window Management → Custom Commands → Quick Actions → Commands

Within a section, the entries you open most come first, then entries with an alias. The rest are
sorted alphabetically. Meetings stay in the order they start.

### Suggestions

**Suggestions** shows up to five entries you're likely to want:

- an app or extension you installed in the last five minutes and haven't opened yet
- the entries you open most, unless they already have a shortcut
- while you have little history, a few built-in commands like Clipboard History and Search Files

Favorites, meetings and AI commands are never suggested. A suggested entry doesn't appear again in
its own section. To hide Suggestions, turn off **Settings → General → Search → Show suggestions**.

When a meeting is about to start, a [join card](/docs/features/calendar#the-join-card) appears above
everything else.

## When you type

The sections merge into one **Results** list, sorted by how well each entry matches. A few extras can
appear around it:

- **A calculator card** at the top when your text is a
  [calculation](/docs/features/calculator), like `12% of 80` or `time in Tokyo`.
- **A color card** when you paste a color like `#FF5733`.
- **Open in Browser** at the top when you type a web address or a bare domain, like `github.com`.
- **Files** below the results, when [File Search](/docs/features/file-search#in-the-launcher) has
  **Show in launcher** on and you type three or more characters. Favorite files and folders whose
  names match appear there too, even with **Show in launcher** off.
- **"Use … with"** rows at the bottom, which send your text somewhere else. See
  [Fallbacks](/docs/launcher/fallbacks).

### Listing a whole category

Type a section's name, like `Snippets`, `Snippet` or `Window Management`, to list that whole
category under its own heading. An app with exactly that name still appears too, which is why typing
`System Settings` lists both the app and its panes.

From three characters, the start of a section's name, or of a word in it, also works: `win` includes
Window Management and Window Layouts. Your best matches still come first under **Results**, so
<kbd>return</kbd> opens the top match, and the rest of the category follows under its own heading.

## How matching works

Tinycast checks several names for each entry and gives some of them more weight than others:

| Name                                  | Example                                 |
| ------------------------------------- | --------------------------------------- |
| Your [alias](/docs/launcher/aliases)  | `ps` for Photoshop                      |
| The display name                      | `Visual Studio Code`                    |
| Other names the app is known by       | `iCal` for Calendar, `微信` as `weixin` |
| The extension a command comes from    | `lucide` for Lucide's Search Icons      |
| The bundle identifier or program name | `apple.Photos`                          |

How the letters match also counts. From strongest to weakest: an exact match, a match at the start
of the name, a match at the start of a word, a match in the middle of a word, and scattered letters.

An exact alias has the strongest priority. Exact names longer than three characters also stay ahead
of learned matches, while short searches can adapt to your choices. [Learned ranking](#learned-ranking)
helps decide between matching entries.

A few more rules keep results useful:

- **Bundle identifiers only match as typed**, never by scattered letters. Otherwise almost any short
  search would match almost every app. They also match without the leading `com.`, so `apple.Photos`
  works, and pasting the full `com.apple.Photos` still finds the app.
- **An extension's name ranks low.** An extension called `Safari` can't push the real Safari out of
  first place.

**Settings → General → Search → Search sensitivity** sets how loose a match can be: **Low**,
**Medium** (default) or **High**. A lower value also shows less exact matches.

### Names in your language

Apps are shown the way Finder shows them, in your Mac's language. The English name still works, so
on a Mac set to Portuguese, both `Find My` and `Buscar` find the same app.

Apps also match alternate names from their own metadata, such as `Address Book` for Contacts and
`System Preferences` for System Settings. Localized names come from your preferred languages,
with English names available too.

Names in other scripts also get a Latin spelling: `微信` matches `weixin` and `wx`, `メモ帳` matches
`memo`, and `Яндекс` matches `yandeks`.

If you renamed an app in Finder, both the old and the new name find it.

## Learned ranking

Tinycast remembers which result you pick for a search and moves it up the next time. This happens on
your Mac.

If you pick WhatsApp after typing `wha`, it also ranks higher for `w` and `wh`. The more often and
the more recently you pick something, the bigger the boost.

Opening something with its own global shortcut doesn't count, and neither do fallbacks or Open in
Browser. Opening a favorite, including with <kbd>⌘</kbd> and a number, counts as a use but teaches
no search word. When you pick from a listed category, the pick counts, but the category's name isn't
learned as a search for it.

**Resetting.** For one entry, choose <kbd>⌘</kbd><kbd>K</kbd> → **Reset Ranking**. It only appears
when Tinycast has learned something about that entry. To reset everything, go to
**Settings → General → Search → Learned ranking** and click **Reset…**.

This data is stored in `launcher-ranking.json` in Tinycast's own folder and is never sent anywhere.

## Search scopes

**Settings → Applications → Search Scopes** sets which folders Tinycast searches for apps. A scope can
be a folder or a single `.app`. Click **Add…** to choose one or several folders or apps;
**Restore Defaults** returns to the original list.

The defaults cover `/Applications`, `/System/Applications`, both `Utilities` folders,
`/System/Library/CoreServices/Applications`, the hidden system folder where Safari is actually
installed, `~/Applications`, and Finder itself.

Tinycast searches **one folder deep**, so it finds `/Applications/Blackmagic Design/DaVinci Resolve.app`
without a separate scope. Apps nested deeper need their own scope. Inside an app, Tinycast only
looks for the apps it ships with, like Instruments and Simulator inside Xcode.

Scopes are saved with your home folder written as `~`, so a backup still works on another Mac.
Tinycast searches again as soon as you change them.

## Multiple installed copies

If you have several versions of an app, each installed path appears in search. Version numbers,
and the containing folder when needed, help you tell them apart. Opening or restarting a result
uses that copy's path.

Copies share their alias, favorite, visibility, learned ranking and global shortcut. Favorites,
Suggestions and Settings use one representative: the earliest search scope wins, and within a
folder the newest version wins. An app's global shortcut uses the running app or macOS's default
copy. Uninstall is unavailable while several indexed copies share the same bundle identifier,
because their support files can be shared.

## Actions on an app

Press <kbd>⌘</kbd><kbd>K</kbd> with an app selected:

| Action                                            | Shortcut                                            |
| ------------------------------------------------- | --------------------------------------------------- |
| Open Application                                  | <kbd>return</kbd>                                   |
| Show in Finder                                    | <kbd>⌘</kbd><kbd>return</kbd>                       |
| Add to / Remove from Favorites                    | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>F</kbd>                |
| Move Favorite Up / Down                           | <kbd>⌥</kbd><kbd>⌘</kbd><kbd>↑</kbd> / <kbd>↓</kbd> |
| Reset Ranking                                     |                                                     |
| Hide from Search                                  | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd>                |
| Restart Application                               | <kbd>⌘</kbd><kbd>R</kbd>                            |
| Quit Application                                  | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>Q</kbd>                |
| Force Quit Application                            | <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⇧</kbd><kbd>Q</kbd>    |
| [Uninstall Application](/docs/launcher/uninstall) |                                                     |

**Restart Application**, **Quit Application** and **Force Quit Application** only appear while the
app is running. Restart and Quit ask the app to quit normally, so an app with unsaved work still asks
you to save it. Restart waits up to five seconds for the app to quit, then opens it again. If the app
doesn't quit, it isn't reopened. **Force Quit Application** ends the app at once, so it can't save
or refuse.

To quit every app at once, use the **Quit All Applications**
[system action](/docs/launcher/system-actions). It leaves Finder and Tinycast running.

You can also drag an app result into Finder or another app that accepts files.

## Hiding a result

<kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> (**Hide from Search**) removes the selected entry from search
results. The palette stays open on the same search.

It works for apps, System Settings panes, commands, Quick Actions, Apple Shortcuts, system actions,
window commands, window layouts, rooms and extension commands. To show an entry again, select its
checkbox in the matching Settings pane.
On a quicklink or custom command it's **Hide from Root Search**, and you turn **Show in root search**
back on in its editor.

Hiding only changes what search shows. The app stays installed, and its favorite, alias, learned
ranking and shortcut keep working.

## Per-app shortcuts

You can give any app its own global shortcut in **Settings → Applications**. Press it to bring the
app to the front, and press it again while the app is in front to hide it.

See [Hotkeys](/docs/reference/hotkeys) for recording shortcuts and using double-tap shortcuts.

## Switching a whole section off

**Settings → Applications** has an **Enable Applications** switch, plus a checkbox for each app.

- Turning off **Enable Applications** removes every app from search **and** turns off every per-app
  shortcut.
- Clearing one app's checkbox only hides that app from search. Its shortcut keeps working.

System Settings, System Actions and Commands each have the same kind of switch in their own pane.
