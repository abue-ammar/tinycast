---
title: File search
description: Find files and folders by name in a few milliseconds, with a preview and live updates.
---

Search file and folder names in the folders you choose. Tinycast keeps its own list of those names in
memory and searches it as you type, so results arrive in a few milliseconds.

Turn it on in **Settings → File Search**. It's **off** by default. While it's off, there's no
command, and Tinycast doesn't read or watch any of your folders.

Open it with the **Search Files** command, its own global shortcut, or the **Search Files** row under
"Use … with" at the bottom of any launcher search. The last option opens with your text already
typed.

## Folder access

The first time you type a search, Tinycast reads the names in your search scopes. That takes about a
second, and the screen says **Indexing files…** meanwhile. After that, Tinycast watches those folders,
so a file you save or delete shows up or disappears within a couple of seconds.

macOS protects Desktop, Documents, Downloads and iCloud Drive, so it asks once whether Tinycast may
read each one. If you say no, that folder is left out and everything else still works. Tinycast never
asks for Full Disk Access.

The list of names stays in memory only. Nothing is written to disk, and it's dropped when you quit,
turn the feature off or change your scopes.

Hidden files, apps, the contents of packages (like a Photos library or a `.pages` document) and
`~/Library` are always left out, and no setting can include them. A package itself is still listed.
Tinycast never downloads iCloud files to search them.

## The screen

With nothing typed, the list shows **Recently Used**: files in your search scopes that you opened in
the last 30 days or changed in the last 3 days. This comes from macOS's own Spotlight records;
Tinycast doesn't keep its own history.

When you type, the list changes to **Results**. Each row shows the file's icon and name. Folders also
show their parent folder's name, dimmed, which helps when many folders share a name like `src`.

The right side previews the selected file: the file itself, followed by its name, location, type,
size and dates. You can play video and audio there. Nothing plays until you press play.

### Filtering by type

<kbd>⌘</kbd><kbd>P</kbd>, or the **All Types** button, narrows the search:

**All Types** · **Folders** · **Documents** · **Images** · **Audio** · **Videos** · **Archives**

The filter is part of the search, so it never hides matches that were already cut off by the result
limit. It resets each time you open the palette.

## Actions

| Action                  | Shortcut                             |
| ----------------------- | ------------------------------------ |
| Open File / Open Folder | <kbd>return</kbd>                    |
| Show in Finder          | <kbd>⌘</kbd><kbd>return</kbd>        |
| Quick Look              | <kbd>⌘</kbd><kbd>Y</kbd>             |
| Copy File               | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Paste File to …         | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd> |
| Copy Name               | <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Copy Path               | <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Move to Trash           | <kbd>⌃</kbd><kbd>X</kbd>             |

- **Quick Look** opens a large preview inside the palette and plays media right away.
  <kbd>esc</kbd> or **Close** dismisses it.
- **Copy File** copies the file itself to the clipboard, so you can paste it into Finder or Mail.
- **Paste File to …** pastes the file into the app you opened the palette over.
- **Copy Name** and **Copy Path** keep the palette open, so you can copy several in a row.
- **Move to Trash** doesn't ask for confirmation, because you can always restore files from the
  Trash.

Copies made here appear in your [clipboard history](/docs/features/clipboard) like any other copy.

## Search scopes

Set these in **Settings → File Search → Search Scopes**. By default, Tinycast searches your home
folder.

Your home folder means everything visible in it, plus `Library/CloudStorage` and your iCloud Drive.
**Tinycast never adds `~/Library` by itself.** If you add a folder inside it, Tinycast searches that
folder.

**An empty scope list searches nothing.** Tinycast doesn't fall back to your home folder.

Scopes are saved with your home folder written as `~`, so a backup still works on another Mac.

## Ignore patterns

Set these in **Settings → File Search → Ignore Patterns**. There are three kinds:

| Pattern          | Checked against    | Example          |
| ---------------- | ------------------ | ---------------- |
| Plain word       | Any folder or name | `node_modules`   |
| With `*` `?` `[` | Any folder or name | `*.tmp`          |
| Containing `/`   | The whole path     | `**/[Cc]ache/**` |

Matching isn't case-sensitive, and `*` also matches `/`, so a `**/…/**` pattern works as written.

The list only shows patterns you add. Six built-in rules always apply as well.

## How search works

Every word you type must match, in any order. `annual report` finds "Report – annual 2025.pdf".
Letters only need to appear in order, so `rprt` finds it too, and a word of five letters or more
forgives one typo. Case and accents don't matter: `resume` finds "Résumé.pdf".

A word can also match a folder above the file, as long as another word matches the name itself.
`tinycast palette` finds `Palette.swift` inside a `Tinycast` folder. Exact names, names that start
with what you typed, folders that usually hold your work and recently changed files rank higher.

| Type             | To find                                             |
| ---------------- | --------------------------------------------------- |
| `'word`          | names containing exactly `word`                     |
| `^word`, `word$` | names starting or ending with `word`                |
| `!word`          | anything _without_ `word` in its name or folders    |
| `"two words"`    | the two words together                              |
| `ext:pdf,md`     | those file extensions                               |
| `kind:folder`    | folders only (`kind:file` for files)                |
| `in:Documents`   | things inside that folder (relative to home)        |
| `mtime:<7d`      | things changed in the last 7 days (`>7d`, `1d..7d`) |

At most **200** rows are shown. Tinycast waits 120 ms after you stop typing before it searches, so it
doesn't start a new search for every letter.

## Messages you might see

| You see                          | It means                                                 |
| -------------------------------- | -------------------------------------------------------- |
| Indexing files…                  | Tinycast is reading your folders for the first search    |
| Type to search files and folders | Nothing recent in your search scopes                     |
| No files found                   | The search finished without a match                      |
| No images found                  | The same, with the Images filter on                      |
| File search is unavailable       | Tinycast couldn't get the Recently Used list from macOS  |
