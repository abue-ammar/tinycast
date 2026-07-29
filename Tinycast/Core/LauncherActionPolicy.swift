import Foundation

enum LauncherEntryKind: String, Sendable {
    case application
    case systemSettings
    case command
}

enum LauncherModifiedReturnAction: Equatable {
    case showInFinder
}

/// Keeps the advertised launcher shortcut and its key handler on the same entry-capability rule.
enum LauncherActionPolicy {
    nonisolated static func modifiedReturnAction(
        for kind: LauncherEntryKind
    ) -> LauncherModifiedReturnAction? {
        switch kind {
        case .application, .systemSettings: return .showInFinder
        case .command: return nil
        }
    }
}
