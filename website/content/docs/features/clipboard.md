---
title: Clipboard history
description: Text and images, searchable, filtered by type, pasted back where you came from.
---

Tinycast keeps what you copy and lets you paste any of it back into the app you were using.

Reach it with <kbd>⇥</kbd> from the launcher, the **Clipboard History** command, or its own global
shortcut recorded in **Settings → Clipboard**. <kbd>⎋</kbd> returns to the launcher from all three.

The footer names where a paste will land — "Paste to Notes" — so you always know the target.

## Actions

| Action                         | Shortcut                             |
| ------------------------------ | ------------------------------------ |
| Paste                          | <kbd>↵</kbd>                         |
| Copy to Clipboard              | <kbd>⌘</kbd><kbd>↵</kbd>             |
| Paste, keeping the window open | <kbd>⌥</kbd><kbd>↵</kbd>             |
| Filter by type                 | <kbd>⌘</kbd><kbd>P</kbd>             |
| Pin / Unpin Entry              | <kbd>⌘</kbd><kbd>.</kbd>             |
| Delete Entry                   | <kbd>⌃</kbd><kbd>X</kbd>             |
| Delete All Entries             | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>X</kbd> |

Pasting needs the [Accessibility permission](/docs/permissions).

## Filtering by type

<kbd>⌘</kbd><kbd>P</kbd> opens a filter at the trailing edge of the search field, with five
**exclusive** cases:

**All Types** · **Text Only** · **Images Only** · **Links Only** · **Emails Only**

A copied URL is a link, not a narrower kind of text, so _Text Only_ means prose.

Each case has its own empty message, so "Clipboard history is empty" never appears over a history
that only looks empty through a filter. The filter stays available when the list is empty, which
makes it the way back out.

Classification is worked out from the text and never stored. Anything over 2048 bytes is plain text;
so is anything containing whitespace. Then `scheme://` and `mailto:`, then an address shape, then a
bare domain — which must be lower case and end in a common TLD, so `Safari.app`, `report.pdf` and
`index.html` stay out.

## Pinning

<kbd>⌘</kbd><kbd>.</kbd> pins the selected entry.

- Pinned entries go in a single **Pinned** section above the date buckets, ordered by when you
  pinned them, oldest first.
- They lead both the empty query and search results.
- **Pins survive retention pruning.** Clear History still removes everything.
- Pasting a pinned entry does not promote it — it holds its place.
- **Unpinning re-dates it**: the entry rejoins history as the newest item rather than dropping back
  into an old date bucket.

## Settings

**Settings → Clipboard**

| Setting               | Options                                                           | Default                    |
| --------------------- | ----------------------------------------------------------------- | -------------------------- |
| Global shortcut       | —                                                                 | None                       |
| Keep history for      | 1 Day · 1 Week · 1 Month · 3 Months · 6 Months · 1 Year · Forever | **3 Months**               |
| Disabled Applications | An app list                                                       | Keychain Access, Passwords |
| Clear history         | —                                                                 | —                          |

**Disabled Applications** ships pre-seeded with Keychain Access and Passwords, so Tinycast never
records what you copy out of a password manager. Add your own.

## Limits worth knowing

Storage is SQLite with a full-text index, plus PNG files for images, under Tinycast's Caches folder.

- Capture polls twice a second. Tinycast's own writes are stamped and skipped, so pasting from
  Tinycast never re-enters history.
- The newest **1000** entries are held in memory; search reaches further back.
- **Search needs at least three characters** to use the full-text index. Shorter queries filter the
  in-memory window instead.
- A search returns at most 200 matches, applied before any type filter — so a narrow filter over a
  broad query can show fewer rows than the history actually holds.
