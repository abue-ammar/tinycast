import Foundation
import SwiftUI

/// Keeps the extension's item-id selection in sync with Tinycast's flat palette index.
struct ExtensionSelectionForwarder: ViewModifier {
    let screen: ExtensionScreen
    let selection: Int
    @Environment(PaletteState.self) private var palette
    @Environment(ExtensionManager.self) private var extensions
    @State private var seededContext: String?

    private var selectedIndex: Int {
        screen.items.isEmpty ? 0 : min(max(selection, 0), screen.items.count - 1)
    }

    private var context: String? {
        guard let running = extensions.running, let root = screen.root else { return nil }
        return "\(running.entryID):\(root.id)"
    }

    func body(content: Content) -> some View {
        content.onChange(of: screen.selectionChange(at: selectedIndex), initial: true) { _, change in
            guard let change else { return }
            if seededContext != context {
                seededContext = context
                if let index = screen.selectedItemIndex, selectedIndex != index {
                    palette.selection = index
                    return
                }
            }
            let argument: Any = change.itemID.map { $0 as Any } ?? NSNull()
            extensions.dispatch(handler: change.handler, arguments: [argument])
        }
    }
}
