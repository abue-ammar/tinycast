import Foundation
import SwiftUI

/// The one source of row order, so the palette's flat `selection` maps 1:1 onto visible rows.
struct ExtensionScreen: Equatable {
    enum Kind: Equatable {
        case list
        case grid(ExtensionGridLayout)
        case detail
        case form
        /// A root component Tinycast doesn't render (`MenuBarExtra`), or nothing rendered yet.
        case unsupported(String)
    }

    /// `id` is the scroll target: an `.id()` inside a row exists only once it is realized.
    struct Item: Equatable, Identifiable {
        let node: RenderNode
        let index: Int

        var id: String { "item:\(node.id)" }
    }

    enum Row: Equatable, Identifiable {
        case header(title: String, subtitle: String?, id: String)
        case item(Item)

        var id: String {
            switch self {
            case .header(_, _, let id): return "header:" + id
            case .item(let item): return item.id
            }
        }
    }

    let kind: Kind
    let root: RenderNode?
    let rows: [Row]
    /// Selectable rows in visible order — what `selection` indexes.
    let items: [Item]
    /// Fields of a Form, in order.
    let fields: [RenderNode]
    let isLoading: Bool
    let navigationTitle: String?
    let searchPlaceholder: String?
    /// True when the palette filters rows itself; false when the extension owns the search text.
    let filtersLocally: Bool
    let searchTextHandler: String?
    let selectionHandler: String?
    let searchBarAccessory: RenderNode?
    /// The `List`-level `isShowingDetail`; when set, rows get a detail pane beside them.
    let showsDetail: Bool
    /// Actions attached to the screen itself (`Detail`/`Form`/`List` level).
    let screenActions: RenderNode?
    /// An `EmptyView` to show when there are no rows.
    let emptyView: RenderNode?

    /// Selectable rows per section: what grid navigation needs to keep a column across a heading.
    var sectionCounts: [Int] {
        var counts: [Int] = []
        for row in rows {
            switch row {
            case .header:
                counts.append(0)
            case .item:
                if counts.isEmpty { counts.append(0) }
                counts[counts.count - 1] += 1
            }
        }
        // An empty section is drawn but holds nothing to land on, so it isn't a row of the grid.
        return counts.filter { $0 > 0 }
    }

    static let empty = ExtensionScreen(
        kind: .unsupported(""), root: nil, rows: [], items: [], fields: [], isLoading: false,
        navigationTitle: nil, searchPlaceholder: nil, filtersLocally: false, searchTextHandler: nil,
        selectionHandler: nil, searchBarAccessory: nil, showsDetail: false, screenActions: nil,
        emptyView: nil)

