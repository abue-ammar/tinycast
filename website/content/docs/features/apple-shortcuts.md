---
title: Apple Shortcuts
description: Run the shortcuts from Apple's Shortcuts app in the launcher or with a global shortcut.
---

Apple Shortcuts lists the shortcuts from Apple's Shortcuts app in the launcher, so you can run one
by name or with its own global shortcut.

Turn it on in **Settings → Apple Shortcuts → Enable Apple Shortcuts**. It's **off** by default.
Tinycast only lists and runs your shortcuts. To create or edit one, use the Shortcuts app.
**Open Shortcuts**, below the list in the pane, opens it.

## In the launcher

Your shortcuts have their own **Apple Shortcuts** section, right after Quicklinks, sorted by name.
Every row shows the Shortcuts app's icon.

| Action                         | Shortcut                             |
| ------------------------------ | ------------------------------------ |
| Run Shortcut                   | <kbd>return</kbd>                    |
| Add to / Remove from Favorites | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>F</kbd> |
| Reset Ranking                  |                                      |
| Hide from Search               | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> |

The launcher closes before the shortcut runs, so a shortcut that works on the front app works on
the app you were using.

A shortcut can take as long as it needs, including waiting on a dialog of its own. When it
succeeds, Tinycast shows nothing. When it fails, Tinycast shows **Couldn’t Run** with the
shortcut's name and the last lines of the error.

## Settings

While it's on, **Settings → Apple Shortcuts** lists every shortcut under **Shortcuts**, with:

- a search field, which also matches aliases
- an [alias](/docs/launcher/aliases) field for each shortcut
- a global shortcut recorder for each shortcut
- a checkbox for each shortcut, which only hides it from launcher search. Its global shortcut keeps
  working.

Tinycast reads your shortcuts again each time you open the launcher or this pane, so a new one
shows up without a restart.

Tinycast needs no permissions for this. It runs shortcuts through Apple's own `shortcuts` tool.

## Renaming and deleting

Tinycast follows each shortcut by its identifier, not its name. **Rename a shortcut in the
Shortcuts app and its alias, global shortcut and favorite stay with it.**

When you delete a shortcut, Tinycast removes its alias, global shortcut, favorite and ranking the
next time it reads the list. That includes shortcuts you deleted while Tinycast wasn't running.

## Turning it off

Turning it off removes the section from the launcher, and the global shortcuts you recorded stop
running anything. They're kept, so they work again when you turn it back on.

**Enable Apple Shortcuts** is included in [backups](/docs/reference/backup). The global shortcuts
you give your shortcuts aren't.
