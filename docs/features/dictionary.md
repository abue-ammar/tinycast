# Dictionary

`Define` is a launcher fallback: whatever was typed goes to the dictionary screen (`.dictionary`), which
shows that term's entry across the palette. The search field stays the term, so a different word is
one edit away. It reads the dictionaries enabled in Dictionary.app through Dictionary Services — no
network, no bundled word list.

## Invariants

- **Define is query-driven and never listed.** `CommandID.define` is `isQueryDriven`, so it has no
  launcher row, no Settings › Commands row and no hotkey; the only way in is the fallback, and the
  fallback's checkbox in Settings › Fallbacks is its switch.
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
