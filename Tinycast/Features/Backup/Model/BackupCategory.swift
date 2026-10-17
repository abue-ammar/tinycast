import Foundation

enum BackupCategory: String, CaseIterable, Identifiable, Sendable {
    case configuration
    case clipboard
    case snippets
    case notes
    case learning

    var id: Self { self }

    struct Descriptor: Sendable {
        let label: String
        let symbol: String
        /// Where this category's files sit inside the bundle; empty means the bundle root.
        let subpath: String
    }

    var descriptor: Descriptor {
        switch self {
        case .configuration:
            return .init(
                label: String(localized: "Settings & Shortcuts"), symbol: "slider.horizontal.3",
                subpath: "")
        case .clipboard:
            return .init(
                label: String(localized: "Clipboard History"), symbol: "doc.on.clipboard",
                subpath: "clipboard")
        case .snippets:
            return .init(
                label: String(localized: "Snippets"), symbol: "curlybraces", subpath: "snippets")
        case .notes:
            return .init(label: String(localized: "Notes"), symbol: "note.text", subpath: "notes")
        case .learning:
            return .init(
                label: String(localized: "Launcher Learning"), symbol: "chart.line.uptrend.xyaxis",
                subpath: "learning")
        }
    }

    /// Nil where a number would say nothing.
    func countText(_ count: Int) -> String? {
        switch self {
        case .configuration: return nil
        case .clipboard: return String(localized: "\(count) clips")
        case .snippets: return String(localized: "\(count) snippets")
        case .notes: return String(localized: "\(count) notes")
        case .learning: return String(localized: "\(count) records")
        }
    }

    static let all = Set(BackupCategory.allCases)

    /// Declaration order, so the picker, the manifest and the summary all list the same way.
    static func ordered(_ selection: Set<BackupCategory>) -> [BackupCategory] {
        allCases.filter(selection.contains)
    }
}
