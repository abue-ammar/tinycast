import AppKit
import SwiftUI

/// A native pop-up button the form can open from the keyboard; SwiftUI's `Picker` opens only to a
/// click, which leaves a keyboard-driven form with no way into the menu.
struct ExtensionPopUpButton: NSViewRepresentable {
    let items: [ExtensionDropdownItem]
    let selected: String
    /// Lent to the view above so a key press can open the menu; the button itself owns the menu.
    let opener: ExtensionMenuOpener
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        opener.button = button
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        opener.button = button
        // Rebuilt only when the titles really changed: rebuilding closes an open menu.
        if context.coordinator.items != items {
            context.coordinator.items = items
            button.removeAllItems()
            button.addItems(withTitles: items.map(\.title))
        }
        if let index = items.firstIndex(where: { $0.value == selected }), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    /// Seeded empty, never with `items`: the update below adds titles only when they differ, so a
    /// coordinator that already knew them would leave the button with no menu at all.
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    @MainActor
    final class Coordinator: NSObject {
        var items: [ExtensionDropdownItem] = []
        var onSelect: (String) -> Void

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        @objc func select(_ sender: NSPopUpButton) {
            guard items.indices.contains(sender.indexOfSelectedItem) else { return }
            onSelect(items[sender.indexOfSelectedItem].value)
        }
    }
}

/// The handle a key press opens the menu through, so nothing opens one mid-view-update.
@MainActor
final class ExtensionMenuOpener {
    weak var button: NSPopUpButton?

    func open() {
        button?.performClick(nil)
    }
}

/// One choice of a `Form.Dropdown`, in the order the extension declared it.
struct ExtensionDropdownItem: Hashable {
    let title: String
    let value: String

    /// Items may be direct children or grouped in sections.
    static func all(in field: RenderNode) -> [ExtensionDropdownItem] {
        var items: [ExtensionDropdownItem] = []
        func walk(_ node: RenderNode) {
            for child in node.children {
                if child.type.hasSuffix(".Item") {
                    let value = child.string("value") ?? ""
                    items.append(
                        ExtensionDropdownItem(title: child.string("title") ?? value, value: value))
                } else if child.type.hasSuffix(".Section") {
                    walk(child)
                }
            }
        }
        walk(field)
        return items
    }
}
