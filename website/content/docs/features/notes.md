---
title: Notes
description: Plain Markdown files in one floating editor. No database, no frontmatter, no sidecar files.
---

Notes is a collection of plain Markdown files, as many as you like, edited in one floating window.

**Settings → Notes** holds the switch. It ships **off**, and turning it on does not create the folder
or write anything until you make a note.

## Commands

Three commands, each with its own optional global shortcut in **Settings → Notes**:

| Command          | Does                                                     |
| ---------------- | -------------------------------------------------------- |
| **Show Notes**   | Opens your last note. Press it again to hide the window. |
| **Create Note**  | Makes a new Untitled note and opens it                   |
| **Search Notes** | Opens the window with the note switcher ready to type in |

## In the window

The title bar holds three buttons: **Create**, **Browse** and **Open Folder**.

| Key                           | Does                                        |
| ----------------------------- | ------------------------------------------- |
| <kbd>⌘</kbd><kbd>N</kbd>      | Create a note                               |
| <kbd>⌘</kbd><kbd>P</kbd>      | Open the switcher, or jump back into it     |
| <kbd>⌘</kbd><kbd>O</kbd>      | Open the Notes folder in Finder             |
| <kbd>⌘</kbd><kbd>W</kbd>      | Hide the window                             |
| <kbd>esc</kbd>                | Close the switcher, then hide the window    |
| <kbd>⌘</kbd><kbd>delete</kbd> | Move the selected switcher row to the Trash |

<kbd>⌘</kbd><kbd>Q</kbd> does nothing here, so **no key press over Notes can quit Tinycast** by
accident.

## Files

Notes live in Tinycast's Application Support folder:

```
~/Library/Application Support/com.tinycast.app/Notes/
```

**One `.md` file is one note, and its file name is its title.** There is no frontmatter, no hidden
ID, no database and no sidecar file. What you see is the file.

Only files directly in that folder count. Subfolders, hidden files and links are ignored. Notes are
sorted by when they changed, newest first.

New notes are named `Untitled.md`, then `Untitled 2.md`, and so on. **Until you rename one, it shows
its first line as the title**, so a list of Untitled notes is still easy to scan. Markdown marks like
`#`, `- [ ]` and `**` are dropped from that title.

Names are compared without case or accents, so `plán` next to `Plan` becomes `plán 2.md`. A note
never clashes with itself, so you can rename one just to change its case or accents.

## The editor

**Markdown renders as you write.** Headings, bold, italic, strikethrough, inline code, links, lists,
tasks, quotes, code blocks and rules all show formatted. The line you are on shows its Markdown so you
can edit it, and every other line stays rendered. The file itself never changes: what is saved, searched
and copied is the plain Markdown you typed.

Images and highlighting inside code blocks are not rendered; they stay as text. Tables stay as text
too, shown in a fixed-width font with nothing styled inside them, so their columns stay readable.

- **Click a checkbox** to tick or untick a task. The caret stays where it was.
- **Click a link** to open it in your browser. Click right at the edge of a link to edit it instead.
- **Return** continues a list, and ends it on an empty item. **Tab** and **Shift-Tab** nest items.
- Type `[] ` at the start of a line to start a task.
- Paste a web address over selected text to turn that text into a link.

| Key                                                              | Does                 |
| ---------------------------------------------------------------- | -------------------- |
| <kbd>⌘</kbd><kbd>B</kbd>                                         | Bold                 |
| <kbd>⌘</kbd><kbd>I</kbd>                                         | Italic               |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>X</kbd>                             | Strikethrough        |
| <kbd>⌘</kbd><kbd>E</kbd>                                         | Inline code          |
| <kbd>⌘</kbd><kbd>K</kbd>                                         | Link                 |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>7</kbd>                             | Numbered list        |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>8</kbd>                             | Bullet list          |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>9</kbd>                             | Task list            |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>1</kbd>, <kbd>2</kbd>, <kbd>3</kbd> | Heading 1, 2, 3      |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>0</kbd>                             | Back to a plain line |

Prefer to see the raw text? Turn off **Render Markdown** in **Settings → Notes**. The editor then shows
every mark as typed, and Return, Tab and these keys behave like any plain text field.

Typing, selection, copy and paste, Find, emoji, input methods and undo all behave like any Mac text
field. An empty note shows **Start writing…**, and the footer counts characters.

[Snippets](/docs/features/snippets) expand right into the editor, and undo takes them back.

## The switcher

The switcher drops down from the title bar. With nothing typed, it lists notes by recency. Type and
it searches titles and note text, after a 120 ms pause, showing up to **200** results.

Each row offers VoiceOver actions to open, rename and move that note to the Trash.

## Saving, and the one real caveat

Changes save automatically 300 ms after you stop typing.

**A save overwrites whatever is on disk.** Tinycast does not watch the folder. If you edit the note
that is _open in Tinycast_ in another app, that edit is lost at the next autosave.

<kbd>⌘</kbd><kbd>O</kbd> invites exactly this, and it is the trade for having no database.

Every _other_ change from outside is picked up, because showing the window reads the folder again
first. A note you add or edit elsewhere shows up as expected.

Quitting waits for the last save, but never blocks the quit.

## The window

You choose the size, and macOS remembers it. You can delete every note; the window shows an empty
state and Create Note still works.

Hiding the window takes you back to the app you came from, but only if that app is still in front.
If you already moved on, you stay where you are.
