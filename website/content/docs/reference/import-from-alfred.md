---
title: Import from Alfred
description: Import your shortcuts, search folders, snippets, bookmarks, web searches and runnable workflows from an Alfred preferences package.
---

Tinycast reads Alfred's preferences package directly. Import it in **Settings → Backup → Alfred
Preferences**.

## Where the package is

Alfred keeps everything in one folder named `Alfred.alfredpreferences`. Find it in
**Alfred → Preferences → Advanced → Reveal in Finder**.

By default it sits in `~/Library/Application Support/Alfred/`. If you use Alfred's sync, it sits in
the sync folder you chose instead — either way, **Reveal in Finder** opens the right one.

Tinycast reads the folder as it is. There is no passphrase, and Tinycast never touches your
Keychain.

## Steps

1. In Alfred, open **Preferences → Advanced → Reveal in Finder**.
2. In Tinycast, go to **Settings → Backup → Alfred Preferences** and choose the folder.
3. Select what you want to import, and import.
4. Importing commands asks once first, because they run shell code.

If a Mac's settings differ, Tinycast uses the most recently written one — the current Mac's.

## What gets imported

| Category            | Notes                                                             |
| ------------------- | ----------------------------------------------------------------- |
| Shortcuts           | Alfred's window chord and its clipboard history chord             |
| Search scope        | The folders Alfred's launcher indexes, from your newest Mac        |
| Snippets            | Every collection, with Alfred's keyword prefix and suffix applied |
| Bookmarks & searches | Your bookmark pages, your custom searches and Alfred's own ones  |
| Workflows           | Only the workflows Tinycast can actually run — see below           |

**Clipboard history is not imported.** Alfred keeps it outside its preferences package, in
`~/Library/Application Support/Alfred/Clipboard History/`, so there is nothing in the folder to read.

Alfred also has no window management, no favourites list and no "paste as plain text" preference, so
none of those carry over. Your own Tinycast window layouts, halves shortcuts and window rooms are
untouched either way.

## Snippets

Snippets are added **without overwriting any you already have**, in their collection order. A
collection's own keyword prefix and suffix come with it, so a keyword that only worked with `!!` in
Alfred still works.

Alfred's placeholders are translated into Tinycast's: `{date:yyyy-MM-dd}` keeps working as a date, and
the clipboard and cursor placeholders do too.

**Importing never turns on keyword expansion.** Only you can turn that on; see
[Backup](/docs/reference/backup#a-backup-can-never-turn-on-a-capability). The summary mentions this.

## Bookmarks and web searches

Bookmark **URLs** become quicklinks. Alfred's own bookmark pages also launch applications, open system
preference panes and drive iTunes, and those aren't links, so they are skipped rather than imported as
something that does something else.

Your **custom searches** come across as they are. Alfred's **built-in searches** store only a keyword,
so Tinycast supplies the search URL for each one it knows. If you use one Tinycast has no URL for, its
name is listed in the summary after the import rather than being dropped quietly.

Every imported search keeps its keyword: it lands in the quicklink's keyword field, so `gi query`
searches Google Images straight from the launcher. Type the name to find it, or the keyword to
invoke it.

Importing at least one quicklink turns on the Quicklinks feature.

## Workflows

An Alfred workflow is a graph of connected objects. A Tinycast custom command is one script, so a
workflow comes across **only when it is exactly that shape**:

- it isn't disabled,
- it has exactly one keyword or hotkey,
- and that trigger runs exactly one bash script, written inline rather than kept in a file.

A keyword becomes part of the command's name, and a hotkey becomes the command's shortcut. The
summary tells you how many workflows were left out.

Imported commands are **added to your library, never replacing it**, and Tinycast asks for
confirmation before importing any, because a custom command runs shell code.

## Afterward

The pane has a **Quit Alfred** button for when you're ready, so Alfred's own chords stop clashing.

Tinycast doesn't need Alfred to be installed.
