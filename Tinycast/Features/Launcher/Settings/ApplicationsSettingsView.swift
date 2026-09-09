import SwiftUI

struct ApplicationsSettingsView: View {
    @Environment(\.locale) private var localizationLocale
    var body: some View {
        Form {
            // Scopes first: they decide what gets indexed, so they read before the results.
            SearchScopesSection()

            LauncherItemsSection(
                kind: .application,
                anchor: .applicationsApplications,
                searchPrompt: String(localized: "Search applications…", bundle: .appLanguage))
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.applications)
        .releasesFocusOnOutsideClick()
    }
}
