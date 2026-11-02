---
title: Define Word
description: Look up a word in your Mac's dictionaries from the launcher, and copy its definition.
---

**Define Word** shows a word's dictionary entry in the launcher, read from the dictionaries already
on your Mac.

There's nothing to turn on. The command is in **Settings → Commands**, where you can give it a
global shortcut and an alias. Press the shortcut again to close it.

## Looking up a word

Run **Define Word** and type a word. The entry updates as you type. The search field holds the
word, so to look up another one, change what you typed.

You can also start from the launcher. Type the word, and **Define Word** appears among the
[fallbacks](/docs/launcher/fallbacks) under **Use "…" with…**. It opens the entry for what you
typed.

The entry shows the word and its pronunciation, then each part of speech with its numbered senses.
You can select and copy any part of it.

With nothing typed, the screen says **Type a word to define**. If none of your dictionaries knows
the word, it says **No definition found**.

## Actions

| Action             | Shortcut                      |
| ------------------ | ----------------------------- |
| Copy Definition    | <kbd>return</kbd>             |
| Open in Dictionary | <kbd>⌘</kbd><kbd>return</kbd> |

**Copy Definition** copies the whole entry as plain text and closes the launcher. **Open in
Dictionary** opens the word in Dictionary.app.

## Which dictionaries

Tinycast uses the dictionaries turned on in Dictionary.app's settings, in the order listed there.
The first one that knows the word answers. To add a language or change the order, change it in
Dictionary.app. **Open in Dictionary** shows the word in every dictionary you turned on.

Lookups happen on your Mac. Nothing is sent over the network.

## Turning it off

Clear **Define Word**'s checkbox in **Settings → Commands**. That hides both the command and its
fallback. To hide only the fallback, clear its checkbox in **Settings → Fallbacks**.
