import Foundation

/// The `List.Dropdown`/`Grid.Dropdown` an extension put in the search bar. The runtime keeps the
/// component hook-free, so Swift holds the selection and reports every change through `onChange`.
struct ExtensionSearchAccessory: Equatable {
    /// The render node's id, which is what the session keys the held selection by.
    let nodeID: Int
    let items: [ExtensionPickerItem]
    let onChange: String?
    /// A `value` prop: while the extension supplies one it owns the selection, not the user.
    let controlledValue: String?
    let defaultValue: String?
    /// Where `storeValue` parks the pick, or nil when the dropdown never asked to persist one.
    let storageKey: String?
    let placeholder: String?
    let tooltip: String?

    init?(node: RenderNode?) {
        guard let node, node.type == "List.Dropdown" || node.type == "Grid.Dropdown" else {
            return nil
        }
        nodeID = node.id
        items = ExtensionPickerItem.items(in: node)
        onChange = node.handler("onChange")
        controlledValue = node.string("value")
        defaultValue = node.string("defaultValue")
        // Raycast keys the stored pick by the dropdown's own id; one per command needs no id.
        storageKey =
            node.bool("storeValue") == true ? (node.string("id") ?? "searchBarAccessory") : nil
        placeholder = node.string("placeholder")
        tooltip = node.string("tooltip")
    }

    /// Raycast's order: the stored pick while it still names a choice, else `defaultValue`, else
    /// the first choice — a dropdown always shows one.
    func initialValue(stored: String?) -> String? {
        if let stored, items.contains(where: { $0.value == stored }) { return stored }
        return defaultValue ?? items.first?.value
    }

    /// What the closed control reads as; a value no item claims is still the value.
    func title(for value: String?) -> String? {
        guard let value else { return placeholder ?? tooltip }
        return item(for: value)?.title ?? value
    }

    func item(for value: String?) -> ExtensionPickerItem? {
        guard let value else { return nil }
        return items.first { $0.value == value }
    }

    /// The row the list opens on, so the choice it holds is the one already highlighted.
    func index(of value: String?) -> Int {
        items.firstIndex { $0.value == value } ?? 0
    }
}
