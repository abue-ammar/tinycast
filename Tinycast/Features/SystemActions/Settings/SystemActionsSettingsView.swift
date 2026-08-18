import SwiftUI

struct SystemActionsSettingsView: View {
    var body: some View {
        Form {
            LauncherItemsSection(
                kind: .systemAction,
                header: "System Actions",
                searchPrompt: "Search system actions…")
        }
        .formStyle(.grouped)
        .releasesFocusOnOutsideClick()
    }
}
