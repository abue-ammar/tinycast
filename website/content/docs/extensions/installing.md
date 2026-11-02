---
title: Installing extensions
description: The four ways to install, how updates work, and when you need a toolchain.
---

**Settings → Extensions → Install** offers four ways to install extensions.

## Search extensions

**Search…** searches the Raycast Store and installs the extension it has already built. This is the
usual way to install, and **it doesn't need Node or a package manager**.

The **Install** buttons on the Raycast Store website open the same search in Tinycast, on that
extension. Nothing installs until you click **Install**. If Raycast is also installed, macOS decides
which app receives those links.

## Install from GitHub

**Install…** builds one extension from its source on this Mac. Enter `owner/repo`, or paste the link
your browser shows for one extension's folder, such as a folder inside `raycast/extensions`. Tinycast
only downloads that folder, not the whole repository.

Building needs Node and a [package manager](#package-managers). Tinycast runs
`<package manager> install --ignore-scripts`, then builds the extension. **Install scripts are
skipped**, because they run code you didn't choose to run. If an extension doesn't build, it fails at
the build step instead of being installed half-broken.

**Only the build is kept.** The source and its dependencies are deleted once the extension
installs. Closing the panel cancels a build in progress, and nothing is left behind.

## Import from Raycast

Copy the extensions you already have in Raycast on this Mac.

**This doesn't need Node, a package manager or a network connection**, because the extensions are
already built.

Tinycast checks both `~/.config/raycast` and `~/.config/raycast-x`, and an extension found in both
is only listed once. You can use **Import All** to import everything. The pane checks again each time
you open it and tells you when Raycast has extensions that Tinycast doesn't.

## Add from folder

Choose any folder that contains a manifest and built command files, like a project you just built
yourself.

Tinycast only copies `package.json`, the built commands, `assets/` and any packages the build
bundled in `node_modules`. It never copies source maps.

## Updates

Each time you open **Settings → Extensions**, Tinycast checks the Raycast Store for newer versions of
the extensions you installed from it or imported from Raycast. An extension with an update shows
**Update** on its row, and **Update All** above the list updates every one. Updating keeps the
extension's preferences, storage and icon.

Extensions installed from GitHub or a folder are never checked. To update one, install it again.

## Package managers

The **Install from GitHub** panel has a **Package manager** menu.

**Automatic** (default) uses the first one you have from this list: **pnpm → Bun → Yarn → npm**. The
fastest and most disk-efficient come first, and npm, which is almost always installed, comes last.

Apps opened from the Dock don't get your terminal's `PATH`, so Tinycast checks the usual install
locations itself: Homebrew, Volta, asdf, mise, fnm, nvm and Yarn. The panel shows what it found, like
"Found pnpm at /opt/homebrew/bin/pnpm.", or tells you that none is installed.

### Custom search paths

For other locations, like Nix, the same panel has **Custom search paths**: a list of folders
separated by colons, like `PATH`, that Tinycast checks **before** the usual locations.

```
~/.local/share/mise/shims
```

```
/etc/profiles/per-user/you/home-path/bin
```

Once you set it, every future install uses it.

## What isn't backed up

Two settings are left out of [backups](/docs/reference/backup) because they're specific to _this
Mac_:

- The package manager choice
- Custom search paths

## Storage

Everything is stored in Tinycast's Application Support folder, and **uninstalling an extension
removes all of it**: the extension, its storage and cache, its preferences and sign-ins, its support
folder, its icon choice, and its command shortcuts, favorites, aliases and learned ranking.

**Settings → Extensions → Storage → Leftover files** shows the size of leftover build folders, like
those a crashed install can leave behind, and **Clean Up…** removes them. It works even while
extensions are off, and it's normally empty.

Tinycast never touches your own `~/Library/pnpm` or `~/.npm`.
