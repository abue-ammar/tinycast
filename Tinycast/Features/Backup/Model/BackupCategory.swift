import Foundation

enum BackupCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case configuration
    case clipboard
    case snippets
    case notes
    case quicklinks
    case customCommands
    case windowManagement
    case learning

    var id: Self { self }

    struct Descriptor: Sendable {
        let label: String
        let symbol: String
        let tint: IconTint
        /// Where this category sits inside the bundle: its JSON file, or its directory.
        let subpath: String
    }

    var descriptor: Descriptor {
        switch self {
        case .configuration:
            return .init(
                label: String(localized: "Settings & Shortcuts"), symbol: "slider.horizontal.3",
                tint: .gray, subpath: "settings.json")
        case .clipboard:
            return .init(
                label: String(localized: "Clipboard History"), symbol: "list.clipboard.fill",
                tint: .indigo, subpath: "clipboard")
        case .snippets:
            return .init(
                label: String(localized: "Snippets"), symbol: "curlybraces", tint: .brown,
                subpath: "snippets")
        case .notes:
            return .init(
                label: String(localized: "Notes"), symbol: "text.page.fill", tint: .yellow,
                subpath: "notes")
        case .quicklinks:
            return .init(
                label: String(localized: "Quicklinks"), symbol: "link", tint: .blue,
                subpath: "quicklinks.json")
        case .customCommands:
            return .init(
                label: String(localized: "Custom Commands"), symbol: "terminal.fill", tint: .graphite,
                subpath: "custom-commands.json")
        case .windowManagement:
            return .init(
                label: String(localized: "Window Management"), symbol: "macwindow", tint: .mint,
                subpath: "window-management.json")
        case .learning:
            return .init(
                label: String(localized: "Launcher Learning"), symbol: "chart.line.uptrend.xyaxis",
                tint: .gray, subpath: "learning")
        }
    }

    /// Nil where a number would say nothing.
    func countText(_ count: Int) -> String? {
        switch self {
        case .configuration: return nil
        case .clipboard: return String(localized: "\(count) clips")
        case .snippets: return String(localized: "\(count) snippets")
        case .notes: return String(localized: "\(count) notes")
        case .quicklinks: return String(localized: "\(count) quicklinks")
        case .customCommands: return String(localized: "\(count) custom commands")
        case .windowManagement: return String(localized: "\(count) layouts, rooms and sizes")
        case .learning: return String(localized: "\(count) records")
        }
    }

    static let all = Set(BackupCategory.allCases)

    /// Declaration order, so the picker, the manifest and the summary all list the same way.
    static func ordered(_ selection: Set<BackupCategory>) -> [BackupCategory] {
        allCases.filter(selection.contains)
    }
}
