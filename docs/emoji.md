# Emoji picker

A palette sub-screen (reached like Clipboard / Calculator History) presenting a searchable emoji grid.

## Layout

- `Core/Emoji/` — the **Foundation-only** catalog + geometry (no AppKit / SwiftUI imports):
  - `EmojiCatalog.swift` — the catalog model (groups, names, keywords).
  - `EmojiGridGeometry.swift` — pure grid-layout math (columns, item sizing).
  - `EmojiData.generated.swift` — the emoji dataset.
  - `EmojiIndex.swift` — search index over the catalog.
  - `FrequentEmojiStore.swift` — persisted most-recently / frequently used emoji.
- `Features/Emoji/EmojiGridView.swift` — the SwiftUI grid view.

## Invariants

- **`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js`** (Node 18+ for global
  `fetch`) — **never edit it by hand**. Regenerate and commit instead.
- **`EmojiCatalog.swift` and `EmojiGridGeometry.swift` must stay AppKit/SwiftUI-free**, because the
  `Tools/emoji-test.swift` harness compiles the real sources:

  ```sh
  swiftc Smallcast/Core/Emoji/EmojiCatalog.swift Smallcast/Core/Emoji/EmojiGridGeometry.swift \
    Smallcast/Core/Emoji/EmojiData.generated.swift Tools/emoji-test.swift -o /tmp/emoji-test && /tmp/emoji-test
  ```

- The grid list uses the palette scrollbar (`.thinScrollbar()` + `.hideNativeScrollers()`) and the
  shared `SectionHeader` for group labels — see [ui.md](ui.md).
