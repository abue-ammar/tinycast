import SwiftUI

struct ApplicationsSettingsView: View {
    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .application, anchor: .applicationsApplications,
                title: "Enable Applications")

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
