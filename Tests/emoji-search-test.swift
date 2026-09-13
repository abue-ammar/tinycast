// Standalone test for emoji search, compiling the real index and frequency store.
import Foundation

@main
@MainActor
struct EmojiSearchTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("emoji-search-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let frequent = FrequentEmojiStore(fileURL: directory.appendingPathComponent("frequency.json"))
        let index = EmojiIndex()
        await index.load()

        for (query, glyph, maxRank) in [
            ("pray", "🙏", 5),
            (":+1:", "👍", 1),
            (":-1:", "👎", 1),
            (":rocket:", "🚀", 1),
            ("hand waving", "👋", 1),
            ("face joy", "😂", 1),
            ("tears joy", "😂", 1),
            ("birthday", "🎂", 1),
            ("party", "🎉", 1),
            ("states united", "🇺🇸", 1)
        ] {
            let results = index.search(query, frequent: frequent)
            expect(
                results.prefix(maxRank).contains { $0.glyph == glyph },
                "\(query) finds \(glyph) in the first \(maxRank) results")
        }

        let waving = index.search("hand waving", frequent: frequent)
        expect(waving.contains { $0.glyph == "👋" }, "multiword terms can match in either order")
        expect(
            !index.search("and waving", frequent: frequent).contains { $0.glyph == "👋" },
            "multiword terms must begin a word")
        expect(
            !index.search("hello missing", frequent: frequent).contains { $0.glyph == "👋" },
            "every multiword term must match")
        expect(index.search("quuxxyz", frequent: frequent).isEmpty, "unmatched query")
        expect(
            index.search("  RED\t HEART\n", frequent: frequent)
                == index.search("red heart", frequent: frequent),
            "case and whitespace do not change ranking")
        expect(
            index.search("piñata", frequent: frequent)
                == index.search("ＰＩＮＡＴＡ", frequent: frequent),
            "accent and width folding are preserved")

        let boundaries = EmojiIndex()
        await boundaries.load("A|zebra|ob|0|red,blue\nB|ladybug bug|ob|0|red")
        expect(
            !boundaries.search("db", frequent: frequent).contains { $0.glyph == "A" },
            "a fuzzy match cannot cross keyword boundaries")
        expect(
            boundaries.search("red blue", frequent: frequent).first?.glyph == "A",
            "separate query words may match separate keywords")
        expect(
            !boundaries.search("red,blue zebra", frequent: frequent).contains { $0.glyph == "A" },
            "one term cannot cross the serialized keyword separator")
        expect(
            boundaries.search("bug red", frequent: frequent).first?.glyph == "B",
            "a later word-start hit survives an earlier mid-word hit")
        for (query, glyph) in [
            ("face screaming in fear", "😱"), ("leaf fluttering in wind", "🍃"),
            ("family: man boy", "👨‍👦"), ("family: man  girl", "👨‍👧"),
            ("couple with heart: woman man", "👩‍❤️‍👨")
        ] {
            expect(
                index.search(query, frequent: frequent).first?.glyph == glyph,
                "full name still ranks first: \(query)")
        }

        await boundaries.load("A|zebra|ob|0|red blue\nB|blue red|ob|0|\nC|zebra|ob|0|red,blue")
        expect(
            boundaries.search("red blue", frequent: frequent).map(\.glyph) == ["A", "B", "C"],
            "a literal phrase outranks reordered name words, then separate keywords")
        expect(
            boundaries.search("blue red", frequent: frequent).first?.glyph == "B",
            "a literal full name outranks metadata matches")

        await boundaries.load(
            "A|red balloon|ob|0|\nB|zebra|ob|0|red\nC|redwood|ob|0|\nD|red|ob|0|")
        expect(
            boundaries.search("red", frequent: frequent).map(\.glyph) == ["D", "A", "B", "C"],
            "full name, complete leading word, exact keyword, then partial leading word")

        frequent.record("🙏")
        expect(index.search("pray", frequent: frequent).first?.glyph == "🙏", "usage reranks a tie")

        let ranking = EmojiIndex()
        await ranking.load("A|alpha|ob|0|\nB|beta|ob|0|alpha")
        let rankingFrequency = FrequentEmojiStore(
            fileURL: directory.appendingPathComponent("ranking-frequency.json"))
        rankingFrequency.record("B")
        expect(
            ranking.search("alpha", frequent: rankingFrequency).first?.glyph == "A",
            "usage cannot overtake a stronger text match")

        await ranking.load("A|alpha|ob|0|red\nB|beta|ob|0|red")
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        rankingFrequency.replace([
            FrequentEmoji(glyph: "A", count: 2, lastUsed: first),
            FrequentEmoji(glyph: "B", count: 1, lastUsed: second)
        ])
        expect(
            ranking.search("red", frequent: rankingFrequency).first?.glyph == "A",
            "count breaks text ties before recency")
        rankingFrequency.replace([
            FrequentEmoji(glyph: "A", count: 2, lastUsed: first),
            FrequentEmoji(glyph: "B", count: 2, lastUsed: second)
        ])
        expect(
            ranking.search("red", frequent: rankingFrequency).first?.glyph == "B",
            "recency breaks equal-count ties and replacement invalidates the memo")
        rankingFrequency.replace([])
        expect(
            ranking.search("red", frequent: rankingFrequency).first?.glyph == "A",
            "clearing usage restores catalog order")

        let otherFrequency = FrequentEmojiStore(
            fileURL: directory.appendingPathComponent("other-frequency.json"))
        otherFrequency.record("B")
        expect(
            ranking.search("red", frequent: otherFrequency).first?.glyph == "B",
            "another frequency store is scored independently")
        expect(
            ranking.search("red", frequent: frequent).first?.glyph == "A",
            "stores with equal revisions cannot share a cached ranking")

        otherFrequency.replace([
            FrequentEmoji(glyph: "B", count: 2, lastUsed: second),
            FrequentEmoji(glyph: "B", count: 1, lastUsed: first)
        ])
        expect(
            ranking.search("red", frequent: otherFrequency).first?.glyph == "B",
            "duplicate imported glyphs do not crash search")

        expect(index.search("face", frequent: frequent, limit: 1).count == 1, "one-result limit")
        expect(index.search("face", frequent: frequent, limit: 12).count == 12, "limit is memoized")
        expect(index.search(" ", frequent: frequent).isEmpty, "empty query")
        expect(index.search("face", frequent: frequent, limit: 0).isEmpty, "zero limit")

        if failures == 0 {
            print("emoji-search-test: all checks passed")
        } else {
            print("emoji-search-test: \(failures) failure(s)")
            exit(1)
        }
    }
}
