---
title: Backup & restore
description: Export your setup to a single file, choose what goes in it, restore it on another Mac, and what a backup deliberately cannot do.
---

**Settings → Backup**

A backup is one `.tinycast` file. You tick what goes into it, and you tick again what comes back out
when you import — the two choices are independent, so a file with everything in it can still restore
only your snippets.

| Category            | What travels                                                        |
| ------------------- | ------------------------------------------------------------------- |
| Settings & Shortcuts | Shortcuts, custom commands, quicklinks, favorites, aliases, preferences |
| Clipboard History   | Text and image clips, with the images themselves                     |
| Snippets            | Your snippet Markdown files                                          |
| Notes               | Your note Markdown files                                             |
| Launcher Learning   | What the launcher has learned you reach for, plus emoji and calculator history |

The same two commands are in the launcher — **Export Backup** and **Import Backup** — where they take
everything, since there's no room for checkboxes there.

## Read this before relying on it

**The format is internal and may change between releases. The only guarantee is that export → import
round-trips within one build.**

The file records which version wrote it, and a Tinycast that doesn't recognise it says so plainly
rather than importing half of it. There is no migration path. A backup is for moving your setup to
another Mac today, or for restoring after a reinstall — it is not a long-term archive.

## Imports are never silent

An import always reports a summary of what it applied, category by category.

A settings file that quietly rewrote your hotkeys would be hostile, so it does not. If the file
contains custom commands, the import **warns before accepting executable content**, because that is
a genuinely different category of risk.

Imports merge rather than overwrite. Snippets and notes are added beside what you already have —
a note whose title is taken gets a suffix, never replaces the original — and importing the same file
twice doesn't leave you with two of everything. Launcher learning is the exception: it replaces,
because averaging two Macs' habits describes neither.

## A backup can never grant a capability

This is the important one.

Several flags are excluded from every export **on purpose**, because each is a consent decision rather
than a preference:

- **`snippetsEnabled`** — enabling snippets is consent to keystroke matching
- **`extensionsEnabled`** — enabling extensions is consent to run third-party code
- **`calendarEnabled`** — consent to read your calendar
- **`autoJoinMeetings`** and **`cameraPreview`** — consent to open links and turn the camera on
- **`quickActionsEnabled`** — consent to deliver keystrokes into other apps

So importing a backup someone sent you cannot switch on keystroke listening, third-party code
execution or calendar access. You have to do that yourself, in the app, having read what it says.
Importing snippets does not enable snippets.

## Other deliberate exclusions

| Excluded                                                       | Why                                            |
| -------------------------------------------------------------- | ---------------------------------------------- |
| Extensions — their code, their data and their stored logins    | Third-party, and their logins are keychain items |
| AI chat history, API keys and every AI setting                 | Conversations and credentials stay on their Mac  |
| Extension registry list, package manager, custom search paths  | Describe this machine, not your setup           |
| Palette position, auto-switch input source                     | Machine-local geometry and hardware             |
| Anything cached — currency rates, update checks                | Regenerates on its own                          |

No file path from your Mac is written into a backup, so nothing in the file says who you are or where
you keep things.

Two values come from outside Tinycast's own settings — **Launch at login** is owned by the system
login item, and **Show in menu bar** is read from the live state — but both are handled correctly.

## Where your data actually lives

Everything a backup carries is also an ordinary file on disk:

| What                                          | Where                                                       |
| --------------------------------------------- | ----------------------------------------------------------- |
| [Snippets](/docs/features/snippets)           | `~/Library/Application Support/com.tinycast.app/Snippets/`  |
| [Notes](/docs/features/notes)                 | `.../Notes/`                                                |
| [Quicklinks](/docs/launcher/quicklinks)       | `.../quicklinks.sqlite3` — and it has its own JSON export   |
| [Clipboard history](/docs/features/clipboard) | `.../clipboard.sqlite3`, with images in `.../images/`       |

Snippets and notes are plain Markdown. Copying those folders is a perfectly good backup, and they
are readable without Tinycast — which is the point of storing them that way.
