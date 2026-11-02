---
title: File search
description: Find files and folders instantly from a private index on your Mac. Needs Full Disk Access.
---

Search file and folder names in the folders you choose. Tinycast builds its own index of those
folders and keeps it current as files change, so results appear as you type. Spotlight isn't used.

Turn it on in **Settings → File Search**. It's **off** by default. While it's off, there's no
command and no index on disk.

Open it with the **Search Files** command, its own global shortcut, or the **Search Files** row under
"Use … with" at the bottom of any launcher search. The last option opens with your text already
typed.

## Full Disk Access

**File Search needs Full Disk Access, and indexes nothing without it.** Tinycast reads your folders
directly to build the index, and macOS protects many of them, so it needs this access to list them.

Tinycast **checks** for access but **never asks** for it. **Settings → File Search** shows
**Granted** or **Required**, with a button that opens System Settings → Privacy & Security → Full Disk
Access. Turn on Tinycast there. If it isn't listed, click **+** and choose Tinycast from
Applications. Indexing starts on its own once access is granted. If the pane still says
**Required**, quit and reopen Tinycast.

What the index holds, and where it goes:

- **Names, folders and dates only.** It stores each file's name, where it is and when it last
  changed. It never stores what's inside a file.
- **It stays on your Mac.** File Search makes no network requests.
- **Off means gone.** Turning File Search off deletes the index.
- **It never downloads.** iCloud Drive and other cloud files that aren't on your Mac are listed as
  they are, without downloading them.

See [Permissions](/docs/permissions#full-disk-access) for what else Full Disk Access is used for.

## The screen

With nothing typed, the list shows **Recent**: the 20 files in your home folder that changed most
recently. Hidden files, `~/Library` and app bundles are left out.

When you type, the list changes to **Results**. Each row shows the file's icon and name. Folders also
show their parent folder's name, dimmed, which helps when many folders share a name like `src`.

The right side previews the selected file: the file itself, followed by its name, location, type,
size and dates. You can play video and audio there. Nothing plays until you press play.

### Filtering by type

<kbd>⌘</kbd><kbd>P</kbd>, or the **All Types** button, narrows the search:

**All Types** · **Folders** · **Documents** · **Images** · **Audio** · **Videos** · **Archives**

The filter is applied during the search, so it never hides matches that were already cut off by the
result limit. It resets each time you open the palette.

## Actions

| Action                                   | Shortcut                             |
| ---------------------------------------- | ------------------------------------ |
| Open File / Open Folder                  | <kbd>return</kbd>                    |
| Show in Finder                           | <kbd>⌘</kbd><kbd>return</kbd>        |
| Share…                                   |                                      |
| Copy File                                | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Paste File to …                          | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd> |
| Copy Name                                | <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Copy Path                                | <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Add to Favorites / Remove from Favorites | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>F</kbd> |
| Move to Trash                            | <kbd>⌃</kbd><kbd>X</kbd>             |

- **Share…** opens the macOS share menu for AirDrop, Mail, Messages and more. The palette stays
  open beside it.
- **Copy File** copies the file itself to the clipboard, so you can paste it into Finder or Mail.
- **Paste File to …** pastes the file into the app you opened the palette over.
- **Copy Name** and **Copy Path** keep the palette open, so you can copy several in a row.
- **Add to Favorites** puts the file or folder in the launcher's
  [Favorites](/docs/launcher/favorites), next to your apps.
- **Move to Trash** doesn't ask for confirmation, because you can always restore files from the
  Trash.

Copies made here appear in your [clipboard history](/docs/features/clipboard) like any other copy.

You can also **drag any row** into another app, like a Finder window or an upload field. Dragging
always copies, so the original file stays where it is.

## In the launcher

Turn on **Show in launcher**, under the File Search switch, to see files in launcher searches too.
It's **off** by default.

When your search has three or more characters, a **Files** section lists up to five matches. It sits
below the apps and commands, so <kbd>return</kbd> still opens the top result. Each row shows the
name, the folder it's in, and whether it's a file or a folder. Matching favorite files come first.

The rows have the same actions as this screen. To see every match, choose the **Search Files** row
under "Use … with".

## Search scopes

Set these in **Settings → File Search → Search Scopes**. **Only the folders listed here are
indexed.** By default, that's your home folder.

Everything inside a scope is indexed, including hidden files and the contents of app bundles. Those
rank below your own files, and [ignore patterns](#ignore-patterns) leave out what you never want.

**An empty scope list indexes nothing.** Tinycast doesn't fall back to your home folder. A folder
inside another scope is already covered, so you don't need to add it. Other disks are never entered
unless you add them as a scope.

Scopes are saved with your home folder written as `~`, so a backup still works on another Mac.

## Ignore patterns

Set these in **Settings → File Search → Ignore Patterns**. A matching folder, and everything in it,
is skipped while indexing. There are three kinds:

| Pattern                       | Checked against    | Example        |
| ----------------------------- | ------------------ | -------------- |
| Plain word                    | Any folder or name | `node_modules` |
| With `*` `?` `[`              | Any folder or name | `*.tmp`        |
| Containing `/`, or `~/` first | The whole path     | `~/Movies`     |

Matching isn't case-sensitive, and `*` also matches `/`, so a `**/…/**` pattern works as written.
**Add Folder…** adds a folder you pick as a path pattern.

The list starts with built-in rules that skip what a search for your own files rarely wants:

- Build and dependency folders, like `node_modules`, `.git`, `build` and `DerivedData`.
- The Photos library, the Trash, and the `~/.cache` and `~/.npm` caches.
- The busiest parts of `~/Library`: `Application Support`, `Caches`, `Containers`, `Developer`,
  `Group Containers` and `Mail`.

You can remove any of them. **Restore Defaults** brings them all back.

Changing a scope or a pattern rebuilds the index. Search keeps using the old index until the new one
is ready.

## The index

**Settings → File Search → Indexed Items** shows how many items are indexed and when the index was
built. **Rebuild Index** builds it again from scratch.

The first build reads every folder in your scopes once. After that, Tinycast watches those folders
and updates only what changed. The build runs in a separate helper process, so it uses extra memory
only while it runs.

## How search works

Every word you type must appear in the file name, in any order. `annual report` finds
"Report – annual 2025.pdf". Matching ignores case and accents.

The best matches come first: an exact name, then names that start with what you typed. Files in your
home folder rank above hidden files, `~/Library` and the contents of app bundles. At most **200**
results are shown.

## Messages you might see

| You see                          | It means                                                         |
| -------------------------------- | ---------------------------------------------------------------- |
| Full Disk Access required        | Tinycast can't index yet. Press return to open the settings pane |
| Indexing your disk…              | The first build is running. Results appear when it finishes      |
| Couldn't build the file index    | The build failed. Try **Rebuild Index** in Settings              |
| Type to search files and folders | Nothing recent in your search scopes                             |
| No files found                   | The search finished without a match                              |
| No images found                  | The same, with the Images filter on                              |
