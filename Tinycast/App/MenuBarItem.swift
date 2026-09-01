import SwiftUI

/// Tinycast's own menu-bar item. It carries no feature state, so no feature can hide or reshape it.
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image(systemName: "macwindow.on.rectangle")
            .accessibilityLabel(appName)
    }
}

struct MenuBarMenu: View {
    let appName: String

    var body: some View {
        Button("Open \(appName)") {
            AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
        }
        Button("Clipboard History") {
            AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
        }
        Divider()
        Button("Check for Updates...") { AppCore.shared.updateCoordinator.checkForUpdates() }
        Button("Support \(appName)...") { AppCore.shared.supportCoordinator.showSupport() }
        Button("Settings...") { AppCore.shared.settingsCoordinator.showSettings() }
            .keyboardShortcut(",")
        Divider()
        // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
        Button("Quit \(appName)") { NSApp.terminate(nil) }
    }
}
