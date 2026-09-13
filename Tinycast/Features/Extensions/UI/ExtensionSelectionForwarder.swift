import Foundation
import SwiftUI

/// Keeps the extension's item-id selection in sync with Tinycast's flat palette index.
struct ExtensionSelectionForwarder: ViewModifier {
    let screen: ExtensionScreen
    let selection: Int
    @Environment(ExtensionManager.self) private var extensions

    private var selectedIndex: Int {
        screen.items.isEmpty ? 0 : min(max(selection, 0), screen.items.count - 1)
    }

    func body(content: Content) -> some View {
        content.onChange(of: screen.selectionChange(at: selectedIndex), initial: true) { _, change in
            guard let change else { return }
            let argument: Any = change.itemID.map { $0 as Any } ?? NSNull()
            extensions.dispatch(handler: change.handler, arguments: [argument])
        }
    }
}
