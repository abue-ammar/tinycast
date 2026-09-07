import Foundation

enum ExtensionLaunchError: LocalizedError {
    case unknownCommand(String)
    case unsupported(String)
    case notBuilt(String)
    case missingPreferences([ExtensionPreferenceSchema])

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let id): return "No installed extension provides '\(id)'."
        case .unsupported(let reason): return reason
        case .notBuilt(let name):
            return "\(name) has no built bundle — reinstall the extension."
        case .missingPreferences(let schemas):
            let names = schemas.map(\.displayTitle).joined(separator: ", ")
            return "This command needs its preferences set first: \(names)."
        }
    }
}
