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
                searchPrompt: "Search System Settings…",
                emptyMessage: LocalizedStringResource(
                    "system-settings-empty", defaultValue: "Nothing here yet."))
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.systemSettings)
        .releasesFocusOnOutsideClick()
    }
}
