import Foundation

enum SnippetTemplateEngine {
    struct ExpansionContext: Sendable {
        /// Clipboard history, most recent first: `{clipboard}` is offset 0.
        let clipboardHistory: [String]
        let selection: String
        let now: Date
        let calendar: Calendar
        let locale: Locale
        let timeZone: TimeZone
        /// Injected so `{uuid}` is reproducible under test.
        let makeUUID: @Sendable () -> String

        var clipboard: String { clipboardHistory.first ?? "" }

        /// A copy reading a different selection, for a caller that learns it after capture.
        func replacingSelection(with selection: String) -> Self {
            Self(
                clipboardHistory: clipboardHistory, selection: selection, now: now,
                calendar: calendar, locale: locale, timeZone: timeZone, makeUUID: makeUUID)
        }

        init(
            clipboardHistory: [String],
            selection: String,
            now: Date,
            calendar: Calendar,
            locale: Locale,
            timeZone: TimeZone,
            makeUUID: @escaping @Sendable () -> String = { UUID().uuidString }
        ) {
            var calendar = calendar
            calendar.timeZone = timeZone
            self.clipboardHistory = clipboardHistory
            self.selection = selection
            self.now = now
            self.calendar = calendar
            self.locale = locale
            self.timeZone = timeZone
            self.makeUUID = makeUUID
        }

        /// Convenience for a caller that only knows the current clipboard.
        init(
            clipboard: String,
            selection: String,
            now: Date,
            calendar: Calendar,
            locale: Locale,
            timeZone: TimeZone,
            makeUUID: @escaping @Sendable () -> String = { UUID().uuidString }
        ) {
            self.init(
                clipboardHistory: [clipboard],
                selection: selection,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone,
                makeUUID: makeUUID)
        }
    }

    /// An `{argument}` still needing a value, with any `options=` the prompt should offer.
    struct MissingArgument: Sendable, Equatable {
        let name: String
        let options: [String]
    }

    struct ExpansionResult: Sendable, Equatable {
        let text: String
        let cursorOffsetFromEnd: Int?
        let missingArguments: [MissingArgument]
    }

    /// Formatting the result asks for: none for a snippet, percent-encoding for a quicklink URL.
    enum ValueEncoding: Sendable {
        case none
        case percentEncoding
    }

    private static let maximumReferenceDepth = 5
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    static func expand(
        _ record: StoredSnippet,
        snippets: [StoredSnippet],
        context: ExpansionContext,
        userArguments: [String: String] = [:]
    ) -> ExpansionResult {
        result(
            of: expandText(
                record.snippet.text,
                snippets: snippets.sorted { $0.id < $1.id },
                context: context,
                userArguments: userArguments,
                encoding: .none,
                depth: 0,
                visitedIDs: [record.id]
            ))
    }

    /// Expands a non-snippet template; `{snippet:…}` has nothing to resolve and stays as text.
    static func expand(
        text: String,
        context: ExpansionContext,
        userArguments: [String: String] = [:],
        encoding: ValueEncoding = .none
    ) -> ExpansionResult {
        result(
            of: expandText(
                text,
                snippets: [],
                context: context,
                userArguments: userArguments,
                encoding: encoding,
                depth: 0,
                visitedIDs: []
            ))
    }

    /// Whether the template reads the selection. Parsed, so a literal brace run doesn't count.
    static func usesSelection(_ text: String) -> Bool {
        parseSegments(text).contains { segment in
            if case .selection = segment { return true }
            return false
        }
    }

    private static func result(of expansion: Expansion) -> ExpansionResult {
        ExpansionResult(
            text: expansion.text,
            cursorOffsetFromEnd: expansion.cursorCharacterOffset.map { expansion.text.count - $0 },
            missingArguments: expansion.missingArguments
        )
    }

    private struct Expansion {
        var text = ""
        var cursorCharacterOffset: Int?
        var missingArguments: [MissingArgument] = []
        var missingArgumentNames = Set<String>()

        mutating func append(_ value: String) {
            text += value
        }

        mutating func append(_ nested: Expansion) {
            let insertionOffset = text.count
            if cursorCharacterOffset == nil, let nestedCursor = nested.cursorCharacterOffset {
                cursorCharacterOffset = insertionOffset + nestedCursor
            }
            text += nested.text
            for argument in nested.missingArguments {
                addMissingArgument(argument)
            }
        }

        mutating func markCursor() {
            if cursorCharacterOffset == nil {
                cursorCharacterOffset = text.count
            }
        }

        mutating func addMissingArgument(_ argument: MissingArgument) {
            if missingArgumentNames.insert(argument.name).inserted {
                missingArguments.append(argument)
            }
        }
    }

