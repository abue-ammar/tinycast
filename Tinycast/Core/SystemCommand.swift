import Foundation

struct SystemCommand: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case lockScreen = "lock-screen"
        case sleep
        case sleepDisplays = "sleep-displays"
        case restart
    }

    enum Confirmation: String, Sendable {
        case none
        case required
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let confirmation: Confirmation

    var entryID: String { "system-command:" + id.rawValue }
}

enum SystemCommandCatalog {
    static let all: [SystemCommand] = SystemCommand.ID.allCases.map { id in
        SystemCommand(
            id: id, name: name(for: id), sfSymbol: symbol(for: id),
            confirmation: confirmation(for: id))
    }

    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })

    static func command(forEntryID entryID: String) -> SystemCommand? {
        byEntryID[entryID]
    }

    private static func name(for id: SystemCommand.ID) -> String {
        switch id {
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .sleepDisplays: return "Sleep Displays"
        case .restart: return "Restart"
        }
    }

    private static func symbol(for id: SystemCommand.ID) -> String {
        switch id {
        case .lockScreen: return "lock"
        case .sleep: return "moon.zzz"
        case .sleepDisplays: return "display"
        case .restart: return "arrow.clockwise"
        }
    }

    private static func confirmation(for id: SystemCommand.ID) -> SystemCommand.Confirmation {
        switch id {
        case .restart:
            return .required
        default:
            return .none
        }
    }
}
