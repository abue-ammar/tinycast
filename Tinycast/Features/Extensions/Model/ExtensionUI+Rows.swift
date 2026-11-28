import Foundation

/// What the extension screen selects and acts on, whichever tree it draws.
nonisolated extension ExtensionUI {
    struct Row: Identifiable, Sendable, Equatable {
        let id: String
        /// The first runs on Return.
        let actions: [Action]
    }

    /// List and Grid items in section order; a Detail is one row; a Form or a MenuBar has none.
    var rows: [Row] {
        switch self {
        case .list(let list):
            list.sections.flatMap(\.items).map { Row(id: $0.id, actions: $0.actions) }
        case .grid(let grid):
            grid.sections.flatMap(\.items).map { Row(id: $0.id, actions: $0.actions) }
        case .detail(let detail):
            [Row(id: Self.detailRowID, actions: detail.actions)]
        case .form, .menuBar:
            []
        }
    }

    /// The main app filters a List or Grid itself unless this is true.
    var handlesSearch: Bool {
        switch self {
        case .list(let list): list.handlesSearch
        case .grid(let grid): grid.handlesSearch
        case .detail, .form, .menuBar: false
        }
    }

    var searchPlaceholder: String? {
        switch self {
        case .list(let list): list.searchPlaceholder
        case .grid(let grid): grid.searchPlaceholder
        case .detail, .form, .menuBar: nil
        }
    }

    /// The wire name, as the extension sent it.
    var typeName: String {
        switch self {
        case .list: "list"
        case .grid: "grid"
        case .detail: "detail"
        case .form: "form"
        case .menuBar: "menu-bar"
        }
    }

    private static let detailRowID = "detail"
}
