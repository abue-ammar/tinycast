import Foundation

/// A prop value as it arrives from the extension runtime. `handler` is a callback the palette can
/// dispatch back; `node` is an element-valued prop the runtime hoisted out of a `__slot` (an
/// `ActionPanel` on `actions`, a `Detail.Metadata` on `metadata`, …).
enum RenderValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case handler(String)
    case array([RenderValue])
    case object([String: RenderValue])
    case node(RenderNode)
    case null

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            // Whole numbers arrive as Doubles; an accessory reading "3.0" would be wrong.
            return value == value.rounded() && value.magnitude < 1e15
                ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var dateValue: Date? {
        if case .date(let date) = self { return date }
        return nil
    }

    var handlerID: String? {
        if case .handler(let id) = self { return id }
        return nil
    }

    var arrayValue: [RenderValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var objectValue: [String: RenderValue]? {
        if case .object(let values) = self { return values }
        return nil
    }

    var nodeValue: RenderNode? {
        if case .node(let node) = self { return node }
        return nil
    }

    /// A slot prop holding several nodes (`ActionPanel` children hoisted from a submenu) or one.
    var nodesValue: [RenderNode] {
        switch self {
        case .node(let node): return [node]
        case .array(let values): return values.compactMap(\.nodeValue)
        default: return []
        }
    }

    /// Plain-JSON form, for handing a value back to JS unchanged (a Form field's current value).
    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .date(let value): return ["$date": ISO8601DateFormatter().string(from: value)]
        case .handler(let id): return ["$fn": id]
        case .array(let values): return values.map(\.jsonValue)
        case .object(let values): return values.mapValues(\.jsonValue)
        case .node: return NSNull()
        case .null: return NSNull()
        }
    }

    /// Decode a JSON array — how host-call arguments cross from the JS queue to the main actor as
    /// `Sendable` values.
    static func arguments(from json: String) -> [RenderValue] {
        ExtensionRuntime.jsonArray(from: json).map(RenderValue.init(json:))
    }

    init(json: Any) {
        switch json {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            // NSNumber erases Bool; CFBoolean identity is the only reliable discriminator.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [Any]:
            self = .array(value.map(RenderValue.init(json:)))
        case let value as [String: Any]:
            if let handler = value["$fn"] as? String {
                self = .handler(handler)
            } else if let iso = value["$date"] as? String {
                self = .date(RenderValue.parseDate(iso) ?? Date())
            } else if let node = RenderNode(json: value), node.isElement {
                self = .node(node)
            } else {
                self = .object(value.mapValues(RenderValue.init(json:)))
            }
        default:
            self = .null
        }
    }

    /// `Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter`: the format style is `Sendable`, so it
    /// can be a shared constant under strict concurrency. JS always sends fractional seconds; the
    /// whole-second parse is the fallback for a hand-built value.
    private static let fractionalISO = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainISO = Date.ISO8601FormatStyle()

    static func parseDate(_ text: String) -> Date? {
        (try? fractionalISO.parse(text)) ?? (try? plainISO.parse(text))
    }
}

/// One node of the tree an extension's React render produced.
struct RenderNode: Sendable, Equatable, Identifiable {
    let id: Int
    let type: String
    let props: [String: RenderValue]
    let children: [RenderNode]
    /// Set only for text nodes (`type == "#text"`).
    let text: String?

    var isText: Bool { type == "#text" }
    /// True for a real host element — the discriminator that keeps an ordinary prop object (`{type:
    /// "day"}` on Action.PickDate) from being mistaken for a hoisted slot node.
    var isElement: Bool { !isText && id > 0 }

    init(
        id: Int, type: String, props: [String: RenderValue] = [:], children: [RenderNode] = [],
        text: String? = nil
    ) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
        self.text = text
    }

    init?(json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        if type == "#text" {
            self.init(id: 0, type: type, text: json["text"] as? String ?? "")
            return
        }
        guard let id = json["id"] as? Int, let rawProps = json["props"] as? [String: Any],
            let rawChildren = json["children"] as? [Any]
        else { return nil }
        self.init(
            id: id, type: type,
            props: rawProps.mapValues(RenderValue.init(json:)),
            children: rawChildren.compactMap { ($0 as? [String: Any]).flatMap(RenderNode.init(json:)) })
    }

    // MARK: - Prop access

    func string(_ key: String) -> String? { props[key]?.stringValue }
    func bool(_ key: String) -> Bool? { props[key]?.boolValue }
    func double(_ key: String) -> Double? { props[key]?.doubleValue }
    func date(_ key: String) -> Date? { props[key]?.dateValue }
    func handler(_ key: String) -> String? { props[key]?.handlerID }
    func node(_ key: String) -> RenderNode? { props[key]?.nodeValue }
    func nodes(_ key: String) -> [RenderNode] { props[key]?.nodesValue ?? [] }
    func array(_ key: String) -> [RenderValue] { props[key]?.arrayValue ?? [] }
    func object(_ key: String) -> [String: RenderValue]? { props[key]?.objectValue }

    /// Concatenated text of this node's direct text children — how `Form.Description`-style content
    /// and stray JSX strings arrive.
    var textContent: String {
        children.compactMap { $0.isText ? $0.text : nil }.joined()
    }

    /// Depth-first search for the first descendant of `type`, following hoisted slot props too.
    func firstDescendant(ofType type: String) -> RenderNode? {
        if self.type == type { return self }
        for child in children {
            if let hit = child.firstDescendant(ofType: type) { return hit }
        }
        for value in props.values {
            for node in value.nodesValue {
                if let hit = node.firstDescendant(ofType: type) { return hit }
            }
        }
        return nil
    }
}

/// The root the runtime pushes after every commit: one `__screen` per entry on the navigation stack.
struct RenderTree: Sendable, Equatable {
    let screens: [RenderNode]

    init(screens: [RenderNode]) {
        self.screens = screens
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let children = root["children"] as? [Any]
        else { return nil }
        let nodes = children.compactMap { ($0 as? [String: Any]).flatMap(RenderNode.init(json:)) }
        // A no-view command renders nothing; a view command wraps every screen in `__screen`.
        screens = nodes.filter { $0.type == "__screen" }
    }

    /// The screen the palette shows — the top of the navigation stack.
    var active: RenderNode? {
        screens.last { $0.bool("active") == true } ?? screens.last
    }

    /// The single root component of the active screen (a `List`, `Detail`, `Form`, `Grid`, …).
    var activeRoot: RenderNode? {
        active?.children.first { !$0.isText }
    }

    var depth: Int { max(screens.count, 1) }
}
