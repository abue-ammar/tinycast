---
title: Backup & restore
description: Save your setup to one file, choose what goes in and what comes back, and what a backup will never do.
---

**Settings → Backup**

A backup is one `.tinycast` file. You tick what goes into it, and you tick again what comes back out
when you import. The two choices are separate, so a file with everything in it can still restore only
your snippets.

| Category             | What travels                                                                            |
| -------------------- | --------------------------------------------------------------------------------------- |
| Settings & Shortcuts | Shortcuts, custom commands, quicklinks, window layouts, rooms, favorites, aliases, preferences |
| Clipboard History    | Text and image clips with their images, and references to copied files                  |
| Snippets             | Your snippet Markdown files                                                             |
| Notes                | Your note Markdown files                                                                |
| Launcher Learning    | What the launcher learned you reach for, plus emoji and calculator history              |

The launcher has **Export Backup** and **Import Backup** commands too. They take everything, since
there is no room for checkboxes there.

## Read this before relying on it

**The format belongs to Tinycast and may change between versions. The only promise is that a backup
imports into the same version that made it.**

The file records which version wrote it. A Tinycast that does not recognize it says so clearly,
instead of importing half of it. A backup is for moving your setup to another Mac today, or restoring
after a reinstall. It is not a long-term archive.

## Imports are never silent

An import always shows a summary of what it did, category by category.

If the file holds custom commands, **it warns you before adding them**, because a file that quietly
adds shell commands is a different kind of risk.

Imports add rather than overwrite. Snippets and notes land next to what you already have; a note
whose name is taken gets a number added, never replaces yours. Importing the same file twice does not
give you two of everything.

Launcher Learning is the exception. It replaces what is there, because mixing two Macs' habits
describes neither.

A copied file in clipboard history travels as its path, not its contents. On import, entries for files
this Mac does not have are left out.

## A backup can never grant a capability

This is the important part.

Some switches are left out of every backup **on purpose**, because turning them on is a decision you
make, not a preference:

- **Snippets**: turning them on agrees to keyword matching
- **Extensions**: agrees to run third-party code
- **Calendar**: agrees to reading your calendar
- **Auto Join Meetings** and **Camera Preview**: agree to opening links and turning on the camera
- **Quick Actions**: agrees to typing into other apps
- **AI** and **MCP servers**: agree to sending text to a model and running server code
- **Search text in images and PDFs**: agrees to background text recognition
- **Fallback order and checkboxes**: could put a shell command runner in your launcher

So a backup someone sent you cannot switch on keystroke listening, run third-party code, read your
calendar or reach an AI provider. You turn those on yourself, in the app, after reading what they do.
Importing snippets does not turn snippets on.

## Other things left out on purpose

| Left out                                                        | Why                                                           |
| --------------------------------------------------------------- | ------------------------------------------------------------- |
| Extensions: their code, data and sign-ins                       | Third-party, and their sign-ins live in the Keychain          |
| AI chats, API keys, and every AI and MCP setting                | Conversations and keys stay on the Mac that had them          |
| Quick Actions model, prompts, language and custom actions       | An import must never change what a shortcut does to your text |
| Extension registries, package manager, custom search paths      | They describe this Mac, not your setup                        |
| Palette position, auto-switch input source, calendar checkboxes | They belong to this Mac's screens and hardware                |
| Anything cached, like currency rates and update checks          | It comes back on its own                                      |

Clipboard images are stored inside the backup by name, not by where they sat on your Mac. The one
kind of path a backup does carry is a copied file's location, because that is what the entry is.

**Launch at login** and **Show in menu bar** are read from their live state, so they come back as you
had them.

## Where your data actually lives

Everything a backup carries is also an ordinary file, in `~/Library/Application Support/com.tinycast.app/`:

| What                                          | Where                                          |
| --------------------------------------------- | ---------------------------------------------- |
| [Snippets](/docs/features/snippets)           | `Snippets/`                                    |
| [Notes](/docs/features/notes)                 | `Notes/`                                       |
| [Quicklinks](/docs/launcher/quicklinks)       | `quicklinks.sqlite3`, with its own JSON export |
| [Clipboard history](/docs/features/clipboard) | `clipboard.sqlite3`, with images beside it     |
| [AI chats](/docs/ai)                          | `ai-chats.sqlite3`, never in a backup          |

Snippets and notes are plain Markdown. Copying those folders is a perfectly good backup, and you can
read them without Tinycast. That is the point of keeping them that way.
