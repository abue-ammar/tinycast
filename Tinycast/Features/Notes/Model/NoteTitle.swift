import Foundation

/// A note's title is its filename; one the user has not named yet borrows its first line to show.
enum NoteTitle {
    static let untitled = "Untitled"

    /// Wide enough that the scanned prefix is covered even where every character is four bytes.
    static let headByteCount = 4096

    private static let scanLimit = 1024
    private static let displayLimit = 120

    /// True only for the names `create` claims — `Untitled`, `Untitled 2`, … — never a typed one.
    static func isUnnamed(_ title: String) -> Bool {
        guard title.hasPrefix(untitled) else { return false }
        let suffix = title.dropFirst(untitled.count)
        guard !suffix.isEmpty else { return true }
        let digits = suffix.dropFirst()
        return suffix.hasPrefix(" ") && !digits.isEmpty
            && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The first line carrying visible text, without its Markdown markers and capped to one row.
    static func firstLine(of source: String) -> String? {
        let head = String(source.prefix(scanLimit))
        let text = head as NSString
        for line in NoteMarkdownParser.parse(head).lines {
            let title = visibleText(of: line, in: text)
            guard !title.isEmpty else { continue }
            return String(title.prefix(displayLimit))
        }
        return nil
    }

    /// A line as it reads when rendered, with the setting on or off: syntax never titles a note.
    private static func visibleText(of line: NoteMarkdown.Line, in text: NSString) -> String {
        switch line.kind {
        case .blank, .rule, .fenceOpen, .fenceClose: return ""
        default: break
        }
        var visible = ""
        var cursor = line.contentRange.location
        for marker in line.inlines.flatMap(\.markerRanges).sorted(by: { $0.location < $1.location }) {
            visible += text.substring(with: NSRange(cursor..<marker.location))
            cursor = NSMaxRange(marker)
        }
        visible += text.substring(with: NSRange(cursor..<NSMaxRange(line.contentRange)))
        return visible.trimmingCharacters(in: .whitespaces)
    }
}
