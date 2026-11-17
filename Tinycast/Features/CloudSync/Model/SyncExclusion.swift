import Foundation

enum SyncExclusion: CaseIterable, Sendable {
    case clipboardHistory, customCommands, searchRanking, credentials, macSpecific

    var title: String {
        switch self {
        case .clipboardHistory: String(localized: "Clipboard History")
        case .customCommands: String(localized: "Custom Commands")
        case .searchRanking: String(localized: "Search Ranking")
        case .credentials: String(localized: "Passwords & API Keys")
        case .macSpecific: String(localized: "Mac-Specific Settings")
        }
    }

    var symbol: String {
        switch self {
        case .clipboardHistory: "doc.on.clipboard"
        case .customCommands: "terminal"
        case .searchRanking: "magnifyingglass"
        case .credentials: "key"
        case .macSpecific: "desktopcomputer"
        }
    }

    var detail: String {
        switch self {
        case .clipboardHistory:
            String(localized: "What you copy stays on the Mac you copied it on.")
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