    // MARK: - Tokens

    private enum Segment {
        case literal(String)
        case clipboard(offset: Int, modifiers: [Modifier])
        case selection(modifiers: [Modifier])
        case dateTime(DateTimeToken, modifiers: [Modifier])
        case uuid(modifiers: [Modifier])
        case argument(ArgumentToken, source: String, modifiers: [Modifier])
        case cursor
        case snippetReference(key: String, source: String)
    }

    private struct DateTimeToken {
        enum Kind {
            case date
            case time
            case dateTime
            case weekday
        }

        let kind: Kind
        /// Signed calendar offsets, applied in written order.
        let offsets: [Offset]
        let format: String?
        let localeIdentifier: String?

        struct Offset {
            let component: Calendar.Component
            let value: Int
        }
    }

    private struct ArgumentToken {
        let name: String
        let options: [String]
        let defaultValue: String?
    }

    /// Post-processing applied to a placeholder's value, left to right.
    private enum Modifier: String {
        case uppercase
        case lowercase
        case trim
        case percentEncode = "percent-encode"
        case jsonStringify = "json-stringify"
        /// Opts out of automatic formatting; Tinycast applies none, so it does nothing.
        case raw
    }

    // MARK: - Expansion

    private static func expandText(
        _ text: String,
        snippets: [StoredSnippet],
        context: ExpansionContext,
        userArguments: [String: String],
        encoding: ValueEncoding,
        depth: Int,
        visitedIDs: Set<StoredSnippet.ID>
    ) -> Expansion {
        var result = Expansion()
        for segment in parseSegments(text) {
            switch segment {
            case .literal(let value):
                result.append(value)
            case .clipboard(let offset, let modifiers):
                let value =
                    offset < context.clipboardHistory.count
                    ? context.clipboardHistory[offset] : ""
                result.append(apply(modifiers, to: value, encoding: encoding))
            case .selection(let modifiers):
                result.append(apply(modifiers, to: context.selection, encoding: encoding))
            case .dateTime(let token, let modifiers):
                result.append(
                    apply(modifiers, to: format(token, context: context), encoding: encoding))
            case .uuid(let modifiers):
                result.append(apply(modifiers, to: context.makeUUID(), encoding: encoding))
            case .argument(let token, let source, let modifiers):
                if let value = userArguments[token.name] ?? token.defaultValue {
                    result.append(apply(modifiers, to: value, encoding: encoding))
                } else {
                    result.append(source)
                    result.addMissingArgument(
                        MissingArgument(name: token.name, options: token.options))
                }
            case .cursor:
                result.markCursor()
            case .snippetReference(let key, let source):
                guard depth < maximumReferenceDepth,
                    let target = resolveReference(key, snippets: snippets),
                    !visitedIDs.contains(target.id)
                else {
                    result.append(source)
                    continue
                }
                var nestedVisited = visitedIDs
                nestedVisited.insert(target.id)
                result.append(
                    expandText(
                        target.snippet.text,
                        snippets: snippets,
                        context: context,
                        userArguments: userArguments,
                        encoding: encoding,
                        depth: depth + 1,
                        visitedIDs: nestedVisited
                    ))
            }
        }
        return result
    }

    private static func apply(
        _ modifiers: [Modifier], to value: String, encoding: ValueEncoding
    ) -> String {
        let modified = modifiers.reduce(value) { partial, modifier in
            switch modifier {
            case .uppercase: return partial.uppercased()
            case .lowercase: return partial.lowercased()
            case .trim: return partial.trimmingCharacters(in: .whitespacesAndNewlines)
            case .percentEncode: return percentEncoded(partial)
            case .jsonStringify: return jsonEscaped(partial)
            case .raw: return partial
            }
        }
        // Last, so `| uppercase` can't rewrite the `%xx`; skipped when the template spoke first.
        guard encoding == .percentEncoding,
            !modifiers.contains(.raw), !modifiers.contains(.percentEncode)
        else { return modified }
        return percentEncoded(modified)
    }

