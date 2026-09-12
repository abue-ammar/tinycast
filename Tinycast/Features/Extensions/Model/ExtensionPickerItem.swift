import Foundation

/// One choice offered by a picker's list, from a `Form.Dropdown`/`Form.TagPicker` or from the
/// search-bar dropdown an extension handed the screen in `searchBarAccessory`.
struct ExtensionPickerItem: Identifiable, Equatable {
    let value: String
    let title: String
    var detail: String?
    var iconValue: RenderValue?
    /// The section this choice was declared under, drawn above the first of them.
    var section: String?

    var id: String { value }

    /// A picker's choices: direct children, or grouped in sections that carry the heading.
    static func items(in node: RenderNode) -> [ExtensionPickerItem] {
        var items: [ExtensionPickerItem] = []
        func walk(_ node: RenderNode, section: String?) {
            for child in node.children {
                if child.type.hasSuffix(".Item") {
                    let value = child.string("value") ?? ""
                    items.append(
                        ExtensionPickerItem(
                            value: value, title: child.string("title") ?? value,
                            iconValue: child.props["icon"], section: section))
                } else if child.type.hasSuffix(".Section") {
                    walk(child, section: child.string("title"))
                }
            }
        }
        walk(node, section: nil)
        return items
    }
}