    /// Filters rows by `query` only when the extension hasn't taken the search text over.
    init(tree: RenderTree, query: String) {
        guard let root = tree.activeRoot else {
            self = .empty
            return
        }
        self.root = root
        isLoading = root.bool("isLoading") ?? false
        navigationTitle = root.string("navigationTitle")
        searchPlaceholder = root.string("searchBarPlaceholder")
        searchTextHandler = root.handler("onSearchTextChange")
        selectionHandler = root.handler("onSelectionChange")
        searchBarAccessory = root.node("searchBarAccessory")
        showsDetail = root.bool("isShowingDetail") ?? false
        screenActions = root.node("actions")
        filtersLocally = root.bool("filtering") ?? (searchTextHandler == nil)

        switch root.type {
        case "List":
            kind = .list
        case "Grid":
            kind = .grid(ExtensionGridLayout(root))
        case "Detail":
            kind = .detail
        case "Form":
            kind = .form
        default:
            kind = .unsupported(root.type)
        }

        switch kind {
        case .list, .grid:
            let itemType = root.type == "Grid" ? "Grid.Item" : "List.Item"
            let sectionType = root.type == "Grid" ? "Grid.Section" : "List.Section"
            let emptyType = root.type == "Grid" ? "Grid.EmptyView" : "List.EmptyView"
            emptyView = root.children.first { $0.type == emptyType }
            let needle = FuzzyMatch.Query(
                filtersLocally ? query.trimmingCharacters(in: .whitespaces) : "")
            var rows: [Row] = []
            var items: [Item] = []
            // Numbering as rows are built keeps `selection` and the drawn order in step.
            func append(_ node: RenderNode) {
                let item = Item(node: node, index: items.count)
                items.append(item)
                rows.append(.item(item))
            }
            for child in root.children {
                if child.type == sectionType {
                    let matching = child.children
                        .filter { $0.type == itemType }
                        .filter { ExtensionScreen.matches($0, needle) }
                    guard !matching.isEmpty else { continue }
                    rows.append(
                        .header(
                            title: child.string("title") ?? "",
                            subtitle: child.string("subtitle"), id: String(child.id)))
                    matching.forEach(append)
                } else if child.type == itemType, ExtensionScreen.matches(child, needle) {
                    append(child)
                }
            }
            self.rows = rows
            self.items = items
            fields = []

        case .form:
            fields = root.children.filter { $0.type.hasPrefix("Form.") }
            rows = []
            // A form's focusable fields are its selectable rows, so ↑/↓ and ⇥ walk one order.
            var fieldItems: [Item] = []
            for field in fields where ExtensionFormField(type: field.type).isFocusable {
                fieldItems.append(Item(node: field, index: fieldItems.count))
            }
            items = fieldItems
            emptyView = nil

        case .detail, .unsupported:
            rows = []
            items = []
            fields = []
            emptyView = nil
        }
    }

    private init(
        kind: Kind, root: RenderNode?, rows: [Row], items: [Item], fields: [RenderNode],
        isLoading: Bool, navigationTitle: String?, searchPlaceholder: String?, filtersLocally: Bool,
        searchTextHandler: String?, selectionHandler: String?, searchBarAccessory: RenderNode?,
        showsDetail: Bool, screenActions: RenderNode?, emptyView: RenderNode?
    ) {
        self.kind = kind
        self.root = root
        self.rows = rows
        self.items = items
        self.fields = fields
        self.isLoading = isLoading
        self.navigationTitle = navigationTitle
        self.searchPlaceholder = searchPlaceholder
        self.filtersLocally = filtersLocally
        self.searchTextHandler = searchTextHandler
        self.selectionHandler = selectionHandler
        self.searchBarAccessory = searchBarAccessory
        self.showsDetail = showsDetail
        self.screenActions = screenActions
        self.emptyView = emptyView
    }

    /// Title, subtitle and keywords, ranked by the launcher's matcher, as Raycast does.
    static func matches(_ item: RenderNode, _ needle: FuzzyMatch.Query) -> Bool {
        guard !needle.isEmpty else { return true }
        var haystack = [item.string("title") ?? ""]
        if let subtitle = item.string("subtitle") { haystack.append(subtitle) }
        haystack.append(contentsOf: item.array("keywords").compactMap(\.stringValue))
        return haystack.contains { FuzzyMatch.score(needle, candidate: $0) != nil }
    }

    /// The `ActionPanel` that applies to the current selection: the item's own, else the screen's.
    func actionPanel(forItemAt index: Int) -> RenderNode? {
        if items.indices.contains(index), let panel = items[index].node.node("actions") {
            return panel
        }
        return screenActions
    }

    /// Where a drawn field sits in the focus order, or nil for one that is never landed on.
    func focusItem(for field: RenderNode) -> Item? {
        items.first { $0.node.id == field.id }
    }

    /// The field a form opens on: the one that asked for it, else the first one there is.
    var autoFocusedField: Int {
        items.first { $0.node.bool("autoFocus") == true }?.index ?? 0
    }

    /// Submenus flatten one level with their title prefixed: the palette's menu is flat.
    static func actions(in panel: RenderNode?) -> [ExtensionAction] {
        guard let panel else { return [] }
        var result: [ExtensionAction] = []
        func walk(_ node: RenderNode, sectionTitle: String?) {
            for child in node.children {
                switch child.type {
                case "Action":
                    result.append(ExtensionAction(node: child, section: sectionTitle))
                case "ActionPanel.Section":
                    walk(child, sectionTitle: child.string("title"))
                case "ActionPanel.Submenu":
                    walk(child, sectionTitle: child.string("title") ?? sectionTitle)
                default:
                    break
                }
            }
        }
        walk(panel, sectionTitle: nil)
        return result
    }
}

