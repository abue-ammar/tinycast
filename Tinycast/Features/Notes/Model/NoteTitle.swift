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

    /// The first line carrying visible text, without its heading markers and capped to one row.
    static func firstLine(of source: String) -> String? {
        for line in source.prefix(scanLimit).split(whereSeparator: \.isNewline) {
            let title = stripped(line)
            guard !title.isEmpty else { continue }
            return String(title.prefix(displayLimit))
        }
        return nil
    }

    private static func stripped(_ line: Substring) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let markers = trimmed.prefix { $0 == "#" }
        guard !markers.isEmpty, markers.count <= 6 else { return trimmed }
        let heading = trimmed.dropFirst(markers.count)
        guard heading.first?.isWhitespace == true else { return trimmed }
        return heading.trimmingCharacters(in: .whitespaces)
    }
}
