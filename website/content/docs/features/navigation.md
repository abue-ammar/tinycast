---
title: Navigation
description: Switch to any open window, or click any menu bar item, from the launcher.
---

Navigation adds three keyboard commands:

- **Switch Windows** lists every open window of every running app and brings the one you choose to
  the front.
- **Switch Windows Backwards** opens the same list and moves through it in reverse.
- **Search Menu Bar Items** lists every item in the frontmost app's menus and clicks the one you
  choose.

Turn it on in **Settings → Navigation → Enable navigation**. It's **off** by default. While it's off,
none of the commands appears in the launcher and their shortcuts do nothing.

All three need the [Accessibility permission](/docs/permissions). None needs Screen Recording.

Each command has a checkbox, a shortcut recorder and an alias field in **Settings → Navigation**.

## Switch Windows

The list starts with the app you used most recently, and each app's windows are listed from front to
back. **Minimized windows come last.** Type to filter by window title or app name.

<kbd>return</kbd> (**Switch to Window**) brings the window to the front:

- A minimized window is restored first.
- A window on another Space switches you to that Space.

If the app quit after the list opened, Tinycast tells you instead of doing nothing.

Press the Switch Windows shortcut again while the list is open to move to the next window. If you
keep holding the shortcut's modifier while you press, releasing it switches to the selected window,
like <kbd>⌘</kbd><kbd>tab</kbd>. For example, with the shortcut set to <kbd>⌥</kbd><kbd>tab</kbd>,
hold <kbd>⌥</kbd>, press <kbd>tab</kbd> to move through the list, and release to switch. A single
press still opens the list for searching.

The Switch Windows Backwards shortcut moves up the list instead, wrapping around to the last window.
Set it to <kbd>⌥</kbd><kbd>⇧</kbd><kbd>tab</kbd> and, while holding <kbd>⌥</kbd>, press
<kbd>tab</kbd> or <kbd>⇧</kbd><kbd>tab</kbd> to move either way before you release.

## Search Menu Bar Items

Open it over any app and every menu item appears as a row, with the app's icon, the item's name, its
location (like `File → Export`) and its keyboard shortcut, if it has one.

With an empty search, rows are grouped by top-level menu, like File, Edit and View. When you type,
they merge into one **Results** list sorted by match. <kbd>return</kbd> (**Activate Menu Item**)
clicks the selected item.

### Good to know

- **It always acts on the app that was in front when you opened it.** Switching apps afterward
  doesn't change the target.
- **Only items you could click are listed.** Disabled items, separators and hidden items are left
  out.
- **Tinycast never opens menus to read them.** Some apps only build a submenu when you open it, so
  those items may be missing. Opening menus in the background would make the app's interface flash
  every time.
- Very large menus are limited to 4,000 items, and reading stops after about a second.

### Settings

| Setting               | Default | What it does                                        |
| --------------------- | ------- | --------------------------------------------------- |
| Show Apple menu items | **Off** | Adds the Apple menu, which is the same in every app |
| Disabled Applications | Empty   | Apps whose menus Tinycast never reads               |

Tinycast checks the Disabled Applications list before reading any menus, so it never reads those
apps' menus at all.

When there's nothing to search, you see a short explanation instead of an empty list, like
**Finder has no menu bar to search** or **Menu search is turned off for 1Password**.
