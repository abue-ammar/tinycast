---
title: App launcher
description: One search across everything Tinycast knows about, and how it orders the results.
---

The launcher is the root screen. One search covers your apps, System Settings panes, commands,
quicklinks, snippets, system actions, window commands and layouts, custom commands, Quick Actions,
extension commands and upcoming meetings.

<kbd>return</kbd> opens the selection. <kbd>⌘</kbd><kbd>K</kbd> shows everything else you can do
with it.

## With nothing typed

[Favorites](/docs/launcher/favorites) come first, followed by each section in this order:

Meetings → Applications → System Settings → Extensions → Quicklinks → Snippets → System Actions →
Window Layouts → Window Management → Custom Commands → Quick Actions → Commands

Each section is sorted alphabetically and keeps that order, because a list that reorders itself as
you use it is hard to scan.

When a meeting is about to start, a [join card](/docs/features/calendar#the-join-card) appears above
everything else.

## When you type

The sections merge into one **Results** list, sorted by how well each entry matches. A few extras can
appear around it:

- **A calculator card** at the top when your text is a
  [calculation](/docs/features/calculator), like `12% of 80` or `time in Tokyo`.
- **A color card** when you paste a color like `#FF5733`.
- **Open in Browser** at the top when you type a web address or a bare domain, like `github.com`.
- **"Use … with"** rows at the bottom, which send your text somewhere else. See
  [Fallbacks](/docs/launcher/fallbacks).

### Listing a whole category

Type a section's exact name, like `Snippets`, `Snippet` or `Window Management`, to list that whole
category under its own heading.

The name has to match exactly. An app with exactly that name still appears too, which is why typing
`System Settings` lists both the app and its panes.

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

Typing a name or alias exactly always puts that entry first, no matter how often you picked
something else. Everything below that can change with [learned ranking](#learned-ranking).

A few more rules keep results useful:

- **Bundle identifiers only match as typed**, never by scattered letters. Otherwise almost any short
  search would match almost every app. They also match without the leading `com.`, so `apple.Photos`
  works, and pasting the full `com.apple.Photos` still finds the app.
- **An extension's name ranks low.** An extension called `Safari` can't push the real Safari out of
  first place.

### Names in your language

Apps are shown the way Finder shows them, in your Mac's language. The English name still works, so
on a Mac set to Portuguese, both `Find My` and `Buscar` find the same app.

Apps also match the other names macOS knows them by: `Address Book` finds Contacts,
`System Preferences` finds System Settings, and `browser`, `浏览器` or `사파리` all find Safari.

Names in other scripts also get a Latin spelling: `微信` matches `weixin` and `wx`, `メモ帳` matches
`memo`, and `Яндекс` matches `yandeks`.

If you renamed an app in Finder, both the old and the new name find it.

## Learned ranking

Tinycast remembers which result you pick for a search and moves it up the next time. This happens on
your Mac.

If you pick WhatsApp after typing `wha`, it also ranks higher for `w` and `wh`. The more often and
the more recently you pick something, the bigger the boost.

Some ways of opening things don't count, because they aren't searches: opening something with its
own shortcut, opening a favorite with <kbd>⌘</kbd> and a number, listing a category, and Open in
Browser.

**Resetting.** For one entry, choose <kbd>⌘</kbd><kbd>K</kbd> → **Reset Ranking**. It only appears
when Tinycast has learned something about that entry. To reset everything, go to
**Settings → General → Learned ranking → Reset**.

This data is stored in `launcher-ranking.json` in Tinycast's own folder and is never sent anywhere.

## Search scopes

**Settings → Applications → Search Scopes** sets which folders Tinycast searches for apps. A scope can
be a folder or a single `.app`.

The defaults cover `/Applications`, `/System/Applications`, both `Utilities` folders,
`/System/Library/CoreServices/Applications`, the hidden system folder where Safari is actually
installed, `~/Applications`, and Finder itself.

Tinycast searches **one folder deep**, so it finds `/Applications/Blackmagic Design/DaVinci Resolve.app`
without a separate scope. Apps nested deeper need their own scope. Tinycast never looks inside an app
bundle.

Scopes are saved with your home folder written as `~`, so a backup still works on another Mac.
Tinycast searches again as soon as you change them.

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
| [Uninstall Application](/docs/launcher/uninstall) |                                                     |

**Restart Application** and **Quit Application** only appear while the app is running. Both ask the
app to quit normally, so an app with unsaved work still asks you to save it. Restart waits up to five
seconds for the app to quit, then opens it again. If the app doesn't quit, it isn't reopened.

To quit every app at once, use the **Quit All Applications**
[system action](/docs/launcher/system-actions). It leaves Finder and Tinycast running.

## Hiding a result

<kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> (**Hide from Search**) removes the selected entry from search
results. The palette stays open on the same search.

It works for apps, System Settings panes, commands, Quick Actions, system actions, window commands
and window layouts. To show an entry again, select its checkbox in the matching Settings pane.
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
