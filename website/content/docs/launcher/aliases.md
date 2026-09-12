---
title: Aliases
description: Give anything in the launcher a second name that matches as strongly as its real one.
---

An alias is your own name for a launcher entry. Type `ps` and get Photoshop; type `sh` and get the
shell script you run every morning.

Aliases work on **any** entry — applications, System Settings panes, commands, quicklinks, snippets
and extension commands.

## Setting one

Aliases are edited in **Settings**, on the row for the item, in any pane that lists launcher items:
Applications, System Settings, System Actions, Commands, Quicklinks, Extensions, and the
feature panes.

There is a clear button on the field, and one alias per entry.

This is deliberately not in the <kbd>⌘</kbd><kbd>K</kbd> menu. Renaming something is a settings
change, not a thing you do mid-search.

## How an alias ranks

From [the matching bands](/docs/launcher#how-matching-works):

- A match at the **start** of an alias ranks the entry **first** — above everything, including an
  exact display-name match on something else.
- A match **inside** an alias ranks alongside Spotlight alternate names.
- A **subsequence** of an alias never matches. `ps` will not match an alias of `Pixelmator Studio`
  by skipping letters, because that would make short aliases useless.

That first rule is the point: a two-letter alias should win outright, or it is not worth setting.

## In the list

A row with an alias shows it as a small chip after the name, so you can see at a glance which
entries you have renamed.

## Backup and lifecycle

Aliases ride along in [settings backups](/docs/reference/backup) under `launcherAliases`.

An alias is removed when its target goes — uninstall the app and the alias goes with it, rather than
lingering and matching nothing.

Raycast's v2 export carries an alias per command; importing maps the application ones across by
bundle id. See [Import from Raycast](/docs/reference/import-from-raycast).
