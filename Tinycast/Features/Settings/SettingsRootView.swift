import SwiftUI

/// A SwiftUI split, not `NSSplitViewController`: only its sidebar gives `.searchable` a soft edge.
struct SettingsRootView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView()
                // Ahead of the width: applied after it, the column shrinks to AppKit's default.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: Theme.Size.settingsSidebar, ideal: Theme.Size.settingsSidebar,
                    max: Theme.Size.settingsSidebar)
        } detail: {
            SettingsDetailView()
                .frame(minWidth: Theme.Size.settingsDetailMinimum)
        }
        .navigationTitle(navigation.tab.title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "chevron.backward") { navigation.goBack() }
                    .disabled(!navigation.canGoBack)
                Button("Forward", systemImage: "chevron.forward") { navigation.goForward() }
                    .disabled(!navigation.canGoForward)
            }
        }
    }
}
