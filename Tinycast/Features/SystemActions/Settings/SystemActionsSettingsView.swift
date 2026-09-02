import SwiftUI

struct SystemActionsSettingsView: View {
    var body: some View {
        Form {
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
