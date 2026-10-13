import Foundation

/// Something in settings.json Tinycast could not use, said the way the HUD says it.
enum SettingsFileIssue: Error, Equatable, Sendable {
    /// `JSONSerialization`'s own account, which names the line and column.
    case invalidJSON(String)
    /// The path whose value had to be an object; nil is the file itself.
    case notAnObject(String?)
    case unknownSetting(String)
    case invalidValue(SettingsFileKey)
    case invalidEntry(SettingsFileKey, String)
    case unreadable
    case unwritable

    var message: String {
        switch self {
        case .invalidJSON(let detail): "not valid JSON — \(detail)"
        case .notAnObject(nil): "the file must hold one JSON object"
        case .notAnObject(let path?): "“\(path)” must be an object"
        case .unknownSetting(let path): "unknown setting “\(path)”"
        case .invalidValue(let key): "“\(key.rawValue)” has a value Tinycast can't use"
        case .invalidEntry(let key, let detail): "“\(key.rawValue)”: \(detail)"
        case .unreadable: "couldn't be read"
        case .unwritable: "couldn't be saved"
        }
    }

    static func summary(_ issues: [SettingsFileIssue]) -> String? {
        guard let first = issues.first else { return nil }
        let more = issues.count > 1 ? " (+\(issues.count - 1) more)" : ""
        return "settings.json: \(first.message)\(more)"
    }
}
