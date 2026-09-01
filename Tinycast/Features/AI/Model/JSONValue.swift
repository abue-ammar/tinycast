import Foundation

/// A decoded JSON tree, for payloads whose shape is the sender's rather than ours.
enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(_ value: Any) {
        switch value {
        case is NSNull: self = .null
        // `0`/`1` bridge to Bool too, so only a CFBoolean box counts as one.
        case let value as NSNumber:
            self =
                CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue) : .number(value.doubleValue)
        case let value as String: self = .string(value)
        case let value as [Any]: self = .array(value.map(JSONValue.init))
        case let value as [String: Any]: self = .object(value.mapValues(JSONValue.init))
        default: self = .null
        }
    }

    /// Parsed from bytes, so a schema or an argument blob can be carried without being understood.
    init?(data: Data) {
        guard
            let parsed = try? JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed])
        else { return nil }
        self.init(parsed)
    }

    /// Back to the `JSONSerialization` shape, so a value can be re-encoded into another request.
    var jsonObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.jsonObject)
        case .object(let value): return value.mapValues(\.jsonObject)
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }
}
