import Foundation

/// A release body as the update window reads it: the changelog CI generates, split into the handful
/// of block shapes it actually emits.
enum ReleaseNotes {
    /// CI writes the install instructions below this line for the download page — a window that
    /// updates itself has no use for them.
    static let installMarker = "<!-- tinycast:install -->"

    /// The app-facing half of a release body. A body published before the marker existed has no
    /// marker, and comes back whole.
    static func summary(of body: String) -> String {
        let head = body.range(of: installMarker).map { String(body[..<$0.lowerBound]) } ?? body
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum Block: Hashable, Sendable {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
    }

    /// A line scanner over what GitHub's release-notes API produces, not a general Markdown parser.
    static func blocks(from summary: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(linkified(paragraph.joined(separator: "\n"))))
            paragraph.removeAll()
        }

        for raw in summary.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false)
        {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let heading = heading(in: line) {
                flush()
                blocks.append(heading)
            } else if let bullet = bullet(in: line) {
                flush()
                blocks.append(.bullet(linkified(bullet)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func heading(in line: String) -> Block? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        // Markdown lets a heading close with its own run of hashes; trimming both ends covers it.
        let text = line.dropFirst(hashes.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return .heading(level: hashes.count, text: text)
    }

    /// GitHub autolinks a mention and a PR reference on the web; in the window they are plain text
    /// until they are spelled as Markdown links.
    private static func linkified(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var previous: Character?

        while index < text.endIndex {
            let rest = text[index...]
            // A Markdown destination is already a URL, so nothing inside it is a reference.
            if rest.hasPrefix("]("), let close = rest.firstIndex(of: ")") {
                output += text[index...close]
                previous = ")"
                index = text.index(after: close)
            } else if let (link, next) = mention(in: rest, after: previous)
                ?? pullRequest(in: rest, after: previous)
            {
                output += link
                previous = text[text.index(before: next)]
                index = next
            } else {
                output.append(rest[index])
                previous = rest[index]
                index = text.index(after: index)
            }
        }
        return output
    }

    private static func mention(in rest: Substring, after previous: Character?) -> (String, String.Index)? {
        guard rest.first == "@", previous.map({ !$0.isLetter && !$0.isNumber }) ?? true else { return nil }
        let handle = rest.dropFirst().prefix(while: isHandle)
        // A scoped package name — `@raycast/api` — is not a person.
        guard !handle.isEmpty, handle.count <= 39, !handle.hasSuffix("-"),
            rest[handle.endIndex...].first != "/"
        else { return nil }
        return ("[@\(handle)](https://github.com/\(handle))", handle.endIndex)
    }

    private static func pullRequest(
        in rest: Substring, after previous: Character?
    ) -> (String, String.Index)? {
        guard rest.first == "#", previous.map({ $0.isWhitespace || $0 == "(" }) ?? true else { return nil }
        let number = rest.dropFirst().prefix(while: { $0.isASCII && $0.isNumber })
        guard !number.isEmpty else { return nil }
        let url = "https://github.com/\(ReleaseFeed.repository)/pull/\(number)"
        return ("[#\(number)](\(url))", number.endIndex)
    }

    private static func isHandle(_ character: Character) -> Bool {
        character == "-" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    private static func bullet(in line: String) -> String? {
        guard let marker = line.first, "*-+".contains(marker), line.dropFirst().first == " " else {
            return nil
        }
        return line.dropFirst().trimmingCharacters(in: .whitespaces)
    }
}
