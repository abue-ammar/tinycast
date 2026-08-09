import SwiftUI

/// The launcher category for macOS System Settings panes — hence the doubled name.
struct SystemSettingsSettingsView: View {
    var body: some View {
        Form {
            LauncherItemsSection(
                kind: .systemSettings,
                header: "System Settings",
                searchPrompt: "Search System Settings…")
        }
        .formStyle(.grouped)
    }
}
