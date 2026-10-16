import SwiftUI

struct SystemSettingsSettingsView: View {
    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .systemSettings, anchor: .systemSettingsSystemSettings,
                title: "Enable System Settings")

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
