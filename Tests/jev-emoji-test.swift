import Foundation

@main
@MainActor
struct JevEmojiTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static func entry(_ glyph: String, _ name: String) -> EmojiEntry {
        EmojiEntry(
            glyph: glyph, name: name, category: .symbols, supportsSkinTone: false, keywords: "")
    }

    static func main() {
        let hammer = entry("☭", "hammer and sickle")
        let fist = entry("✊", "raised fist")
        let grin = entry("😀", "grinning face")
        let catalog = [hammer, fist, grin]

        expect(JevEmojiRanking.requestBody(query: "ab", entries: catalog) == nil, "short query")
        expect(JevEmojiRanking.requestBody(query: "communism", entries: []) == nil, "empty catalog")

        let body = JevEmojiRanking.requestBody(query: " communism ", entries: catalog)
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let state = json?["state"] as? [String: String]
        let questions = json?["questions"] as? [String: Any]
        let first = questions?["s0"] as? [String: Any]
        let criteria = first?["criteria"] as? [String: String]
        expect(json?["model"] as? String == "jev-latest", "model alias")
        expect(state?["query"] == "communism", "query is trimmed into state")
        expect(criteria?["☭"] == "hammer and sickle", "glyph is a choice option")
        expect(criteria?["none"] != nil, "each shard can decline")

        let wide = (0..<450).map { entry("e\($0)", "emoji \($0)") }
        let wideBody = JevEmojiRanking.requestBody(query: "yearning", entries: wide)
        let wideJSON =
            wideBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let wideQuestions = wideJSON?["questions"] as? [String: Any]
        expect(wideQuestions?.count == 3, "shards stay under the choice cap")
        for question in wideQuestions.map({ Array($0.values) }) ?? [] {
            let criteria = (question as? [String: Any])?["criteria"] as? [String: String]
            expect((criteria?.count ?? 0) <= 255, "a shard plus none fits in one choice")
        }

        let response = """
        {"answers":{
          "s0":{"type":"choice","probabilities":{"☭":0.62,"✊":0.21,"none":0.1,"😀":0.07}},
          "s1":{"type":"choice","probabilities":{"😀":0.04,"none":0.9}},
          "s2":{"type":"noul","noul":0.2}
        }}
        """.data(using: .utf8)!
        expect(
            JevEmojiRanking.glyphs(in: response, catalog: catalog) == ["☭", "✊"],
            "keeps emoji that beat none and drops a shard that declines")
        expect(
            JevEmojiRanking.glyphs(in: Data("nope".utf8), catalog: catalog).isEmpty,
            "malformed response")

        if failures == 0 {
            print("ok")
        } else {
            print("\(failures) failed")
            exit(1)
        }
    }
}