/// One activatable action from an `ActionPanel`.
struct ExtensionAction: Equatable, Identifiable {
    let node: RenderNode
    let section: String?

    var id: Int { node.id }
    var title: String { node.string("title") ?? "Action" }
    var handler: String? { node.handler("onAction") }
    var isDestructive: Bool { node.string("style") == "destructive" }
    var iconValue: RenderValue? { node.props["icon"] }

    /// `{modifiers: ["cmd","shift"], key: "c"}` rendered as the palette's keycap glyphs.
    var shortcutCaps: [String]? {
        guard let shortcut = node.object("shortcut") else { return nil }
        // A cross-platform shortcut nests the real one under `macOS`.
        let resolved = shortcut["macOS"]?.objectValue ?? shortcut
        guard let key = resolved["key"]?.stringValue else { return nil }
        let modifiers = (resolved["modifiers"]?.arrayValue ?? []).compactMap(\.stringValue)
        var caps = modifiers.compactMap { modifier -> String? in
            switch modifier {
            case "cmd": return "⌘"
            case "ctrl": return "⌃"
            case "opt", "alt": return "⌥"
            case "shift": return "⇧"
            default: return nil
            }
        }
        caps.append(ExtensionAction.keyCap(key))
        return caps
    }

    /// Modifiers must match exactly, so ⌘⇧C never fires a plain ⌘C action.
    func matches(key: KeyEquivalent, modifiers: EventModifiers) -> Bool {
        guard let shortcut = node.object("shortcut") else { return false }
        let resolved = shortcut["macOS"]?.objectValue ?? shortcut
        guard let declared = resolved["key"]?.stringValue else { return false }
        let declaredModifiers = (resolved["modifiers"]?.arrayValue ?? []).compactMap(\.stringValue)

        var expected: EventModifiers = []
        for modifier in declaredModifiers {
            switch modifier {
            case "cmd": expected.insert(.command)
            case "ctrl": expected.insert(.control)
            case "opt", "alt": expected.insert(.option)
            case "shift": expected.insert(.shift)
            default: break
            }
        }
        let pressed: EventModifiers = [.command, .control, .option, .shift].filter {
            modifiers.contains($0)
        }
        .reduce(into: EventModifiers()) { $0.insert($1) }
        guard pressed == expected else { return false }
        return ExtensionAction.keyEquivalent(declared) == key
    }

    /// Raycast's `KeyEquivalent` names → SwiftUI's.
    private static func keyEquivalent(_ key: String) -> KeyEquivalent {
        switch key {
        case "return", "enter": return .return
        case "delete", "backspace": return .delete
        case "deleteForward": return .deleteForward
        case "tab": return .tab
        case "arrowUp": return .upArrow
        case "arrowDown": return .downArrow
        case "arrowLeft": return .leftArrow
        case "arrowRight": return .rightArrow
        case "escape": return .escape
        case "space": return .space
        case "pageUp": return .pageUp
        case "pageDown": return .pageDown
        case "home": return .home
        case "end": return .end
        default: return KeyEquivalent(Character(key.lowercased().first.map(String.init) ?? " "))
        }
    }

    private static func keyCap(_ key: String) -> String {
        switch key {
        case "return", "enter": return "↵"
        case "delete", "backspace": return "⌫"
        case "deleteForward": return "⌦"
        case "tab": return "⇥"
        case "arrowUp": return "↑"
        case "arrowDown": return "↓"
        case "arrowLeft": return "←"
        case "arrowRight": return "→"
        case "escape": return "⎋"
        case "space": return "␣"
        case "pageUp": return "⇞"
        case "pageDown": return "⇟"
        case "home": return "↖"
        case "end": return "↘"
        default: return key.uppercased()
        }
    }
}
