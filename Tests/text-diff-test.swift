import Foundation

@main
enum TextDiffTests {
    static func main() {
        precondition(TextDiffEngine.maxTokens <= Int(UInt16.max), "LCS cells are UInt16")

        precondition(TextDiffEngine.diff(original: "", modified: "") == [])
        precondition(TextDiffEngine.diff(original: "", modified: "new") == [.inserted("new")])
        precondition(TextDiffEngine.diff(original: "old", modified: "") == [.deleted("old")])
        precondition(
            TextDiffEngine.diff(original: "a b", modified: "b a")
                == [.deleted("a "), .equal("b"), .inserted(" a")])
        precondition(
            TextDiffEngine.diff(original: "café 👩🏽‍💻\n", modified: "cafe 👩🏽‍💻\n")
                == [.deleted("café"), .inserted("cafe"), .equal(" 👩🏽‍💻\n")])

        for count in Array(1...33) + [127, 128, 129] {
            let original = (0..<count).map { $0.isMultiple(of: 2) ? "old" : " " }.joined()
            let modified = (0..<count).map { $0.isMultiple(of: 2) ? "new" : " " }.joined()
            let expected: [TextDiffEngine.Chunk] = (0..<count).flatMap { index in
                index.isMultiple(of: 2)
                    ? [.deleted("old"), .inserted("new")] : [.equal(" ")]
            }
            precondition(TextDiffEngine.diff(original: original, modified: modified) == expected)
            precondition(
                TextDiffEngine.diff(original: "start " + original, modified: original)
                    == [.deleted("start "), .equal(original)])
            precondition(
                TextDiffEngine.diff(original: original, modified: "start " + original)
                    == [.inserted("start "), .equal(original)])
        }

        for count in [TextDiffEngine.maxTokens - 1, TextDiffEngine.maxTokens] {
            let original = (0..<count).map { $0.isMultiple(of: 2) ? "word" : " " }.joined()
            let suffix = String(original.dropFirst(4))
            let modified = "ward" + suffix
            precondition(
                TextDiffEngine.diff(original: original, modified: modified)
                    == [.deleted("word"), .inserted("ward"), .equal(suffix)])
        }

        let overCap = String(repeating: "word ", count: TextDiffEngine.maxTokens / 2) + "word"
        for (original, modified) in [(overCap, "short"), ("short", overCap)] {
            precondition(
                TextDiffEngine.diff(original: original, modified: modified)
                    == [.deleted(original), .inserted(modified)])
        }
        precondition(TextDiffEngine.diff(original: overCap, modified: overCap) == [.equal(overCap)])
        precondition(TextDiffEngine.diff(original: "", modified: overCap) == [.inserted(overCap)])
        precondition(TextDiffEngine.diff(original: overCap, modified: "") == [.deleted(overCap)])
        print("Exact chunks, Unicode, ties, packed boundaries, high LCS values and fast paths passed")
    }
}
