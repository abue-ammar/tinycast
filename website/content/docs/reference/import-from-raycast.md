---
title: Import from Raycast
description: Import your shortcuts, favorites, snippets, quicklinks and clipboard history from a Raycast export.
---

Tinycast reads Raycast's export file directly. Import it in **Settings → Backup → Raycast Export**,
or from the welcome screen the first time you open Tinycast.

## Which exports it reads

**Only Raycast v2.0 and newer.** Tinycast reads the `.rayconfig` file written by Raycast v2.0 and
later, and no other format. Check your Raycast version in **Raycast → Settings → About** before you
export.

**Raycast v1.x exports aren't supported.** Support for that format was removed in
**Tinycast v0.10.5**, along with the Raycast X beta format. If your file won't open, export it again
from a current version of Raycast.

## Steps

1. In Raycast, export your settings and data, and note the passphrase.
2. In Tinycast, go to **Settings → Backup → Raycast Export** and choose the file.
3. Enter the passphrase, select what you want to import, and import.
4. **Quit Tinycast and open it again.**

**You need to quit and reopen Tinycast after the import finishes.** Some imported settings don't take
effect in the running app until it restarts. Quit from the menu bar icon (closing the Settings window
isn't enough), then open Tinycast again.

Tinycast recognizes the file **before** you enter the passphrase, so a wrong passphrase is reported
as a wrong passphrase, not as "this is not a Raycast file".

## About the passphrase

**Raycast encrypts the export even if you never set a password.** It creates one and stores it in
your login Keychain.

You can find it in **Raycast → Settings → Extensions → Export Settings & Data**, or in Keychain
Access under the service `Raycast` and account `export_passphrase`.

**Tinycast never reads your Keychain.** You paste the passphrase yourself.

## What gets imported

| Category            | Notes                                                      |
| ------------------- | ---------------------------------------------------------- |
| Shortcuts           | App shortcuts, command shortcuts, and your Hyper key setup |
| Favorites           | From Raycast's pinned items                                |
| Aliases             | App aliases                                                |
| Clipboard history   | Text, and images whose files still exist                   |
| Snippets            | Name, text and keyword                                     |
| Quicklinks          | Name, link and the app it opens with                       |
| Emoji skin tone     | Raycast's default becomes Tinycast's Default               |
| Compact mode        | From Raycast's window mode                                 |
| Pop to root         | Only when the delay matches an option Tinycast offers      |
| Launch at login     |                                                            |
| Menu bar visibility | From Raycast's menu bar icon setting                       |

The list of apps excluded from clipboard history is imported along with Clipboard history.

If a shortcut uses a modifier Tinycast doesn't recognize, the **whole shortcut is skipped** rather
than imported as something slightly different.

## Clipboard history

Pinned text and image entries stay pinned, so they survive the configured history retention even
when their original copy dates are old. Imported pins are ordered by their original copy dates,
oldest first; unpinned entries remain subject to your retention setting.

Images are only imported if their files still exist on this Mac. The summary tells you how many were
missing.

## Snippets

Snippets are added **in their original order, without overwriting any you already have**. Snippets
that can't be read are skipped. If a name is already in use, a number is added to it, and duplicate
keywords are kept as they are.

Imported snippets are **enabled and visible in the launcher, with confirmation off**.

**Importing never turns on keyword expansion.** Only you can turn that on; see
[Backup](/docs/reference/backup#a-backup-can-never-turn-on-a-capability). The summary mentions this,
so a keyword that doesn't work yet doesn't look broken.

If the snippet files can't be written, the summary tells you, and the other categories are still
imported.

## Quicklinks

Quicklinks are added to your existing library, never replacing it, and duplicates are skipped the
same way as in a [quicklink import](/docs/launcher/quicklinks#import-and-export). Raycast's `{Query}`
becomes `{argument}`.

Importing at least one quicklink turns on the Quicklinks feature.

## Other things you can import

Two things aren't part of a `.rayconfig`, so they have their own importers:

- **Extensions.** **Settings → Extensions → Import from Raycast** copies your installed extensions.
  See [Installing extensions](/docs/extensions/installing#import-from-raycast).
- **Script commands.** **Settings → Commands → Import Raycast Scripts** turns a folder of scripts
  into custom commands. See [Commands](/docs/launcher/commands#importing-raycast-script-commands).

## Afterward

The pane has a **Quit Raycast** button for when you're ready.

Tinycast doesn't need Raycast to be installed, except to import extensions from it, since that reads
Raycast's folder.
