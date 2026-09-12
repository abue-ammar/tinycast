import SwiftUI

struct ApplicationsSettingsView: View {
    var body: some View {
        Form {
            // Scopes first: they decide what gets indexed, so they read before the results.
            SearchScopesSection()

            LauncherItemsSection(
                kind: .application,
                anchor: .applicationsApplications,
                searchPrompt: "Search applications…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.applications)
        .releasesFocusOnOutsideClick()
    }
}