    /// Percent-encodes outside RFC 3986's unreserved set, so it is safe in any URL component.
    private static func percentEncoded(_ value: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Escapes for use inside a JSON string; the surrounding quotes stay the template's job.
    private static func jsonEscaped(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 {
                    escaped += String(format: "\\u%04x", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }

    // MARK: - Parsing

    private static func parseSegments(_ source: String) -> [Segment] {
        var segments: [Segment] = []
        var position = source.startIndex

        while position < source.endIndex,
            let opening = source[position...].firstIndex(of: "{")
        {
            if position < opening {
                segments.append(.literal(String(source[position..<opening])))
            }
            guard let closing = source[source.index(after: opening)...].firstIndex(of: "}") else {
                segments.append(.literal(String(source[opening...])))
                return segments
            }

            let end = source.index(after: closing)
            let rawToken = String(source[opening..<end])
            let tokenBody = String(source[source.index(after: opening)..<closing])
            if let segment = segment(for: tokenBody, source: rawToken) {
                segments.append(segment)
                position = end
            } else {
                segments.append(.literal("{"))
                position = source.index(after: opening)
            }
        }

        if position < source.endIndex {
            segments.append(.literal(String(source[position...])))
        }
        return segments
    }

    private static func segment(for body: String, source: String) -> Segment? {
        guard let parts = splitOnPipes(body), let head = parts.first else { return nil }
        var modifiers: [Modifier] = []
        for raw in parts.dropFirst() {
            guard let modifier = Modifier(rawValue: raw) else { return nil }
            modifiers.append(modifier)
        }

        // Structural tokens produce no text, so a modifier on one is malformed.
        if head == "cursor" {
            return modifiers.isEmpty ? .cursor : nil
        }
        if head.hasPrefix("snippet:") {
            let key = head.dropFirst("snippet:".count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, modifiers.isEmpty else { return nil }
            return .snippetReference(key: key, source: source)
        }

        guard let token = parseToken(head) else { return nil }
        switch token.command {
        case "clipboard":
            guard let offset = intParameter(token, "offset", default: 0), offset >= 0,
                token.hasOnly(["offset"])
            else { return nil }
            return .clipboard(offset: offset, modifiers: modifiers)
        // `selectedText` is Raycast's spelling, accepted on the way in but never written out.
        case "selection", "selectedtext":
            guard token.parameters.isEmpty else { return nil }
            return .selection(modifiers: modifiers)
        case "uuid":
            guard token.parameters.isEmpty else { return nil }
            return .uuid(modifiers: modifiers)
        case "date", "time", "datetime", "day":
            guard let dateTime = parseDateTime(token) else { return nil }
            return .dateTime(dateTime, modifiers: modifiers)
        case "argument":
            guard let argument = parseArgument(token) else { return nil }
            return .argument(argument, source: source, modifiers: modifiers)
        case "snippet":
            guard let name = token.parameters["name"]?.trimmingCharacters(in: .whitespaces),
                !name.isEmpty, token.hasOnly(["name"]), modifiers.isEmpty
            else { return nil }
            return .snippetReference(key: name, source: source)
        default:
            return nil
        }
    }

    private static func parseDateTime(_ token: ParsedToken) -> DateTimeToken? {
        guard token.hasOnly(["offset", "format", "locale"]) else { return nil }
        let format = token.parameters["format"]
        let localeIdentifier = token.parameters["locale"]
        // Raycast documents these as mutually exclusive; a template asking for both is ambiguous.
        if format != nil, localeIdentifier != nil { return nil }
        if let format, format.isEmpty { return nil }
        if let localeIdentifier, localeIdentifier.isEmpty { return nil }

        var offsets: [DateTimeToken.Offset] = []
        if let raw = token.parameters["offset"] {
            guard let parsed = parseOffsets(raw) else { return nil }
            offsets = parsed
        }

        let kind: DateTimeToken.Kind
        switch token.command {
        case "date": kind = .date
        case "time": kind = .time
        case "datetime": kind = .dateTime
        default: kind = .weekday
        }
        return DateTimeToken(
            kind: kind, offsets: offsets, format: format, localeIdentifier: localeIdentifier)
    }

    /// `"+2y +5M"` / `"-3d"` — signed amounts with a unit suffix, applied in order.
    private static func parseOffsets(_ raw: String) -> [DateTimeToken.Offset]? {
        let pieces = raw.split(whereSeparator: \Character.isWhitespace)
        guard !pieces.isEmpty else { return nil }

        var offsets: [DateTimeToken.Offset] = []
        for piece in pieces {
            guard let unit = piece.last, let component = component(for: unit) else { return nil }
            let amount = piece.dropLast()
            guard let value = Int(amount), !amount.isEmpty else { return nil }
            offsets.append(DateTimeToken.Offset(component: component, value: value))
        }
        return offsets
    }

    private static func component(for unit: Character) -> Calendar.Component? {
        switch unit {
        case "m": return .minute
        case "h": return .hour
        case "d": return .day
        case "M": return .month
        case "y": return .year
        default: return nil
        }
    }

    private static func parseArgument(_ token: ParsedToken) -> ArgumentToken? {
        guard token.hasOnly(["name", "default", "options"]) else { return nil }
        let name = token.parameters["name"]?.trimmingCharacters(in: .whitespaces) ?? "Argument"
        guard !name.isEmpty else { return nil }
        let options = (token.parameters["options"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if token.parameters["options"] != nil, options.isEmpty { return nil }
        return ArgumentToken(
            name: name, options: options, defaultValue: token.parameters["default"])
    }

    private static func format(_ token: DateTimeToken, context: ExpansionContext) -> String {
        var date = context.now
        for offset in token.offsets {
            date =
                context.calendar.date(byAdding: offset.component, value: offset.value, to: date)
                ?? date
        }

        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.timeZone = context.timeZone
        formatter.locale = token.localeIdentifier.map(Locale.init(identifier:)) ?? context.locale
        if let format = token.format {
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
        switch token.kind {
        case .date:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case .time:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .dateTime:
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        case .weekday:
            formatter.dateFormat = "EEEE"
        }
        return formatter.string(from: date)
    }

    // MARK: - Token body parsing

    private struct ParsedToken {
        let command: String
        let parameters: [String: String]

        func hasOnly(_ allowed: Set<String>) -> Bool {
            parameters.keys.allSatisfy(allowed.contains)
        }
    }

    private static func intParameter(
        _ token: ParsedToken, _ key: String, default fallback: Int
    ) -> Int? {
        guard let raw = token.parameters[key] else { return fallback }
        return Int(raw)
    }

    /// Splits on pipes outside a quoted value, trimming each part.
    private static func splitOnPipes(_ body: String) -> [String]? {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false

        for character in body {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\" where inQuotes:
                current.append(character)
                escaped = true
            case "\"":
                inQuotes.toggle()
                current.append(character)
            case "|" where !inQuotes:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(character)
            }
        }
        guard !inQuotes, !escaped else { return nil }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        guard parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts
    }

    /// `date offset="+1d"` → command plus parameters. Values may be quoted or bare.
    private static func parseToken(_ head: String) -> ParsedToken? {
        var remainder = Substring(head)
        remainder = remainder.drop(while: \Character.isWhitespace)
        let command = remainder.prefix { !$0.isWhitespace && $0 != "=" }
        guard !command.isEmpty else { return nil }
        remainder = remainder.dropFirst(command.count)

        var parameters: [String: String] = [:]
        while true {
            remainder = remainder.drop(while: \Character.isWhitespace)
            if remainder.isEmpty { break }

            let key = remainder.prefix { !$0.isWhitespace && $0 != "=" }
            guard !key.isEmpty else { return nil }
            remainder = remainder.dropFirst(key.count)
            remainder = remainder.drop(while: \Character.isWhitespace)
            guard remainder.first == "=" else { return nil }
            remainder = remainder.dropFirst()
            remainder = remainder.drop(while: \Character.isWhitespace)

            let value: String
            if remainder.first == "\"" {
                remainder = remainder.dropFirst()
                guard let decoded = decodeQuoted(&remainder) else { return nil }
                value = decoded
            } else {
                let bare = remainder.prefix { !$0.isWhitespace }
                guard !bare.isEmpty else { return nil }
                remainder = remainder.dropFirst(bare.count)
                value = String(bare)
            }
            guard parameters.updateValue(value, forKey: String(key)) == nil else { return nil }
        }
        return ParsedToken(command: String(command).lowercased(), parameters: parameters)
    }

    /// Consumes a quoted value from `remainder`, leaving it positioned after the closing quote.
    private static func decodeQuoted(_ remainder: inout Substring) -> String? {
        var decoded = ""
        var escaped = false
        while let character = remainder.first {
            remainder = remainder.dropFirst()
            if escaped {
                switch character {
                case "\\": decoded.append("\\")
                case "\"": decoded.append("\"")
                case "n": decoded.append("\n")
                case "r": decoded.append("\r")
                case "t": decoded.append("\t")
                default: return nil
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return decoded
            } else {
                decoded.append(character)
            }
        }
        return nil
    }

    // MARK: - References

    private static func resolveReference(
        _ key: String,
        snippets: [StoredSnippet]
    ) -> StoredSnippet? {
        let normalizedKey = normalizeReference(key)
        // A disabled snippet is not expandable alone, so nesting must not make it so.
        let candidates = snippets.filter { $0.snippet.isEnabled }
        if let nameMatch = candidates.first(where: {
            normalizeReference($0.snippet.name) == normalizedKey
        }) {
            return nameMatch
        }
        return candidates.first(where: {
            guard let keyword = $0.snippet.keyword else { return false }
            return normalizeReference(keyword) == normalizedKey
        })
    }

    private static func normalizeReference(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: comparisonLocale)
    }
}
