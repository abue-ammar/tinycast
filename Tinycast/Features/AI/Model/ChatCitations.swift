import Foundation

/// Where a reply's source numbers go: after the sentence that cited each one, as a paper does.
enum ChatCitations {
    struct Anchor: Equatable {
        /// Characters into the drawn text; the marker goes here.
        let offset: Int
        let number: Int
        let url: URL
    }

    /// One anchor per source per sentence, in reading order; two in one sentence share its end.
    static func anchors(in text: AttributedString, numbers: [String: Int]) -> [Anchor] {
        guard !numbers.isEmpty else { return [] }
        let plain = Array(String(text.characters))
        var anchors: [Anchor] = []
        var seen = Set<[Int]>()
        func add(url: URL, endingAt end: Int) {
            guard let number = numbers[ChatReferences.key(url)] else { return }
            let offset = sentenceEnd(after: end, in: plain)
            guard seen.insert([offset, number]).inserted else { return }
            anchors.append(Anchor(offset: offset, number: number, url: url))
        }
        for run in text.runs {
            guard let url = run.link, url.scheme?.hasPrefix("http") == true else { continue }
            let end = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
            add(url: url, endingAt: end)
        }
        let string = String(plain)
        for match in string.matches(of: #/https?://[^\s<>"'`)\]]+/#) {
            let offset = string.distance(from: string.startIndex, to: match.range.lowerBound)
            let start = text.characters.index(text.startIndex, offsetBy: offset)
            // A URL a Markdown link already names was cited through the link.
            guard text.runs[start].link == nil else { continue }
            var raw = String(match.output)
            while let last = raw.last, ".,;:!?*_".contains(last) { raw.removeLast() }
            guard let url = URL(string: raw) else { continue }
            add(url: url, endingAt: offset + raw.count)
        }
        return anchors.sorted { ($0.offset, $0.number) < ($1.offset, $1.number) }
    }

    /// The end of the sentence holding `offset`: past its full stop, or the line or text's end.
    static func sentenceEnd(after offset: Int, in plain: [Character]) -> Int {
        var index = offset
        while index < plain.count {
            let character = plain[index]
            if character.isNewline { return index }
            if ".!?".contains(character), index + 1 == plain.count || plain[index + 1].isWhitespace {
                return index + 1
            }
            index += 1
        }
        return plain.count
    }

}
