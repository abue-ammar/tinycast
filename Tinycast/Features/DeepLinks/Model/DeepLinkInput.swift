import Foundation

/// What a link carries besides its target, under Raycast's parameter names.
struct DeepLinkInput: Equatable, Sendable {
    enum Arguments: Equatable, Sendable {
        case named([String: String])
        case positional([String])
    }

    /// Bounds what a link can push into a field; nothing typed by hand comes near it.
    static let maximumParameterLength = 65_536
    static let none = DeepLinkInput(fallbackText: nil, arguments: nil, context: [:])

    var fallbackText: String?
    var arguments: Arguments?
    var context: [String: String]

    init(fallbackText: String?, arguments: Arguments?, context: [String: String]) {
        self.fallbackText = fallbackText
        self.arguments = arguments
        self.context = context
    }

    /// Nil when a parameter is malformed or oversized: the link fails rather than run without it.
    init?(queryItems: [URLQueryItem]) {
        var input = Self.none
        var launchContext: [String: String]?
        for item in queryItems {
            guard let value = item.value, !value.isEmpty else { continue }
            guard value.count <= Self.maximumParameterLength else { return nil }
            switch item.name.lowercased() {
            case "fallbacktext":
                input.fallbackText = value
            case "arguments":
                guard let arguments = Self.arguments(fromJSON: value) else { return nil }
                input.arguments = arguments
            case "context":
                guard let context = Self.object(fromJSON: value) else { return nil }
                input.context = context
            case "launchcontext":
                guard let context = Self.object(fromJSON: value) else { return nil }
                launchContext = context
            default:
                continue
            }
        }
        // Raycast reads `launchContext` first, so a link carrying both means that one.
        if let launchContext { input.context = launchContext }
        self = input
    }

    var isEmpty: Bool { fallbackText == nil && arguments == nil && context.isEmpty }

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
        if let named = object(fromJSON: raw) { return .named(named) }
        guard let values = try? JSONDecoder().decode([Scalar].self, from: Data(raw.utf8)) else {
            return nil
        }
        let texts = values.compactMap(\.text)
        return texts.count == values.count ? .positional(texts) : nil
    }

    private static func object(fromJSON raw: String) -> [String: String]? {
        guard let values = try? JSONDecoder().decode([String: Scalar].self, from: Data(raw.utf8))
        else { return nil }
        let texts = values.compactMapValues(\.text)
        return texts.count == values.count ? texts : nil
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
