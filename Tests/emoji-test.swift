// Standalone test for the emoji catalog and grid geometry, compiling the real sources.
import Foundation

@main
@MainActor
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
        let reference = entries.first { $0.glyph == "※" }
        expect(reference?.category == .cjk, "※ landed in CJK Symbols")
        let command = entries.first { $0.glyph == "⌘" }
        expect(command?.category == .keysAndTechnical, "⌘ landed in Keys & Technical")
        let apple = entries.first { $0.glyph == "\u{F8FF}" }
        expect(apple?.keywords.contains("apple") == true, " is searchable as apple")
        expect(
            EmojiCategory.allCases.allSatisfy { !$0.systemImage.isEmpty },
            "every category has a menu symbol")
        expect(
            EmojiCategoryFilter.allCases.count == EmojiCategory.allCases.count + 3,
            "all, pinned and frequent precede every catalog category")
        expect(EmojiCategoryFilter.allCases.first == .all, "All Categories is the default row")
        expect(EmojiCategory.symbols.itemTitle == "Symbol", "symbol categories use Symbol actions")
        expect(EmojiCategory.flags.itemTitle == "Emoji", "emoji categories use Emoji actions")

        // Density is bounded to the five user-facing choices, with eight as the default.
        expect(
            EmojiGridColumns.allCases.map(\.rawValue) == [6, 7, 8, 9, 10],
            "grid densities cover six through ten columns")
        expect(EmojiGridColumns.default == .eight, "the default grid has eight columns")
        expect(EmojiGridColumns.six.applying(.zoomIn, default: .eight) == nil, "zoom-in stops at six")
        expect(EmojiGridColumns.ten.applying(.zoomOut, default: .eight) == nil, "zoom-out stops at ten")
        expect(EmojiGridColumns.eight.applying(.zoomIn, default: .eight) == .seven, "zoom-in drops one")
        expect(EmojiGridColumns.eight.applying(.zoomOut, default: .eight) == .nine, "zoom-out adds one")
        expect(
            EmojiGridColumns.six.applying(.actualSize, default: .nine) == .nine,
            "actual size returns to the configured default")
        expect(
            EmojiGridColumns.nine.applying(.actualSize, default: .nine) == nil,
            "actual size at the default changes nothing")

        // Keyword packs join after English, in preference order, and skip blank keyword fields.
        let merged = EmojiCatalog.parse(
            "A|alpha|ob|0|red\nB|beta|ob|0|", localized: ["A|rouge,vif\nbad line\nB|bleu", "A|rot"])
        expect(merged.map(\.keywords) == ["red,rouge,vif,rot", "bleu"], "packs append keywords")

        let packDirectory = URL(fileURLWithPath: "Tinycast/Resources/EmojiKeywords")
        let packs =
            (try? FileManager.default.contentsOfDirectory(
                at: packDirectory, includingPropertiesForKeys: nil)) ?? []
        let available = packs.map { $0.deletingPathExtension().lastPathComponent }
        expect(
            Set(available) == ["de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"],
            "keyword packs ship for the supported languages")
        let glyphs = Set(entries.map(\.glyph))
        for pack in packs {
            let lines = ((try? String(contentsOf: pack, encoding: .utf8)) ?? "").split(separator: "\n")
            let name = pack.deletingPathExtension().lastPathComponent
            expect(
                lines.count > 1500
                    && lines.allSatisfy {
                        let fields = $0.split(separator: "|", omittingEmptySubsequences: false)
                        return fields.count == 2 && glyphs.contains(String(fields[0]))
                            && !fields[1].isEmpty
                    },
                "\(name) pack is well-formed and keyed by catalog glyphs")
            expect(
                EmojiCatalog.keywordLanguages(available: available, preferred: [name]) == [name],
                "\(name) pack is reachable by its own language")
        }

        for (preferred, expected) in [
            (["en-US"], []),
            (["en-GB", "fr-CA"], ["fr"]),
            (["fr-FR", "de-DE", "fr-CA"], ["fr", "de"]),
            (["zh-CN"], ["zh-Hans"]),
            (["zh-Hans-CN", "zh-SG"], ["zh-Hans"]),
            (["pt-PT"], ["pt"]),
            (["sr-Latn-RS"], [])
        ] {
            expect(
                EmojiCatalog.keywordLanguages(available: available, preferred: preferred) == expected,
                "\(preferred) reads the \(expected) packs")
        }

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
        expect(
            EmojiGridGeometry.selectionAfterRemovingPin(at: 1, remainingCount: 3) == 1,
            "unpin selects the neighbour that shifts into the removed slot")
        expect(
            EmojiGridGeometry.selectionAfterRemovingPin(at: 2, remainingCount: 2) == 1,
            "unpinning the last pin selects its preceding neighbour")
        expect(
            EmojiGridGeometry.selectionAfterRemovingPin(at: 0, remainingCount: 0) == 0,
            "unpinning the only pin leaves a safe empty selection")

        let history = ["a", "b", "x", "d"]
        expect(
            EmojiGridGeometry.selection(
                3, afterSectionAt: 1, changesFrom: history, to: ["x", "a", "b", "d"]) == 1,
            "a used emoji takes the selection with it to the front")
        expect(
            EmojiGridGeometry.selection(6, afterSectionAt: 1, changesFrom: history, to: ["n"] + history)
                == 7,
            "a growing section shifts the cells after it")
        expect(
            EmojiGridGeometry.selection(4, afterSectionAt: 1, changesFrom: history, to: ["a", "b"]) == 2,
            "a shrinking section clamps a dropped glyph to its last cell")
        expect(
            EmojiGridGeometry.selection(0, afterSectionAt: 1, changesFrom: history, to: []) == 0,
            "cells before the section keep their index")

        let sixColumns = EmojiGridGeometry(counts: [12, 8], columns: 6)
        expect(sixColumns.down(from: 2) == 8, "six-column navigation keeps its visual column")
        let tenColumns = EmojiGridGeometry(counts: [20], columns: 10)
        expect(tenColumns.down(from: 7) == 17, "ten-column navigation keeps its visual column")

        if failures == 0 {
            print("emoji-test: all checks passed (\(entries.count) records)")
        } else {
            print("emoji-test: \(failures) failure(s)")
            exit(1)
        }
    }
}
