import Foundation

@main
@MainActor
struct ActionMenuSearchTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        let empty = ActionMenuSearchQuery("  \n")
        expect(empty.isEmpty, "a whitespace-only query is empty")
        expect(empty.score("Paste as Plain Text") != nil, "a blank query keeps every action")

        let plainText = ActionMenuSearchQuery("ptxt")
        expect(!plainText.isEmpty, "a meaningful query is not empty")
        expect(
            plainText.score("Paste as Plain Text") != nil,
            "a non-contiguous query uses the launcher's fuzzy matcher")
        expect(plainText.score("Copy to Clipboard") == nil, "unmatched actions are removed")
        let ranked = ActionMenuSearchQuery("paste")
        expect(
            ranked.score("Paste")! > ranked.score("Paste as Plain Text")!,
            "the strongest fuzzy result can drive the menu highlight")

        let folded = ActionMenuSearchQuery("resume")
        expect(folded.score("Résumé") != nil, "matching stays case- and diacritic-insensitive")

        let preserved = ActionMenuSearchQuery("  paste  ")
        expect(preserved.score("Paste to Finder") != nil, "outer whitespace does not affect matching")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
