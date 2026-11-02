---
title: Clipboard history
description: Search the text, images, files and colors you copied, and paste them back where you were.
---

Tinycast saves what you copy, so you can find it later and paste it back into the app you were
using.

Clipboard history is the only feature that's **on** by default. To turn it off, go to
**Settings → Clipboard → Enable Clipboard History**. When it's off, nothing is recorded, the history
file closes, and the Clipboard History and Paste Sequentially commands and their shortcuts are
removed. Your existing history is kept, and **Clear history** still works.

## Opening it

- Press <kbd>tab</kbd> from the launcher (after Quick AI, if AI is on).
- Run the **Clipboard History** command, or use its global shortcut from **Settings → Clipboard**.
- Choose **Clipboard History** in the Tinycast menu bar menu.

The footer shows where a paste will go, like "Paste to Notes".

## Actions

| Action                     | Shortcut                                            |
| -------------------------- | --------------------------------------------------- |
| Paste                      | <kbd>return</kbd>                                   |
| Copy to Clipboard          | <kbd>⌘</kbd><kbd>return</kbd>                       |
| Paste as Plain Text        | <kbd>⌃</kbd><kbd>⌘</kbd><kbd>return</kbd>           |
| Paste and Keep Window Open | <kbd>⌥</kbd><kbd>return</kbd>                       |
| Filter by type             | <kbd>⌘</kbd><kbd>P</kbd>                            |
| Pin / Unpin Entry          | <kbd>⌘</kbd><kbd>.</kbd>                            |
| Edit Entry                 | <kbd>⌘</kbd><kbd>E</kbd>                            |
| Copy Text, on an image     | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>T</kbd>                |
| Show in Finder             | <kbd>⌘</kbd><kbd>F</kbd>                            |
| Paste a pinned entry       | <kbd>⌘</kbd><kbd>1</kbd> … <kbd>⌘</kbd><kbd>0</kbd> |
| Delete Entry               | <kbd>⌃</kbd><kbd>X</kbd>                            |
| Delete All Entries         | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>X</kbd>                |

The **Default action** setting swaps <kbd>return</kbd> and <kbd>⌘</kbd><kbd>return</kbd>. If you set
it to **Copy to Clipboard**, <kbd>return</kbd> copies and <kbd>⌘</kbd><kbd>return</kbd> pastes.
If you set it to **Paste as Plain Text**, <kbd>return</kbd> pastes plain text and
<kbd>⌃</kbd><kbd>⌘</kbd><kbd>return</kbd> pastes normally. Double-clicking and the number shortcuts
follow the same setting. <kbd>⌥</kbd><kbd>return</kbd> always pastes.

**Paste as Plain Text** pastes only the text. For a file, that's its path instead of the file. An
image has no text, so it always pastes as an image.

**Edit Entry** opens a text entry for editing. <kbd>⌘</kbd><kbd>return</kbd> saves the change to
the same entry and puts it on the clipboard. <kbd>return</kbd> starts a new line, and <kbd>esc</kbd>
cancels. An entry can be up to 32,000 characters long.

**Copy Text** reads the text in a copied image, or an image file, and puts it on the clipboard. The
text is recognized on your Mac. If the image has no text, you see **No text found**.

Pasting needs the [Accessibility permission](/docs/permissions).

You can also **drag any row** into another app. Dragging always copies, so the entry stays in your
history. When you drop it, the palette closes, the same as after a paste.

## Paste Sequentially

Give **Paste Sequentially** a shortcut in **Settings → Clipboard** to paste a series of copies one
at a time without opening the palette. If you copy `A`, then `B`, then `C`, three presses paste `C`,
`B`, then `A` into the frontmost field, so you can move between fields as you go.

It works with text, images and files, and doesn't change the order of your history. Copying
something new, or waiting a minute between presses, starts again from the newest entry. After the
oldest entry, it shows **Nothing left to paste** instead of starting over.

## What it keeps

- **Text**, with a preview. Text longer than 32,000 characters isn't recorded.
- **Images**, like screenshots, saved as PNG files. When you paste an image, a terminal receives the
  path of its saved file, because terminals ignore image data.
- **Files you copy in Finder.** Tinycast saves a reference to the file in its current location, not
  a copy of the file. Up to 32 files per copy are recorded. When you paste, apps receive the file
  itself, and text fields receive its path.
