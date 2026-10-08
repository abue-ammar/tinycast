---
title: Installing extensions
description: The three ways to install, the registries behind them, and when you need a toolchain.
---

**Settings → Extensions → Install** offers three ways to install extensions.

## Search Registries

Search every enabled registry and install from any of them. This is the usual way to install.

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

Tinycast only copies `package.json`, the built commands and `assets/`. It never copies
`node_modules` or source maps.

## Registries

Two registries are on by default, and you can add your own.

|           | Raycast Store              | A GitHub repository        |
| --------- | -------------------------- | -------------------------- |
| Gives you | An extension already built | Source code                |
| You need  | Nothing                    | Node and a package manager |

**Because the store provides prebuilt extensions, most people don't need a toolchain at all.**

A GitHub registry is any repository with one folder per extension, like `raycast/extensions`. Add one
with `owner/repo` or a link to the folder. Tinycast only downloads the extension's own folder, not the
whole repository.

Installing from source runs `<package manager> install --ignore-scripts`, then builds the extension.
**Install scripts are skipped**, because they run code you didn't choose to run. If an extension
doesn't build, it fails at the build step instead of being installed half-broken.

## Package managers

**Settings → Extensions → Package manager**

**Automatic** (default) uses the first one you have from this list: **pnpm → Bun → Yarn → npm**. The
fastest and most disk-efficient come first, and npm, which is almost always installed, comes last.

Apps opened from the Dock don't get your terminal's `PATH`, so Tinycast checks the usual install
locations itself: Homebrew, Volta, asdf, mise, fnm, nvm and Yarn. The pane shows what it found, like
"Found pnpm at /opt/homebrew/bin/pnpm", or tells you that none is installed.

### Custom search paths

For other locations, like Nix, the Registries sheet has **Custom search paths**: a list of folders
separated by colons, like `PATH`, that Tinycast checks **before** the usual locations.

```
~/.local/share/mise/shims
```

```
/etc/profiles/per-user/you/home-path/bin
```

Once you set it, every future install uses it.

## What isn't backed up

Three settings are left out of [backups](/docs/reference/backup) because they're specific to _this
Mac_:

- The registry list
- The package manager choice
- Custom search paths

## Storage

Everything is stored in Tinycast's Application Support folder, and **uninstalling an extension
removes all of it**: the extension, its storage and cache, its preferences, its support folder, its
icon choice, and its command shortcuts, favorites, aliases and learned ranking.

**Settings → Extensions → Storage** shows the size of leftover build folders, like those a crashed
install can leave behind, and offers to remove them. It works even while extensions are off, and
it's normally empty.

Tinycast never touches your own `~/Library/pnpm` or `~/.npm`.
