import Foundation

/// A page a reply pointed at, shown under it as a source the reader can open.
struct ChatReference: Equatable, Hashable, Sendable {
    let title: String
    let url: URL

    var host: String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Every web link in a reply, in the order it cited them; a code sample's URLs are not sources.
enum ChatReferences {
    static let limit = 8

    static func extract(from text: String) -> [ChatReference] {
        let prose = withoutCode(text)
        var found: [(offset: Int, reference: ChatReference)] = []
        var linked = Set<String>()
        for match in prose.matches(of: #/\[([^\]\n]+)\]\((https?://[^)\s]+)\)/#) {
            guard let url = URL(string: String(match.output.2)) else { continue }
            let label = String(match.output.1).trimmingCharacters(in: .whitespaces)
            let title = label.hasPrefix("http") ? readable(url) : label
            linked.insert(key(url))
            found.append((offset(of: match.range, in: prose), ChatReference(title: title, url: url)))
        }
        // Bare URLs outside a Markdown link: the link's own target was already counted above.
        let unlinked = prose.replacing(#/\[[^\]\n]+\]\(https?://[^)\s]+\)/#) { match in
            String(repeating: " ", count: match.output.count)
        }
        for match in unlinked.matches(of: #/https?://[^\s<>"'`)\]]+/#) {
            let trimmed = String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?*_"))
            guard let url = URL(string: trimmed), url.host() != nil, !linked.contains(key(url)) else {
                continue
            }
            let reference = ChatReference(title: readable(url), url: url)
            found.append((offset(of: match.range, in: unlinked), reference))
        }
        var seen = Set<String>()
        return found.sorted { $0.offset < $1.offset }
            .map(\.reference)
            .filter { seen.insert(key($0.url)).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// Fences and inline code are examples, not citations.
    private static func withoutCode(_ text: String) -> String {
        text.replacing(#/```[\s\S]*?(```|$)/#) { _ in "" }
            .replacing(#/`[^`\n]*`/#) { _ in "" }
    }

    /// Each source's number, keyed as `key` keys a URL, so a citation can find its chip.
    static func numbers(for references: [ChatReference]) -> [String: Int] {
        Dictionary(
            references.enumerated().map { (key($0.element.url), $0.offset + 1) },
            uniquingKeysWith: { first, _ in first })
    }

    /// One page cited twice, with and without a trailing slash, is one source.
    static func key(_ url: URL) -> String {
        var string = url.absoluteString.lowercased()
        while string.hasSuffix("/") { string.removeLast() }
        return string
    }

    private static func readable(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return path.isEmpty ? bare : "\(bare)/\(path)"
    }

    private static func offset(of range: Range<String.Index>, in text: String) -> Int {
        text.distance(from: text.startIndex, to: range.lowerBound)
    }
}
