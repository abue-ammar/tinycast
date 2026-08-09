import SwiftUI

/// Stock `.sidebar` styling throughout: headers, capsule and tint are all system-supplied.
struct SettingsSidebarView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// `List` hands back an optional selection; routing it through `select` records history.
    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { navigation.tab },
            set: { if let tab = $0 { navigation.select(tab) } }
        )
    }
}
