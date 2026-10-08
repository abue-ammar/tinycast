---
title: File search
description: Find files and folders through the Spotlight index, with a preview and no file permissions.
---

Search file and folder names in the folders you choose, using Spotlight or an already-running fsearch daemon.

Turn it on in **Settings → File Search**. It's **off** by default. While it's off, there's no
command and Tinycast doesn't query Spotlight.

Open it with the **Search Files** command, its own global shortcut, or the **Search Files** row under
"Use … with" at the bottom of any launcher search. The last option opens with your text already
typed.

## No permissions needed

Tinycast doesn't ask for **any file permissions** for this feature. Hidden files and the contents of
app bundles are always excluded, and no setting can include them. That's what lets the feature work
without permissions.

If Spotlight hasn't indexed something, you get fewer results instead of a Full Disk Access prompt.

## Optional fsearch

If you install and start [fsearch](https://github.com/noahdunnagan/fsearch) separately, Tinycast can use
it for faster, typo-tolerant filename searches in **All Types**. Tinycast does not install or start an
indexer itself. fsearch maintains its own disk index and uses additional background memory and CPU.

Recent files, type filters, very short searches and non-ASCII queries still use Spotlight. The two
engines match differently: fsearch adds fuzzy and path matching, while Spotlight provides language
folding and metadata. If fsearch is unavailable, Tinycast uses Spotlight automatically. Your configured
folders and ignore rules still apply. fsearch's own permissions and cloud-file coverage can differ
from Spotlight's, so it may not find every file Spotlight knows about.

## The screen

With nothing typed, the list shows **Recently Used**: files in your search scopes that you opened in
the last 30 days or changed in the last 3 days. This comes from macOS's own records; Tinycast doesn't
keep its own history.

When you type, the list changes to **Results**. Each row shows the file's icon and name. Folders also
show their parent folder's name, dimmed, which helps when many folders share a name like `src`.

The right side previews the selected file: the file itself, followed by its name, location, type,
size and dates. You can play video and audio there. Nothing plays until you press play.

### Filtering by type

<kbd>⌘</kbd><kbd>P</kbd>, or the **All Types** button, narrows the search:

**All Types** · **Folders** · **Documents** · **Images** · **Audio** · **Videos** · **Archives**

The filter changes what Tinycast asks Spotlight for, so it never hides matches that were already cut
off by the result limit. It resets each time you open the palette.

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

Your home folder means its **visible** folders, plus `Library/CloudStorage` and your iCloud Drive.
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

Every word you type must appear in the file name, in any order. `annual report` finds
"Report – annual 2025.pdf".

Spotlight returns at most **1,000** matches, and at most **200** rows are shown after filtering.
Tinycast waits 120 ms after you stop typing before it searches, so it doesn't start a new search for
every letter.

## Messages you might see

| You see                          | It means                                     |
| -------------------------------- | -------------------------------------------- |
| Type to search files and folders | Nothing recent in your search scopes         |
| No files found                   | The search finished without a match          |
| No images found                  | The same, with the Images filter on          |
| File search is unavailable       | Tinycast couldn't get results from Spotlight |
