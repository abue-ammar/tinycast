import AppKit
import SwiftUI

/// A real `NSSplitViewController` so the toolbar can use `.sidebarTrackingSeparator`.
@MainActor
final class SettingsSplitViewController: NSSplitViewController {
    init(sidebar: some View, detail: some View) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: AnyView(sidebar.localizationEnvironment())))
        // Fixed, as the column was before: nothing here reflows with width.
        sidebarItem.minimumThickness = Theme.Size.settingsSidebar
        sidebarItem.maximumThickness = Theme.Size.settingsSidebar
        sidebarItem.canCollapse = false

        let detailItem = NSSplitViewItem(viewController: NSHostingController(rootView: AnyView(detail.localizationEnvironment())))
        detailItem.minimumThickness = Theme.Size.settingsDetailMinimum

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
