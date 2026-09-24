import SwiftUI

struct SystemActionsSettingsView: View {
    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .systemAction, anchor: .systemActionsSystemActions)

            LauncherItemsSection(
                kind: .systemAction,
                anchor: .systemActionsSystemActions,
                searchPrompt: "Search system actions…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.systemActions)
        .releasesFocusOnOutsideClick()
    }

}
