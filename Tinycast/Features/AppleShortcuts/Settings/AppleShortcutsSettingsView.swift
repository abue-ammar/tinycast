import SwiftUI

/// The shortcuts found in the Shortcuts app, each with the launcher controls any item carries.
struct AppleShortcutsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(AppIndex.self) private var appIndex
    @State private var query = ""

    private var entries: [AppEntry] {
        let entries = core.appleShortcutCoordinator.entries
        guard !query.isEmpty else { return entries }
        // Membership only: score order would move the row being edited out from under the caret.
        let matched = Set(appIndex.matches(query).map(\.id))
        return entries.filter { matched.contains($0.id) }
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.appleShortcutsEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .appleShortcutsAppleShortcuts,
                        title: "Enable Apple Shortcuts",
                        subtitle: "Run your shortcuts from the launcher.")
                }
            }
            .settingsAnchor(.appleShortcutsAppleShortcuts)

            if settings.appleShortcutsEnabled {
                library
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.appleShortcuts)
        .releasesFocusOnOutsideClick()
        // Shortcuts can change while Settings sits closed, so the pane reads them fresh.
        .task(id: settings.appleShortcutsEnabled) { core.appleShortcutCoordinator.refresh() }
    }

    private var library: some View {
        Section {
            SettingsFilterField(prompt: "Search shortcuts…", query: $query)
            LauncherItemsList(entries: entries, query: query, isEnabled: true)
            Button("Open Shortcuts") { core.appleShortcutCoordinator.openShortcutsApp() }
        } header: {
            SettingsSectionHeader(.appleShortcutsShortcuts)
        }
    }
}