- **Colors.** A copied `#FF5733`, `rgb(…)`, `hsl(…)` or `oklch(…)` is shown as a color swatch.

If a file has been moved or deleted since you copied it, it stays in your history, because its old
location can still be useful. Pasting it shows a message instead of failing silently. For file
entries, <kbd>⌘</kbd><kbd>K</kbd> also offers **Show in Finder**, **Open** and **Copy Path**.

You can play video and audio files in the preview. Nothing plays until you press play.

## Filtering by type

<kbd>⌘</kbd><kbd>P</kbd> opens a filter to the right of the search field. There are seven options,
and every entry belongs to exactly one:

**All Types** · **Text Only** · **Images Only** · **Files Only** · **Colors Only** · **Links Only** ·
**Emails Only**

Copied URLs count as links rather than text, and colors aren't text either, so _Text Only_ shows
regular text.

Each filter has its own empty message, so "Clipboard history is empty" never appears when the
history only looks empty because of a filter. The filter stays available on an empty list, so you
can always switch back.

Links and emails are detected from the text each time and never stored separately. Text over 2,048
bytes, or text containing a space, counts as plain text. A bare domain must be lowercase and end in
a common domain ending, so `Safari.app`, `report.pdf` and `index.html` stay text.

## Pinning

<kbd>⌘</kbd><kbd>.</kbd> pins the selected entry.

- Pinned entries appear in a **Pinned** section at the top, in the order you pinned them.
- They come first in both the full list and your search results.
- <kbd>⌘</kbd><kbd>1</kbd> to <kbd>⌘</kbd><kbd>9</kbd>, then <kbd>⌘</kbd><kbd>0</kbd>, act on the
  first ten visible pinned entries.
- **Pinned entries are never removed by the retention limit.** **Clear history** and **Delete All
  Entries** keep them too. To remove a pinned entry, use **Delete Entry**.
- Pasting a pinned entry doesn't change its position.
- **Unpinning an entry makes it the newest entry**, instead of returning it to an old date group.

## Searching text inside images and PDFs

**Search text in images and PDFs** is **off** by default. When you turn it on, Tinycast reads the
text in your copied images, image files and PDFs, so searching for a word in a screenshot finds it.

- Text recognition happens **on your Mac**, one item at a time, while you aren't typing or moving
  the mouse.
- It runs in a separate helper process, so Tinycast itself stays light.
- It handles files up to 32 MB and the first 64 pages of a PDF.
- The recognized text is only used for search. Pasting still gives you the original item.
- Turning the setting off stops recognition. Text that was already recognized is kept and reused if
  you turn it back on.

This setting isn't included in [backups](/docs/reference/backup).

## Settings

**Settings → Clipboard**

| Setting                        | Options                                                           | Default                    |
| ------------------------------ | ----------------------------------------------------------------- | -------------------------- |
| Enable Clipboard History       | On · Off                                                          | **On**                     |
| Clipboard History shortcut     | Any shortcut                                                      | None                       |
| Paste Sequentially shortcut    | Any shortcut                                                      | None                       |
| Keep history for               | 1 Day · 1 Week · 1 Month · 3 Months · 6 Months · 1 Year · Forever | **3 Months**               |
| Search text in images and PDFs | On · Off                                                          | **Off**                    |
| Default action                 | Paste · Copy to Clipboard · Paste as Plain Text                   | **Paste**                  |
| Excluded Applications          | A list of apps                                                    | Keychain Access, Passwords |
| Clear history                  | Removes every entry except pinned ones                            | None                       |

**Excluded Applications** includes Keychain Access and Passwords by default, so Tinycast never
records what you copy from them. You can add your own apps. Copies that apps mark as confidential
are also skipped.

## Limits worth knowing

History is stored in `clipboard.sqlite3`, with images next to it, in Tinycast's Application Support
folder. Because it isn't in Caches, Time Machine backs it up and macOS never clears it on its own.

- Tinycast checks the clipboard twice a second. It recognizes and skips its own pastes, so pasting
  from Tinycast never adds a new entry.
- The newest **1,000** entries are kept in memory. Search also covers older entries.
- **Search needs at least three characters** to use the full index. Shorter searches only look
  through the recent entries in memory.
- A search returns at most 200 matches before the type filter is applied, so a narrow filter on a
  broad search can show fewer results than your history contains.
