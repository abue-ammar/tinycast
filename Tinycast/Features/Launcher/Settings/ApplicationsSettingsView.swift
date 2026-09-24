import SwiftUI

struct ApplicationsSettingsView: View {
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .application, anchor: .applicationsApplications)

            SearchScopesSection()
                .settingsEnabled(isEnabled)

            LauncherItemsSection(
                kind: .application,
                anchor: .applicationsApplications,
                searchPrompt: "Search applications…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.applications)
        .releasesFocusOnOutsideClick()
    }

    private var isEnabled: Bool { visibility.isKindEnabled(.application) }
}
