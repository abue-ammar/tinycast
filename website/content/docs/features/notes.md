---
title: Notes
description: Plain Markdown files in one floating editor, with no database or extra files.
---

Notes is a collection of plain Markdown files, as many as you want, edited in one floating window.

Turn it on in **Settings → Notes**. It's **off** by default, and turning it on doesn't create the
folder or write anything until you make your first note.

## Commands

There are three commands, and each can have its own global shortcut in **Settings → Notes**:

| Command          | Does                                                     |
| ---------------- | -------------------------------------------------------- |
| **Show Notes**   | Opens your last note. Press it again to hide the window. |
| **Create Note**  | Creates a new Untitled note and opens it                 |
| **Search Notes** | Opens the window with the note switcher ready for typing |

## In the window

The title bar has three buttons: **Create**, **Browse** and **Open Folder**.

| Key                           | Does                                        |
| ----------------------------- | ------------------------------------------- |
| <kbd>⌘</kbd><kbd>N</kbd>      | Create a note                               |
| <kbd>⌘</kbd><kbd>P</kbd>      | Open the switcher, or return to it          |
| <kbd>⌘</kbd><kbd>O</kbd>      | Open the Notes folder in Finder             |
| <kbd>⌘</kbd><kbd>W</kbd>      | Hide the window                             |
| <kbd>esc</kbd>                | Close the switcher, then hide the window    |
| <kbd>⌘</kbd><kbd>delete</kbd> | Move the selected switcher row to the Trash |

<kbd>⌘</kbd><kbd>Q</kbd> does nothing in Notes, so you can't quit Tinycast by accident while
writing.

## Files

Notes are stored in Tinycast's Application Support folder:

```
~/Library/Application Support/com.tinycast.app/Notes/
```

**Each note is one `.md` file, and the file name is the note's title.** There's no frontmatter,
hidden ID, database or extra file. The file is the note.

Only files directly in that folder are included. Subfolders, hidden files and links are ignored.
Notes are sorted by when they were last changed, newest first.

New notes are named `Untitled.md`, then `Untitled 2.md`, and so on. **Until you rename a note, its
first line is shown as the title**, so a list of untitled notes is still easy to scan. Markdown
symbols like `#`, `- [ ]` and `**` are removed from that title.

File names are compared without case or accents, so a new `plán` next to `Plan` becomes
`plán 2.md`. A note never conflicts with itself, so you can rename a note just to change its case or
accents.

## The editor

**Markdown is formatted as you write.** Headings, bold, italic, strikethrough, inline code, links,
lists, tasks, quotes, code blocks and horizontal rules are all shown formatted. The line you're
editing shows its Markdown symbols, and every other line stays formatted. The file itself doesn't
change: what's saved, searched and copied is the plain Markdown you typed.

Images and syntax highlighting in code blocks aren't rendered; they appear as text. Tables also
appear as text, in a fixed-width font without other formatting, so their columns stay aligned.

- **Click a checkbox** to check or uncheck a task. The text cursor stays where it was.
- **Click a link** to open it in your browser. To edit the link instead, click right at its edge.
- **Return** continues a list, and ends it on an empty item. **Tab** and **Shift-Tab** indent and
  outdent items.
- Type `[] ` at the start of a line to start a task.
- Paste a web address over selected text to turn the text into a link.

| Key                                                              | Does                        |
| ---------------------------------------------------------------- | --------------------------- |
| <kbd>⌘</kbd><kbd>B</kbd>                                         | Bold                        |
| <kbd>⌘</kbd><kbd>I</kbd>                                         | Italic                      |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>X</kbd>                             | Strikethrough               |
| <kbd>⌘</kbd><kbd>E</kbd>                                         | Inline code                 |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd>                             | Code block                  |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>B</kbd>                             | Quote                       |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>T</kbd>                             | Show the formatting buttons |
| <kbd>⌘</kbd><kbd>K</kbd>                                         | Link                        |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>7</kbd>                             | Numbered list               |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>8</kbd>                             | Bullet list                 |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>9</kbd>                             | Task list                   |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>1</kbd>, <kbd>2</kbd>, <kbd>3</kbd> | Heading 1, 2, 3             |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>0</kbd>                             | Back to a plain line        |

If you'd rather see the raw text, turn off **Render Markdown** in **Settings → Notes**. The editor
then shows every symbol as you typed it, and Return, Tab and the shortcuts above behave like they do
in any plain text field.

### The formatting bar

There's a round button at the bottom right of each note. Click it, or press
<kbd>⌥</kbd><kbd>⌘</kbd><kbd>T</kbd>, and a button for each of the shortcuts above appears, along
with a heading menu. Click a button to format the selection or the word at the cursor, and click a
highlighted button to remove that formatting. Hover over a button to see its shortcut. Tinycast
remembers whether you left the bar open. When the window is narrow, the character count moves aside
to make room for the buttons.

To hide it, turn off **Show Formatting Bar** in **Settings → Notes**. The shortcuts still work. The
bar is also hidden while Render Markdown is off.

Typing, selecting, copy and paste, Find, emoji, input methods and undo all work like they do in any
Mac text field. An empty note shows **Start writing…**, and the character count appears below the
note.

[Snippets](/docs/features/snippets) expand directly in the editor, and you can undo them.

## The switcher

The switcher opens below the title bar. With nothing typed, it lists notes by when you last changed
them. When you type, it searches titles and note text after a 120 ms pause and shows up to **200**
results.

Each row has VoiceOver actions to open, rename and move that note to the Trash.

## Saving, and one important caveat

Changes are saved automatically 300 ms after you stop typing.

**Saving overwrites the file on disk.** Tinycast doesn't watch the folder for changes, so if you
edit the note that's _open in Tinycast_ in another app, that edit is lost at the next autosave.

<kbd>⌘</kbd><kbd>O</kbd> makes this easy to do by accident. It's the tradeoff for storing notes as
plain files instead of in a database.

When you reopen the window, Tinycast reads the folder again and reloads the active note if it has no
unsaved changes. Notes you add or edit elsewhere appear as expected. An unsaved draft is kept,
including after a failed save. Reloading changed contents clears that note's undo history; reopening
unchanged contents keeps it.

When you quit, Tinycast waits for the last save to finish, but it never stops the app from quitting.

## The window

You choose the window's size, and macOS remembers it. You can delete every note; the window then
shows an empty state, and Create Note still works.

Hiding the window returns you to the app you were using, but only if that app is still in front. If
you've already switched to something else, you stay there.
