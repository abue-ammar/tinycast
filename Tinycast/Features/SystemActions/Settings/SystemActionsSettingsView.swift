import SwiftUI

struct SystemActionsSettingsView: View {
    @Environment(\.locale) private var localizationLocale
    var body: some View {
        Form {
            LauncherItemsSection(
                kind: .systemAction,
                anchor: .systemActionsSystemActions,
                searchPrompt: String(localized: "Search system actions…", bundle: .appLanguage))
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.systemActions)
        .releasesFocusOnOutsideClick()
    }
}
