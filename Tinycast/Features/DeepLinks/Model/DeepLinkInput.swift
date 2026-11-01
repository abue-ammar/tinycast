import Foundation

/// What a link carries besides its target: text, field values and an editor's contents.
struct DeepLinkInput: Equatable, Sendable {
    enum Arguments: Equatable, Sendable {
        case named([String: String])
        case positional([String])
    }

    /// One object fills an editor; a list of them is a batch to add.
    enum Context: Equatable, Sendable {
        case fields([String: String])
        case list([[String: String]])
    }

    /// Bytes, not characters: one character can carry any number of combining marks.
    static let maximumParameterBytes = 65_536
    static let none = DeepLinkInput()
    /// RFC 3986's unreserved set, so an encoded value survives any reader of the link intact.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    var fallbackText: String?
    var arguments: Arguments?
    var context: Context?

    init(fallbackText: String? = nil, arguments: Arguments? = nil, context: Context? = nil) {
        self.fallbackText = fallbackText
        self.arguments = arguments
        self.context = context
    }

    /// Nil when a parameter is malformed or oversized: the link fails rather than run without it.
    init?(queryItems: [URLQueryItem]) {
        var input = Self.none
        for item in queryItems {
            guard let value = item.value, !value.isEmpty else { continue }
            guard value.utf8.count <= Self.maximumParameterBytes else { return nil }
            switch item.name.lowercased() {
            case "fallbacktext":
                input.fallbackText = value
            case "arguments":
                guard let arguments = Self.arguments(fromJSON: value) else { return nil }
                input.arguments = arguments
            case "context":
                guard let context = Self.context(fromJSON: value) else { return nil }
                input.context = context
            default:
                continue
            }
        }
        self = input
    }

    var isEmpty: Bool { fallbackText == nil && arguments == nil && context == nil }

    var contextFields: [String: String]? {
        guard case .fields(let fields)? = context else { return nil }
        return fields
    }

    /// The input as a reader checks it before letting a link run with it; long input is cut.
    var summary: String {
        let full = [fallbackText, arguments.flatMap(Self.json), context.flatMap(Self.json)]
            .compactMap { $0 }.joined(separator: " · ")
        return full.count > Self.summaryLength ? String(full.prefix(Self.summaryLength)) + "…" : full
    }

    private static let summaryLength = 160

    /// The inverse of `init?(queryItems:)`, encoded strictly so the link reads back exactly.
    var percentEncodedQueryItems: [URLQueryItem] {
        let values: [(String, String?)] = [
            ("fallbackText", fallbackText),
            ("arguments", arguments.flatMap(Self.json)),
            ("context", context.flatMap(Self.json))
        ]
        return values.compactMap { name, value in
            value.flatMap { $0.addingPercentEncoding(withAllowedCharacters: Self.unreserved) }
                .map { URLQueryItem(name: name, value: $0) }
        }
    }

    /// Named values fill the first field of that name; with no arguments, `fallbackText` the first.
    func fieldValues(names: [String], fieldID: (Int) -> String) -> [String: String] {
        switch arguments ?? fallbackText.map({ .positional([$0]) }) {
        case nil:
            return [:]
        case .positional(let values):
            return Dictionary(
                zip(names.indices, values).map { (fieldID($0), $1) }, uniquingKeysWith: { first, _ in first })
        case .named(let values):
            var filled: [String: String] = [:]
            var claimedNames: Set<String> = []
            for (index, name) in names.enumerated() where !claimedNames.contains(name) {
                guard let value = values[name] else { continue }
                claimedNames.insert(name)
                filled[fieldID(index)] = value
            }
            return filled
        }
    }

    private static func arguments(fromJSON raw: String) -> Arguments? {
        if let named = decode([String: Scalar].self, from: raw).flatMap(texts) { return .named(named) }
        return decode([Scalar].self, from: raw).flatMap(texts).map(Arguments.positional)
    }

    private static func context(fromJSON raw: String) -> Context? {
        if let fields = decode([String: Scalar].self, from: raw).flatMap(texts) { return .fields(fields) }
        guard let list = decode([[String: Scalar]].self, from: raw) else { return nil }
        let objects = list.compactMap(texts)
        return objects.count == list.count ? .list(objects) : nil
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from raw: String) -> Value? {
        try? JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    /// Nil when any value was nested, so a half-read object never passes for the whole one.
    private static func texts(_ values: [String: Scalar]) -> [String: String]? {
        let texts = values.compactMapValues(\.text)
        return texts.count == values.count ? texts : nil
    }

    private static func texts(_ values: [Scalar]) -> [String]? {
        let texts = values.compactMap(\.text)
        return texts.count == values.count ? texts : nil
    }

    private static func json(_ arguments: Arguments) -> String? {
        switch arguments {
        case .named(let values): encoded(values)
        case .positional(let values): encoded(values)
        }
    }

    private static func json(_ context: Context) -> String? {
        switch context {
        case .fields(let values): encoded(values)
        case .list(let values): encoded(values)
        }
    }

    private static func encoded(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// A JSON scalar as the text a field would hold; nested objects and arrays have none.
    private struct Scalar: Decodable {
        let text: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                text = ""
            } else if let string = try? container.decode(String.self) {
                text = string
            } else if let bool = try? container.decode(Bool.self) {
                text = bool ? "true" : "false"
            } else if let integer = try? container.decode(Int64.self) {
                text = String(integer)
            } else if let number = try? container.decode(Double.self) {
                text = String(number)
            } else {
                text = nil
            }
        }
    }
}
