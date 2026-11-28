import Foundation
import Testing

@testable import Tinycast

struct EmojiTests {
    private var catalog: [EmojiEntry] { EmojiCatalog.parse(EmojiData.raw) }

    @Test func shippedCatalogHasUniqueGlyphsAndPopulatesEveryCategory() {
        let entries = catalog
        #expect(entries.count > 1900)
        #expect(Set(entries.map(\.glyph)).count == entries.count)
        #expect(Set(entries.map(\.category)).count == EmojiCategory.allCases.count)
    }

    @Test func wavingHandSupportsTonesAndCarriesTheHelloKeyword() throws {
        let wave = try #require(catalog.first { $0.name == "waving hand" })
        #expect(wave.supportsSkinTone)
        #expect(wave.keywords.contains("hello"))
    }

    @Test(arguments: [("€", EmojiCategory.currency), ("※", .cjk), ("⌘", .keysAndTechnical)])
    func symbolsAreGroupedByKind(_ glyph: String, _ category: EmojiCategory) throws {
        let entry = try #require(catalog.first { $0.glyph == glyph })
        #expect(entry.category == category)
    }

    @Test func appleLogoCarriesTheAppleKeyword() throws {
        let apple = try #require(catalog.first { $0.glyph == "\u{F8FF}" })
        #expect(apple.keywords.contains("apple"))
    }

    @Test func categoryMenuIncludesTheCatalogAndThreeOverviewOptions() {
        #expect(EmojiCategory.allCases.allSatisfy { !$0.systemImage.isEmpty })
        #expect(EmojiCategoryFilter.allCases.count == EmojiCategory.allCases.count + 3)
        #expect(EmojiCategoryFilter.allCases.first == .all)
    }

    @Test(arguments: [(EmojiCategory.symbols, "Symbol"), (.flags, "Emoji")])
    func actionTitleReflectsTheCategory(_ category: EmojiCategory, _ title: String) {
        #expect(category.itemTitle == title)
    }

    @Test func densityOptionsSpanSixThroughTenColumnsAndDefaultToEight() {
        #expect(EmojiGridColumns.allCases.map(\.rawValue) == [6, 7, 8, 9, 10])
        #expect(EmojiGridColumns.default == .eight)
    }

    @Test(arguments: [
        (EmojiGridColumns.six, EmojiGridZoom.zoomIn, EmojiGridColumns.eight, nil as EmojiGridColumns?),
        (.ten, .zoomOut, .eight, nil),
        (.eight, .zoomIn, .eight, .seven),
        (.eight, .zoomOut, .eight, .nine),
        (.six, .actualSize, .nine, .nine),
        (.nine, .actualSize, .nine, nil)
    ])
    func zoomRespectsDensityBoundsAndTheConfiguredDefault(
        _ columns: EmojiGridColumns, _ zoom: EmojiGridZoom,
        _ defaultColumns: EmojiGridColumns, _ expected: EmojiGridColumns?
    ) {
        #expect(columns.applying(zoom, default: defaultColumns) == expected)
    }

    @Test func localizedTermsFollowEnglishInLanguagePreferenceOrder() {
        let entries = EmojiCatalog.parse(
            "A|alpha|ob|0|red\nB|beta|ob|0|", localized: ["A|rouge,vif\nbad line\nB|bleu", "A|rot"])
        #expect(entries.map(\.keywords) == ["red,rouge,vif,rot", "bleu"])
    }

    private static let languages = ["de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"]

    private func keywordPacks() throws -> [URL] {
        let resources = try #require(Bundle.main.resourceURL)
        return try FileManager.default.contentsOfDirectory(
            at: resources.appending(path: "EmojiKeywords", directoryHint: .isDirectory),
            includingPropertiesForKeys: nil)
    }

    @Test func theAppShipsKeywordPacksForEverySupportedSearchLanguage() throws {
        let packs = try keywordPacks()
        #expect(Set(packs.map { $0.deletingPathExtension().lastPathComponent }) == Set(Self.languages))
    }

