// Standalone test for the emoji catalog + grid geometry — compiles the *real* sources (they stay AppKit/SwiftUI-free for this reason):
// swiftc Smallcast/Core/Emoji/EmojiCatalog.swift Smallcast/Core/Emoji/EmojiGridGeometry.swift Smallcast/Core/Emoji/EmojiData.generated.swift Tools/emoji-test.swift -o /tmp/emoji-test && /tmp/emoji-test

import Foundation

@main
struct EmojiTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static func main() {
        // Dataset + parser
        let entries = EmojiCatalog.parse(EmojiData.raw)
        expect(entries.count > 1900, "dataset has \(entries.count) records (want > 1900)")
        expect(Set(entries.map(\.glyph)).count == entries.count, "glyphs are unique")
        expect(
            Set(entries.map(\.category)).count == EmojiCategory.allCases.count,
            "every category is populated")

        let wave = entries.first { $0.name == "waving hand" }
        expect(wave?.supportsSkinTone == true, "👋 is tone-capable")
        expect(wave?.keywords.contains("hello") == true, "👋 carries CLDR keywords")
        let holdingHands = entries.first { $0.glyph == "🧑‍🤝‍🧑" }
        expect(holdingHands?.supportsSkinTone == false, "multi-person ZWJ is not tone-capable")
        let euro = entries.first { $0.glyph == "€" }
        expect(euro?.category == .currency, "€ landed in Currency")

        // Skin tone application
        expect(EmojiCatalog.applyTone(.dark, to: "👋") == "👋🏿", "modifier appended")
        let victory = entries.first { $0.name == "victory hand" }!
        expect(victory.glyph.unicodeScalars.contains { $0.value == 0xFE0F }, "✌️ base carries VS16")
        let toned = victory.display(tone: .light)
        expect(
            !toned.unicodeScalars.contains { $0.value == 0xFE0F }
                && toned.unicodeScalars.contains { $0.value == 0x1F3FB },
            "tone strips VS16 and appends the modifier")
        expect(victory.display(tone: .none) == victory.glyph, "tone .none leaves the glyph alone")
        expect(
            holdingHands!.display(tone: .dark) == holdingHands!.glyph,
            "tone ignored on non-capable entries")

        // Grid geometry (8 columns): sections of 16, 10, 3 cells
        let g = EmojiGridGeometry(counts: [16, 10, 3], columns: 8)
        expect(g.down(from: 0) == 8, "down within a full section keeps the column")
        expect(g.up(from: 8) == 0, "up within a full section keeps the column")
        expect(g.down(from: 8) == 16, "down from last row col 0 enters section 1 col 0")
        expect(g.down(from: 15) == 16 + 7, "down from col 7 keeps col 7 in the next section")
        expect(g.down(from: 16 + 4) == 16 + 9, "down onto a shorter partial row clamps to its end")
        expect(g.down(from: 16 + 0) == 16 + 8, "down within section 1 keeps the column")
        expect(g.down(from: 16 + 9) == 26 + 1, "down from partial-row col 1 keeps the column")
        expect(g.down(from: 28) == 28, "down from the last row is a no-op")
        expect(g.up(from: 26) == 16 + 8, "up from section 2 col 0 lands on section 1 last row col 0")
        expect(g.up(from: 28) == 16 + 9, "up from col 2 clamps into the shorter row above")
        expect(g.up(from: 3) == 3, "up from the first row is a no-op")
        expect(g.up(from: 16 + 2) == 10, "up from section 1 row 0 keeps the column into section 0")
        expect(g.up(from: 16 + 7) == 15, "up from section 1 col 7 clamps to section 0's last cell")

        // Single-section grid (search results) never escapes its bounds.
        let single = EmojiGridGeometry(counts: [5], columns: 8)
        expect(single.down(from: 2) == 2, "single row: down is a no-op")
        expect(single.up(from: 2) == 2, "single row: up is a no-op")
        expect(EmojiGridGeometry(counts: [], columns: 8).down(from: 0) == 0, "empty grid is safe")

        if failures == 0 {
            print("emoji-test: all checks passed (\(entries.count) records)")
        } else {
            print("emoji-test: \(failures) failure(s)")
            exit(1)
        }
    }
}
