# Dictionary

`Define` is a launcher command and a fallback. The command opens the dictionary screen (`.dictionary`)
empty; the fallback opens it on whatever was typed, showing that term's entry across the palette. The search field stays the term, so a different word is
one edit away. It reads the dictionaries enabled in Dictionary.app through Dictionary Services — no
network, no bundled word list.

## Invariants

- **The command gates the fallback, never the reverse.** Define has no feature pane, so Settings ›
  Commands is its switch: while the command is hidden there — itself or the whole Commands category —
  `FallbackCoordinator` offers no Define fallback and Settings › Fallbacks does not list it. While it is
  visible, the fallback's own checkbox hides just the fallback, leaving the command searchable.
- **The copy is the dictionary's own text.** `DictionaryEntry` splits the plain text for display
  only — the first `| … |` span as the pronunciation, each `•` as a new sense — and keeps `text`
  untouched, so ↵ never copies a layout the parser invented.
- **One lookup per term.** The palette rebuilds its screen on every redraw, so `DictionaryProvider`
  keeps the last term's result, the same one-deep memo as `CalcMemo`.

## Actions

| Key | Does |
| --- | --- |
| ↵ | Copy Definition — the whole entry, then the palette closes |
| ⌘↵ | Open in Dictionary — `dict://<term>`, for the rich entry and every other enabled dictionary |

What the screen shows depends on the dictionaries the reader has enabled; a term none of them knows
reads "No definition found".
