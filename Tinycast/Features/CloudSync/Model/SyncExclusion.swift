import Foundation

enum SyncExclusion: CaseIterable, Sendable {
    case copiedFiles, customCommands, searchRanking, credentials, macSpecific

    var title: String {
        switch self {
        case .copiedFiles: String(localized: "Copied Files")
        case .customCommands: String(localized: "Custom Commands")
        case .searchRanking: String(localized: "Search Ranking")
        case .credentials: String(localized: "Passwords & API Keys")
        case .macSpecific: String(localized: "Mac-Specific Settings")
        }
    }

    var symbol: String {
        switch self {
        case .copiedFiles: "doc.on.doc.fill"
        case .customCommands: "terminal.fill"
        case .searchRanking: "magnifyingglass"
        case .credentials: "key.fill"
        case .macSpecific: "desktopcomputer"
        }
    }

    var tint: IconTint {
        switch self {
        case .copiedFiles: .indigo
        case .customCommands: .graphite
        case .searchRanking, .credentials, .macSpecific: .gray
        }
    }

    var detail: String {
        switch self {
        case .copiedFiles:
            String(localized: "History keeps where a copied file is on this Mac, not the file.")
        case .customCommands:
            String(localized: "They run code, so each Mac keeps its own.")
        case .searchRanking:
            String(localized: "Tinycast learns what you pick on each Mac, so ranking stays there.")
        case .credentials:
            String(localized: "API keys, server credentials and extension passwords are never synced.")
        case .macSpecific:
            String(
                localized: """
                    Feature switches, permissions, folders, language, search scopes and the palette's \
                    position stay on each Mac.
                    """)
        }
    }
}
