import Foundation
import Testing

@testable import Tinycast

@MainActor
struct EmojiSearchTests {
    private let scratch: ScratchDirectory
    private let frequent: FrequentEmojiStore

    init() throws {
        scratch = try ScratchDirectory("emoji")
        frequent = FrequentEmojiStore(fileURL: scratch.url.appending(path: "frequency.json"))
    }

    @Test func pinsKeepTheirAuthoredOrderThroughEditsAndReload() throws {
        let file = scratch.url.appending(path: "pinned.json")
        try JSONEncoder().encode(["A", "", "A", "B"]).write(to: file)
        let pins = PinnedEmojiStore(fileURL: file)
        #expect(pins.glyphs == ["A", "B"])

        pins.toggle("C")
        #expect(pins.glyphs == ["A", "B", "C"])
        pins.swap("C", with: "B")
        #expect(pins.glyphs == ["A", "C", "B"])
        pins.swap("A", with: "missing")
        #expect(pins.glyphs == ["A", "C", "B"])
        pins.toggle("C")
        #expect(pins.glyphs == ["A", "B"])
        pins.replace(["B", "B", "D", ""])
        #expect(pins.glyphs == ["B", "D"])
        #expect(PinnedEmojiStore(fileURL: file).glyphs == ["B", "D"])
    }

    @Test func pinWriteFailureIsReported() async {
        let pins = PinnedEmojiStore(fileURL: scratch.url)
        await confirmation { reported in
            pins.onPersistenceFailure = { reported() }
            pins.toggle("A")
        }
    }

    @Test(arguments: [
        ("pray", "🙏", 5), (":+1:", "👍", 1), (":-1:", "👎", 1), (":rocket:", "🚀", 1),
        ("hand waving", "👋", 1), ("face joy", "😂", 1), ("tears joy", "😂", 1), ("birthday", "🎂", 1),
        ("party", "🎉", 1), ("states united", "🇺🇸", 1)
    ])
    func catalogNamesAndAliasesReachTheirExpectedRank(_ query: String, _ glyph: String, _ rank: Int) async {
        let index = EmojiIndex()
        await index.load()
        #expect(index.search(query, frequent: frequent).prefix(rank).contains { $0.glyph == glyph })
    }

    @Test(arguments: [
        ("poulet", "🐔"), ("gateau", "🎂"), ("gâteau d'anniversaire", "🎂"), ("allemagne", "🇩🇪"),
        ("ねこ", "🐱"), ("ネコ", "🐱"), ("寿司", "🍣")
    ])
    func frenchAndJapaneseTermsRankInTheFirstThree(_ query: String, _ glyph: String) async {
        let index = EmojiIndex()
        await index.load(languages: ["fr-FR", "ja-JP", "en-US"])
        #expect(index.search(query, frequent: frequent).prefix(3).contains { $0.glyph == glyph })
    }

    @Test func aLocalizedKeywordReachesEveryGlyphItAnnotates() async {
        let index = EmojiIndex()
        await index.load(languages: ["fr-FR", "ja-JP", "en-US"])
        #expect(index.search("poulet", frequent: frequent).contains { $0.glyph == "🍗" })
    }

