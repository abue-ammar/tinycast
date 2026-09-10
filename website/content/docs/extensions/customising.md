---
title: Configuring an extension
description: Preferences, launcher icons, and making a third-party extension look like it belongs.
---

**Settings → Extensions → Library → Configure** on any installed extension.

## Preferences

Whatever the extension declares, rendered as a native control: checkbox, dropdown, text field,
password field, file picker, directory picker or app picker.

These are stored per extension in Tinycast's own folder and removed when you uninstall it.

## Launcher icon

Replace an extension's shipped artwork with an **SF Symbol on a tinted tile** — 18 tints available,
or **Use Original** to clear it.

The choice is stored per extension and applies to **every command** it provides.

The symbol picker opens on about 85 curated suggestions, but **search reaches the whole catalog** —
roughly 6,500 symbols — regardless of which category is selected. It uses Apple's own extra search
terms, so "coffee" finds `cup.and.saucer`.

Apple's reserved marks (iCloud, iPhone, AirPlay and around 600 others) are never offered, because
using them outside Apple's own context is not permitted.

Icon choices **do** ride along in [settings backups](/docs/reference/backup).

## Command alias

Each command has an **Add Alias** field beside its shortcut recorder. Type `si` and that command
ranks first when you search `si`, the same way an [application alias](/docs/launcher/aliases) works.

The field dims when the command is hidden from launcher search.

## Uninstalling

Removes the extension and everything attached to it: local storage, cache, preferences, its support
folder, the icon override, command shortcuts, favorites, hidden-item state, aliases and learned
ranking.
