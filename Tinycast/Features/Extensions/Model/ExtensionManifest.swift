import Foundation

/// What a command renders into. Only `view` and `noView` run today; the rest are recognised so the
/// launcher can label them and explain why they don't open.
enum ExtensionCommandMode: String, Sendable, Codable {
    case view
    case noView = "no-view"
    case menuBar = "menu-bar"

    /// The string the JS runtime expects (it only distinguishes mounted from headless).
    var runtimeName: String { self == .view ? "view" : "no-view" }

    var isSupported: Bool { self != .menuBar }

    var unsupportedReason: String? {
        self == .menuBar
            ? "Menu bar commands aren't supported yet — Tinycast only runs view and no-view commands."
            : nil
    }
}

/// One entry from a manifest's `preferences` array.
struct ExtensionPreferenceSchema: Sendable, Hashable {
    enum Kind: String, Sendable {
        case textfield
        case password
        case checkbox
        case dropdown
        case appPicker
        case file
        case directory

        init(raw: String?) {
            self = Kind(rawValue: raw ?? "textfield") ?? .textfield
        }
    }

    struct Option: Sendable, Hashable {
        let title: String
        let value: String
    }

    let name: String
    let title: String?
    let label: String?
    let description: String?
    let placeholder: String?
    let kind: Kind
    let required: Bool
    let options: [Option]
    /// Already resolved for macOS: a manifest default can be platform-keyed
    /// (`{"macOS": "/var/run/docker.sock", "Windows": "…"}`).
    let defaultValue: ExtensionPreferenceValue?

    /// The value to use when the user hasn't set one — falls back to a type-appropriate empty.
    var effectiveDefault: ExtensionPreferenceValue {
        defaultValue ?? (kind == .checkbox ? .bool(false) : .string(""))
    }

    var displayTitle: String { title ?? label ?? name }

    init?(json: Any) {
        guard let dict = json as? [String: Any], let name = dict["name"] as? String else { return nil }
        self.name = name
        title = dict["title"] as? String
        label = dict["label"] as? String
        description = dict["description"] as? String
        placeholder = dict["placeholder"] as? String
        kind = Kind(raw: dict["type"] as? String)
        required = dict["required"] as? Bool ?? false
        options = (dict["data"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let value = entry["value"] as? String else { return nil }
            return Option(title: entry["title"] as? String ?? value, value: value)
        }
        defaultValue = ExtensionPreferenceValue(manifestDefault: dict["default"])
    }
}

/// A preference value as it round-trips between the manifest, `UserDefaults` and JS.
enum ExtensionPreferenceValue: Sendable, Hashable {
    case string(String)
    case bool(Bool)
    case number(Double)

    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value
        case .number(let value): return value
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return value == value.rounded() ? String(Int(value)) : String(value)
        }
    }

    var boolValue: Bool {
        switch self {
        case .string(let value): return value == "true"
        case .bool(let value): return value
        case .number(let value): return value != 0
        }
    }

    init?(manifestDefault raw: Any?) {
        switch raw {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            self =
                CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue) : .number(value.doubleValue)
        case let value as [String: Any]:
            // Platform-keyed default; Tinycast is macOS-only.
            guard let macOS = value["macOS"] else { return nil }
            self.init(manifestDefault: macOS)
        default:
            return nil
        }
    }
}

/// One argument the launcher collects before a command starts.
struct ExtensionCommandArgument: Sendable, Hashable {
    let name: String
    let type: String
    let placeholder: String
    let required: Bool

    init?(json: Any) {
        guard let dict = json as? [String: Any], let name = dict["name"] as? String else { return nil }
        self.name = name
        type = dict["type"] as? String ?? "text"
        placeholder = dict["placeholder"] as? String ?? name
        required = dict["required"] as? Bool ?? false
    }
}

struct ExtensionCommand: Sendable, Hashable, Identifiable {
    let name: String
    let title: String
    let subtitle: String?
    let description: String
    let mode: ExtensionCommandMode
    let keywords: [String]
    let icon: String?
    let disabledByDefault: Bool
    let preferences: [ExtensionPreferenceSchema]
    let arguments: [ExtensionCommandArgument]

    /// Unique within its extension; `ExtensionCommandRef` pairs it with the owner for a global id.
    var id: String { name }

    /// Every declared argument must reach the command, empty string when the user left it blank — that
    /// is Raycast's contract, and extensions lean on it: `Number(args.seconds)` is `0` for `""` but
    /// `NaN` for `undefined`, which silently corrupts whatever they compute from it.
    func completeArguments(_ given: [String: String]) -> [String: String] {
        var complete = given
        for argument in arguments where complete[argument.name] == nil {
            complete[argument.name] = ""
        }
        return complete
    }

    init?(json: Any) {
        guard let dict = json as? [String: Any], let name = dict["name"] as? String,
            let title = dict["title"] as? String
        else { return nil }
        self.name = name
        self.title = title
        subtitle = dict["subtitle"] as? String
        description = dict["description"] as? String ?? ""
        mode = ExtensionCommandMode(rawValue: dict["mode"] as? String ?? "view") ?? .view
        keywords = dict["keywords"] as? [String] ?? []
        icon = dict["icon"] as? String
        disabledByDefault = dict["disabledByDefault"] as? Bool ?? false
        preferences = (dict["preferences"] as? [Any] ?? []).compactMap(ExtensionPreferenceSchema.init(json:))
        arguments = (dict["arguments"] as? [Any] ?? []).compactMap(ExtensionCommandArgument.init(json:))
    }
}

/// A Raycast extension's `package.json`, reduced to what Tinycast uses.
struct ExtensionManifest: Sendable, Hashable {
    let name: String
    let title: String
    let description: String
    let author: String
    let icon: String?
    let categories: [String]
    let platforms: [String]?
    let commands: [ExtensionCommand]
    let preferences: [ExtensionPreferenceSchema]

    /// `platforms` is absent on older manifests, which predate Windows support and are macOS-only.
    var supportsMacOS: Bool {
        guard let platforms else { return true }
        return platforms.contains { $0.caseInsensitiveCompare("macOS") == .orderedSame }
    }

    enum ParseError: LocalizedError {
        case unreadable(URL)
        case notAnExtension(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "Couldn't read \(url.lastPathComponent)."
            case .notAnExtension(let url):
                return "\(url.lastPathComponent) doesn't contain a Raycast extension manifest."
            }
        }
    }

    static func load(directory: URL) throws -> ExtensionManifest {
        let manifestURL = directory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw ParseError.unreadable(manifestURL)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let manifest = ExtensionManifest(json: json)
        else { throw ParseError.notAnExtension(directory) }
        return manifest
    }

    init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        let commands = (json["commands"] as? [Any] ?? []).compactMap(ExtensionCommand.init(json:))
        guard !commands.isEmpty else { return nil }
        self.name = name
        title = json["title"] as? String ?? name
        description = json["description"] as? String ?? ""
        author = json["author"] as? String ?? ""
        icon = json["icon"] as? String
        categories = json["categories"] as? [String] ?? []
        platforms = json["platforms"] as? [String]
        self.commands = commands
        preferences = (json["preferences"] as? [Any] ?? []).compactMap(ExtensionPreferenceSchema.init(json:))
    }
}
