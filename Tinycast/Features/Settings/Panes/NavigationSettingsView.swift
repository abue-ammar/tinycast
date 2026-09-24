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
                    SettingsFeatureToggleLabel(
                        anchor: .navigationNavigation, title: "Enable navigation",
                        subtitle: "Switch windows and search menu bar items.")
                }
            }
            .settingsAnchor(.navigationNavigation)

            // No "show in launcher" switch: the per-command checkboxes below already are one.
            FeatureCommandsSection(
                owner: .navigation, anchor: .navigationCommands,
                excluding: [.searchMenuItems]
            )
            .settingsEnabled(settings.navigationEnabled)

            // The menu-search command sits with the two settings that only it reads.
            Section {
                if let entry = CommandCatalog.entry(for: .searchMenuItems) {
                    FeatureCommandRow(entry: entry)
                }

                Toggle(isOn: $settings.menuSearchShowsAppleMenu) {
                    SettingsRowTitle(.navigationMenuSearch, "Show Apple menu items")
                }

                SettingsRow(
                    title: "Disabled Applications",
                    subtitle: "Their menus are never searched.",
                    anchor: .navigationMenuSearch
                ) {
                    EmptyView()
                }

                DisabledApplicationsList(bundleIDs: $settings.menuSearchDisabledApps)
            } header: {
                SettingsSectionHeader(.navigationMenuSearch)
            }
            .settingsEnabled(settings.navigationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.navigation)
    }
}