    @Test(arguments: languages)
    func aShippedPackUsesCatalogGlyphsAndIsReachableByItsLanguage(_ language: String) throws {
        let packs = try keywordPacks()
        let available = packs.map { $0.deletingPathExtension().lastPathComponent }
        let pack = try #require(
            Bundle.main.url(forResource: language, withExtension: "txt", subdirectory: "EmojiKeywords"))
        let lines = try String(contentsOf: pack, encoding: .utf8).split(separator: "\n")
        let glyphs = Set(catalog.map(\.glyph))
        #expect(lines.count > 1500)
        #expect(lines.allSatisfy { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            return fields.count == 2 && glyphs.contains(String(fields[0])) && !fields[1].isEmpty
        })
        #expect(EmojiCatalog.keywordLanguages(available: available, preferred: [language]) == [language])
    }

    @Test(arguments: [
        (["en-US"], [String]()),
        (["en-GB", "fr-CA"], ["fr"]),
        (["fr-FR", "de-DE", "fr-CA"], ["fr", "de"]),
        (["zh-CN"], ["zh-Hans"]),
        (["zh-Hans-CN", "zh-SG"], ["zh-Hans"]),
        (["pt-PT"], ["pt"]),
        (["sr-Latn-RS"], [])
    ])
    func preferredLocalesSelectDistinctAvailablePacks(_ preferred: [String], _ expected: [String]) throws {
        let packs = try keywordPacks()
        let available = packs.map { $0.deletingPathExtension().lastPathComponent }
        #expect(EmojiCatalog.keywordLanguages(available: available, preferred: preferred) == expected)
    }

    @Test func applyingADarkToneAppendsTheModifier() {
        #expect(EmojiCatalog.applyTone(.dark, to: "👋") == "👋🏿")
    }

    @Test func applyingALightToneReplacesTheVariationSelector() throws {
        let victory = try #require(catalog.first { $0.name == "victory hand" })
        #expect(victory.glyph.unicodeScalars.contains { $0.value == 0xFE0F })
        let toned = victory.display(tone: .light)
        #expect(!toned.unicodeScalars.contains { $0.value == 0xFE0F })
        #expect(toned.unicodeScalars.contains { $0.value == 0x1F3FB })
        #expect(victory.display(tone: .none) == victory.glyph)
    }

    @Test func multiPersonGlyphIgnoresSkinTone() throws {
        let holdingHands = try #require(catalog.first { $0.glyph == "🧑‍🤝‍🧑" })
        #expect(!holdingHands.supportsSkinTone)
        #expect(holdingHands.display(tone: .dark) == holdingHands.glyph)
    }

    @Test(arguments: [
        (0, 8), (8, 16), (15, 23), (20, 25), (16, 24), (25, 27), (28, 28)
    ])
    func downPreservesTheColumnAcrossSectionsAndClampsToPartialRows(_ index: Int, _ expected: Int) {
        #expect(EmojiGridGeometry(counts: [16, 10, 3], columns: 8).down(from: index) == expected)
    }

    @Test(arguments: [(8, 0), (26, 24), (28, 25), (3, 3), (18, 10), (23, 15)])
    func upPreservesTheColumnAcrossSectionsAndClampsToPartialRows(_ index: Int, _ expected: Int) {
        #expect(EmojiGridGeometry(counts: [16, 10, 3], columns: 8).up(from: index) == expected)
    }

    @Test func singleRowCannotMoveVertically() {
        let grid = EmojiGridGeometry(counts: [5], columns: 8)
        #expect(grid.up(from: 2) == 2)
        #expect(grid.down(from: 2) == 2)
    }

    @Test func anEmptyGridKeepsTheSelectionSafe() {
        #expect(EmojiGridGeometry(counts: [], columns: 8).down(from: 0) == 0)
    }

    @Test(arguments: [([12, 8], 6, 2, 8), ([20], 10, 7, 17)])
    func downUsesTheConfiguredDensity(_ counts: [Int], _ columns: Int, _ index: Int, _ expected: Int) {
        #expect(EmojiGridGeometry(counts: counts, columns: columns).down(from: index) == expected)
    }

    @Test(arguments: [(1, 3, 1), (2, 2, 1), (0, 0, 0)])
    func removingAPinKeepsTheNearestAvailableSlot(_ index: Int, _ remaining: Int, _ expected: Int) {
        #expect(EmojiGridGeometry.selectionAfterRemovingPin(at: index, remainingCount: remaining) == expected)
    }

    @Test(arguments: [
        (3, ["x", "a", "b", "d"], 1),
        (6, ["n", "a", "b", "x", "d"], 7),
        (4, ["a", "b"], 2),
        (0, [], 0)
    ])
    func selectionFollowsTheGlyphOrItsNearestSlotWhenHistoryChanges(
        _ index: Int, _ updated: [String], _ expected: Int
    ) {
        #expect(EmojiGridGeometry.selection(
            index, afterSectionAt: 1, changesFrom: ["a", "b", "x", "d"], to: updated) == expected)
    }
}
