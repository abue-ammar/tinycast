import Foundation

/// A typed query, parsed. See docs/features/file-search.md#query-language.
struct FileNameQuery: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case file
        case folder
    }

    /// Token bits are a `UInt8`, so a ninth positive word is dropped rather than wrapped.
    static let positiveTokenLimit = 8
    static let resultLimit = 200

    private(set) var tokens: [FileNameMatch.Token] = []
    private(set) var kind: Kind?
    /// Lowercased and without the dot.
    private(set) var extensions: [[UInt8]] = []
    private(set) var scope: String?
    /// Seconds since 1970, inclusive at both ends.
    private(set) var modified: ClosedRange<UInt32>?

    init(_ raw: String, homeDirectory: URL, now: Date) {
        for word in Self.words(in: raw) {
            if let colon = word.firstIndex(of: ":"),
                applyFilter(
                    key: word[..<colon], value: String(word[word.index(after: colon)...]),
                    homeDirectory: homeDirectory, now: now)
            {
                continue
            }
            for piece in word.split(separator: "/") { appendToken(String(piece)) }
        }
    }

    var positive: [FileNameMatch.Token] { tokens.filter { !$0.negate } }
    var negative: [FileNameMatch.Token] { tokens.filter(\.negate) }

    var isEmpty: Bool {
        tokens.isEmpty && kind == nil && extensions.isEmpty && scope == nil && modified == nil
    }

    /// Spaces split words, except inside "double quotes".
    static func words(in raw: String) -> [String] {
        var words: [String] = []
        var current = ""
        var isQuoted = false
        for character in raw {
            if character == "\"" {
                isQuoted.toggle()
            } else if character.isWhitespace && !isQuoted {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private mutating func appendToken(_ word: String) {
        var text = Substring(word)
        var negate = false
        var mode = FileNameMatch.Mode.fuzzy
        if text.hasPrefix("!") {
            text = text.dropFirst()
            negate = true
            mode = .exact
        }
        if text.hasPrefix("'") {
            text = text.dropFirst()
            mode = .exact
        } else if text.hasPrefix("^") {
            text = text.dropFirst()
            mode = .prefix
        } else if text.hasSuffix("$") {
            text = text.dropLast()
            mode = .suffix
        }
        let folded = Array(FuzzyMatch.normalized(String(text)).utf8)
        guard !folded.isEmpty else { return }
        guard negate || positive.count < Self.positiveTokenLimit else { return }
        tokens.append(FileNameMatch.Token(text: folded, mode: mode, negate: negate))
    }

    /// False when `key` names no filter, so the word is searched for as typed.
    private mutating func applyFilter(
        key: Substring, value: String, homeDirectory: URL, now: Date
    ) -> Bool {
        switch key {
        case "ext":
            extensions += value.split(separator: ",").compactMap { part in
                let bare = part.trimmingPrefix(".").lowercased()
                return bare.isEmpty ? nil : Array(bare.utf8)
            }
        case "kind":
            switch value {
            case "file", "f": kind = .file
            case "folder", "dir", "d": kind = .folder
            default: break
            }
        case "in":
            guard !value.isEmpty else { break }
            let anchored = value.hasPrefix("/") || value.hasPrefix("~") ? value : "~/" + value
            let path = FileSearchScope.expand(anchored, homeDirectory: homeDirectory).path
            scope = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        case "mtime", "modified":
            modified = Self.modifiedRange(value, now: now)
        default:
            return false
        }
        return true
    }

    /// `<7d` is "within the last seven days", `>7d` "longer ago", `1d..7d` between the two.
    static func modifiedRange(_ value: String, now: Date) -> ClosedRange<UInt32>? {
        guard let ages = range(value, parse: age) else { return nil }
        let now = UInt64(max(0, now.timeIntervalSince1970))
        let newest = now - min(ages.lowerBound, now)
        let oldest = ages.upperBound == .max ? 0 : now - min(ages.upperBound, now)
        return UInt32(clamping: oldest)...UInt32(clamping: newest)
    }

    private static func range(
        _ value: String, parse: (Substring) -> UInt64?
    ) -> ClosedRange<UInt64>? {
        for prefix in [">=", ">"] where value.hasPrefix(prefix) {
            return parse(value.dropFirst(prefix.count)).map { $0...UInt64.max }
        }
        for prefix in ["<=", "<"] where value.hasPrefix(prefix) {
            return parse(value.dropFirst(prefix.count)).map { 0...$0 }
        }
        if let dots = value.range(of: "..") {
            guard let low = parse(value[..<dots.lowerBound]),
                let high = parse(value[dots.upperBound...]), low <= high
            else { return nil }
            return low...high
        }
        return parse(Substring(value)).map { $0...$0 }
    }

    /// Seconds in an age such as `90m`, `3d` or `2w`; a bare number is days.
    private static func age(_ text: Substring) -> UInt64? {
        let digits = text.prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        guard let amount = Double(digits), amount >= 0 else { return nil }
        let unit: Double
        switch text.dropFirst(digits.count).lowercased() {
        case "s": unit = 1
        case "m", "min": unit = 60
        case "h": unit = 3_600
        case "", "d": unit = 86_400
        case "w": unit = 604_800
        case "mo": unit = 2_592_000
        case "y": unit = 31_536_000
        default: return nil
        }
        return UInt64(min(amount * unit, Double(UInt32.max)))
    }
}
