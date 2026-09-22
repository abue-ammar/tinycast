import AppKit
import SwiftUI

/// A real split view, as Settings has, so the sidebar collapses and resizes like a native one.
final class AIChatSplitViewController: NSSplitViewController {
    private static let autosaveName = "AIChatSplitView"

    init(sidebar: some View, detail: some View) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: sidebar))
        sidebarItem.minimumThickness = Theme.Size.aiChatSidebarMinimum
        sidebarItem.maximumThickness = Theme.Size.aiChatSidebarMaximum
        sidebarItem.canCollapse = true

        let detailItem = NSSplitViewItem(viewController: NSHostingController(rootView: detail))
        detailItem.minimumThickness = Theme.Size.aiChatDetailMinimum

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        splitView.autosaveName = Self.autosaveName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
