import SwiftUI

/// Moving somewhere — a window, a menu item — rather than changing something. Two features,
/// one switch, so the pane lives here rather than inside either of them.
struct NavigationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.navigationEnabled) {
                    SettingsRowTitle(.navigationNavigation, "Enable navigation")
                    Text("Jump to any open window, or press any menu bar item, from the launcher.")
                }
            } header: {
                SettingsSectionHeader(.navigationNavigation)
            }

            // No "show in launcher" switch: the per-command checkboxes below already are one.
            FeatureCommandsSection(owner: .navigation, anchor: .navigationCommands)
                .settingsEnabled(settings.navigationEnabled)

            DisabledApplicationsSection(
                bundleIDs: $settings.menuSearchDisabledApps,
                anchor: .navigationDisabledApplications,
                footer: "Search Menu Bar Items won't read the menu bar of these apps."
            )
            .settingsEnabled(settings.navigationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.navigation)
    }
}
