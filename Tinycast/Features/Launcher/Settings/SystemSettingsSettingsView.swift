import SwiftUI

/// The launcher category for macOS System Settings panes — hence the doubled name.
struct SystemSettingsSettingsView: View {
    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .systemSettings, anchor: .systemSettingsSystemSettings)

            LauncherItemsSection(
                kind: .systemSettings,
                anchor: .systemSettingsSystemSettings,
                searchPrompt: "Search System Settings…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.systemSettings)
        .releasesFocusOnOutsideClick()
    }
}