    @Test(arguments: ["chicken", "birthday", "party", "pray", "red heart", "hand waving", "cat"])
    func addingLocalizedTermsPreservesTheEnglishTopFive(_ query: String) async {
        let english = EmojiIndex()
        let multilingual = EmojiIndex()
        await english.load()
        await multilingual.load(languages: ["fr-FR", "ja-JP", "en-US"])
        #expect(multilingual.search(query, frequent: frequent).prefix(5).map(\.glyph)
            == english.search(query, frequent: frequent).prefix(5).map(\.glyph))
    }

    @Test func englishRequestsUseOnlyTheCatalogKeywords() async {
        let catalog = EmojiIndex()
        let english = EmojiIndex()
        await catalog.load()
        await english.load(languages: ["en-US"])
        #expect(english.entries.map(\.keywords) == catalog.entries.map(\.keywords))
    }

    @Test(arguments: [("猫", "🐱"), ("汉堡", "🍔"), ("cat", "🐱")])
    func simplifiedChineseAndEnglishTermsRankTogether(_ query: String, _ glyph: String) async {
        let index = EmojiIndex()
        await index.load(languages: ["zh-Hans-CN", "en-US"])
        #expect(index.search(query, frequent: frequent).prefix(3).contains { $0.glyph == glyph })
    }

    @Test(arguments: [("hand waving", true), ("and waving", false), ("hello missing", false)])
    func multiwordQueriesMatchEveryWordStartInAnyOrder(_ query: String, _ includesWave: Bool) async {
        let index = EmojiIndex()
        await index.load()
        #expect(index.search(query, frequent: frequent).contains { $0.glyph == "👋" } == includesWave)
    }

    @Test(arguments: [("  RED\t HEART\n", "red heart"), ("piñata", "ＰＩＮＡＴＡ")])
    func caseWhitespaceAccentAndWidthFoldToTheSameRanking(_ query: String, _ equivalent: String) async {
        let index = EmojiIndex()
        await index.load()
        #expect(index.search(query, frequent: frequent) == index.search(equivalent, frequent: frequent))
    }

    @Test(arguments: ["db", "red,blue zebra"])
    func aSingleTermCannotCrossKeywordBoundaries(_ query: String) async {
        let index = EmojiIndex()
        await index.load("A|zebra|ob|0|red,blue\nB|ladybug bug|ob|0|red")
        #expect(!index.search(query, frequent: frequent).contains { $0.glyph == "A" })
    }

    @Test(arguments: [("red blue", "A"), ("bug red", "B")])
    func wordsMayMatchSeparateKeywordsAndLaterWordStarts(_ query: String, _ glyph: String) async throws {
        let index = EmojiIndex()
        await index.load("A|zebra|ob|0|red,blue\nB|ladybug bug|ob|0|red")
        let first = try #require(index.search(query, frequent: frequent).first)
        #expect(first.glyph == glyph)
    }

    @Test(arguments: [
        ("face screaming in fear", "😱"), ("leaf fluttering in wind", "🍃"),
        ("family: man boy", "👨‍👦"), ("family: man  girl", "👨‍👧"),
        ("couple with heart: woman man", "👩‍❤️‍👨")
    ])
    func fullNamesRankFirst(_ query: String, _ glyph: String) async throws {
        let index = EmojiIndex()
        await index.load()
        let first = try #require(index.search(query, frequent: frequent).first)
        #expect(first.glyph == glyph)
    }

    @Test func exactPhrasesRankAheadOfReorderedWordsAndSeparateKeywords() async throws {
        let index = EmojiIndex()
        await index.load("A|zebra|ob|0|red blue\nB|blue red|ob|0|\nC|zebra|ob|0|red,blue")
        #expect(index.search("red blue", frequent: frequent).map(\.glyph) == ["A", "B", "C"])
        let first = try #require(index.search("blue red", frequent: frequent).first)
        #expect(first.glyph == "B")
    }

    @Test func fullNameThenCompleteLeadingWordThenExactKeywordThenPartialWord() async {
        let index = EmojiIndex()
        await index.load("A|red balloon|ob|0|\nB|zebra|ob|0|red\nC|redwood|ob|0|\nD|red|ob|0|")
        #expect(index.search("red", frequent: frequent).map(\.glyph) == ["D", "A", "B", "C"])
    }

    @Test func recordingAGlyphReranksACatalogTie() async throws {
        let index = EmojiIndex()
        await index.load()
        frequent.record("🙏")
        let first = try #require(index.search("pray", frequent: frequent).first)
        #expect(first.glyph == "🙏")
    }

    @Test func usageCannotOutrankAStrongerTextMatch() async throws {
        let index = EmojiIndex()
        await index.load("A|alpha|ob|0|\nB|beta|ob|0|alpha")
        frequent.record("B")
        let first = try #require(index.search("alpha", frequent: frequent).first)
        #expect(first.glyph == "A")
    }

    @Test func historyUsesRecencyWhileSearchBreaksTiesByCountThenRecency() async throws {
        let index = EmojiIndex()
        await index.load("A|alpha|ob|0|red\nB|beta|ob|0|red")
        let file = scratch.url.appending(path: "ranking-frequency.json")
        let ranking = FrequentEmojiStore(fileURL: file)
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        ranking.replace([
            FrequentEmoji(glyph: "A", count: 2, lastUsed: first),
            FrequentEmoji(glyph: "B", count: 1, lastUsed: second)
        ])
        #expect(ranking.records.map(\.glyph) == ["B", "A"])
        let byCount = try #require(index.search("red", frequent: ranking).first)
        #expect(byCount.glyph == "A")

        ranking.record("A")
        #expect(ranking.records.map(\.glyph) == ["A", "B"])
        #expect(FrequentEmojiStore(fileURL: file).records.map(\.glyph) == ["A", "B"])
        ranking.replace([
            FrequentEmoji(glyph: "A", count: 2, lastUsed: first),
            FrequentEmoji(glyph: "B", count: 2, lastUsed: second)
        ])
        let byRecency = try #require(index.search("red", frequent: ranking).first)
        #expect(byRecency.glyph == "B")

        ranking.replace([])
        let byCatalog = try #require(index.search("red", frequent: ranking).first)
        #expect(byCatalog.glyph == "A")
    }

    @Test func equalRevisionsFromDifferentFrequencyStoresHaveIndependentRankings() async throws {
        let index = EmojiIndex()
        await index.load("A|alpha|ob|0|red\nB|beta|ob|0|red")
        frequent.record("🙏")
        let other = FrequentEmojiStore(fileURL: scratch.url.appending(path: "other-frequency.json"))
        other.record("B")
        let otherFirst = try #require(index.search("red", frequent: other).first)
        #expect(otherFirst.glyph == "B")
        let originalFirst = try #require(index.search("red", frequent: frequent).first)
        #expect(originalFirst.glyph == "A")
    }

    @Test func importingDuplicateTalliesKeepsTheNewestOneAndStillRanks() async throws {
        let index = EmojiIndex()
        await index.load("A|alpha|ob|0|red\nB|beta|ob|0|red")
        frequent.record("B")
        frequent.replace([
            FrequentEmoji(glyph: "B", count: 2, lastUsed: Date(timeIntervalSince1970: 200)),
            FrequentEmoji(glyph: "B", count: 1, lastUsed: Date(timeIntervalSince1970: 100))
        ])
        let first = try #require(index.search("red", frequent: frequent).first)
        #expect(first.glyph == "B")
        #expect(frequent.records.map(\.glyph) == ["B"])
        let record = try #require(frequent.records.first)
        #expect(record.count == 2)
    }

    @Test func aNewUseInAFullHistoryEvictsItsOldestGlyph() throws {
        frequent.replace((0..<300).map {
            FrequentEmoji(glyph: String($0), count: 100, lastUsed: Date(timeIntervalSince1970: Double($0)))
        })
        frequent.record("new")
        let first = try #require(frequent.records.first)
        #expect(first.glyph == "new")
        #expect(frequent.records.count == 300)
        #expect(!frequent.records.contains { $0.glyph == "0" })
    }

    @Test func changingTheLimitRecomputesAMemoizedQuery() async {
        let index = EmojiIndex()
        await index.load()
        frequent.record("🙏")
        #expect(index.search("face", frequent: frequent, limit: 1).count == 1)
        #expect(index.search("face", frequent: frequent, limit: 12).count == 12)
        #expect(index.search("face", frequent: frequent, limit: 0).isEmpty)
    }

    @Test(arguments: [" ", "quuxxyz"])
    func blankAndUnmatchedQueriesReturnNoRows(_ query: String) async {
        let index = EmojiIndex()
        await index.load()
        #expect(index.search(query, frequent: frequent).isEmpty)
    }
}
