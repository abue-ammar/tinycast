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
        case .invalidJSON(let detail): String(localized: "not valid JSON — \(detail)")
        case .notAnObject(nil): String(localized: "the file must hold one JSON object")
        case .notAnObject(let path?): String(localized: "“\(path)” must be an object")
        case .unknownSetting(let path): String(localized: "unknown setting “\(path)”")
        case .invalidValue(let key): String(localized: "“\(key.rawValue)” has a value Tinycast can't use")
        case .invalidEntry(let key, let detail): "“\(key.rawValue)”: \(detail)"
        case .unreadable: String(localized: "couldn't be read")
        case .unwritable: String(localized: "couldn't be saved")
        }
    }

    static func summary(_ issues: [SettingsFileIssue]) -> String? {
        guard let first = issues.first else { return nil }
        guard issues.count > 1 else { return "settings.json: \(first.message)" }
        return String(localized: "settings.json: \(first.message) (+\(issues.count - 1) more)")
    }
}
