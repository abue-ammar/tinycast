// How a Dictionary Services plain-text entry splits into headword, pronunciation and senses.

import Foundation

@main
@MainActor
struct DictionaryEntryTests {
    static var failures = 0
    static var passes = 0

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func main() {
        let hello = DictionaryEntry(
            term: "hello",
            text: "hello hel·lo | həˈlō | exclamation used as a greeting. • used to attract attention.")
        expect(hello.pronunciation, "həˈlō", "the first pipe pair is the pronunciation")
        expect(
            hello.senses, ["exclamation used as a greeting.", "used to attract attention."],
            "each bullet starts a sense, and the headword before the pipes is dropped")
        expect(hello.id, "hello", "the entry is named by the term that was asked for")

        let run = DictionaryEntry(term: "run", text: "run | rən | verb (, running | ˈrəniNG |) move fast")
        expect(run.pronunciation, "rən", "a later pipe pair is left in the sense")
        expect(run.senses, ["verb (, running | ˈrəniNG |) move fast"], "the body keeps its own pipes")

        let plain = DictionaryEntry(term: "thesaurus", text: "a book of synonyms")
        expect(plain.pronunciation, nil, "no pipes means no pronunciation")
        expect(plain.senses, ["a book of synonyms"], "no pipes means the whole text is the sense")

        let bare = DictionaryEntry(term: "x", text: "x | | • • a letter")
        expect(bare.pronunciation, nil, "an empty pipe pair is no pronunciation")
        expect(bare.senses, ["a letter"], "empty senses are dropped")
        expect(bare.text, "x | | • • a letter", "the copied text is the dictionary's own")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
