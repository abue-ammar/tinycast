import Foundation

/// A Dictionary Services entry, split into the parts its plain text runs together on one line.
struct DictionaryEntry: Equatable, Identifiable, Sendable {
    let term: String
    /// The first `| … |` span — how the headword is said — when the dictionary gives one.
    let pronunciation: String?
    /// One per sense: the plain text marks each sub-sense with `•` but never breaks the line.
    let senses: [String]
    /// The dictionary's own text, untouched, since that is what a copy should carry.
    let text: String

    var id: String { term }

    init(term: String, text: String) {
        self.term = term
        self.text = text
        let pipes = text.ranges(of: "|").prefix(2)
        let body: Substring
        if pipes.count == 2 {
            let spoken = text[pipes[0].upperBound..<pipes[1].lowerBound]
                .trimmingCharacters(in: .whitespaces)
            pronunciation = spoken.isEmpty ? nil : spoken
            body = text[pipes[1].upperBound...]
        } else {
            pronunciation = nil
            body = text[...]
        }
        senses = body.split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
