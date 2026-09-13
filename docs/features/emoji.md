# Emoji picker

A palette sub-screen (reached like Clipboard / Calculator History) presenting a searchable emoji grid.

## Invariants

- **`Model/` stays Foundation-only** — `EmojiCatalog`, `EmojiGridGeometry` and the generated dataset are
  compiled by `emoji-test`, so an `import AppKit` there breaks the test suite.
- **`EmojiData.generated.swift` is emitted by `node Scripts/gen-emoji.js`** (Node 18+ for global `fetch`)
  and is never edited by hand. Regenerate and commit instead.

## Layout

| Path | Role |
| --- | --- |
| `Model/EmojiCatalog.swift` | The catalog model — groups, names, keywords |
| `Model/EmojiGridGeometry.swift` | Pure grid math — columns, item sizing |
| `Model/EmojiData.generated.swift` | The dataset |
| `Service/EmojiIndex.swift` | Search index over the catalog |
| `Service/FrequentEmojiStore.swift` | Persisted most-frequently-used emoji |
| `UI/EmojiGridView.swift` | The SwiftUI grid |
| `UI/EmojiScreen.swift`, `UI/EmojiCoordinator.swift` | The palette screen and its action surface |

The index and the store are **effects**, so they live under `Service/` — only the three files above them
are pure.

## Search

- **Keywords keep their CLDR phrase boundaries.** The generator joins them with commas and keeps every
  annotation, and a single-word query fuzzy-matches the name and each keyword on its own, so a
  subsequence never spans two keywords.
- **Every word of a multiword query must start a word** in the name or a keyword, in any order. A literal
  phrase outranks words found in the name, which outrank words assembled from name and keywords.
- **A full name ranks first, then a complete leading name word, then an exact keyword**, then a partial
  leading word: `birthday` keeps 🎂 first, and `pray` favours the annotation over "prayer beads".
- **Colon-wrapped queries are unwrapped**, so `:+1:` reuses CLDR's `+1` annotation with no alias table.
- **Usage breaks ties, never tiers.** The top 100 glyphs from `FrequentEmojiStore.top` add a 100…1
  bonus, and the store's identity and revision are in the search memo key.

## Rendering

Two structural decisions in `EmojiGridView` are load-bearing, and both are about the ~2,000 cells the
grid can realize.

**Interaction lives on the row, never the cell.** Tap, double-tap, right-click and hover are attached
once per `EmojiSectionGrid` row. A fast scroll realizes every cell, and per-cell interaction
machinery — notably the `NSView`-backed right-click catcher — costs roughly **100 MB** at that scale,
which lazy containers never release. Per-row keeps it bounded to the handful of visible rows, so the
cell view stays pure content: no gestures, no overlays, no hover tracking. Hover is resolved by
mapping the pointer's x to a column, which is exact because cells split the row width evenly with
zero spacing; the empty trailing slots of a partial last row resolve to nil.

**Rows sit directly under the outer `LazyVStack`.** A cell nested inside a `LazyVGrid` cannot be
scrolled to until it is realized, which broke keyboard scrolling on key-hold. Keeping rows as the
`ScrollViewReader`'s targets means any row can be reached even while off-screen. Row IDs are
section-namespaced, because a frequently-used emoji also appears inside its own category. Selecting
into the first row scrolls to the origin rather than the row, so the section header shows too.

The grid list uses the palette scrollbar (`.thinScrollbar()` + `.hideNativeScrollers()`) and the shared
`SectionHeader` for group labels — see [ui.md](../ui.md).
