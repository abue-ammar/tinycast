import SwiftUI

/// Stock `.sidebar` styling throughout: headers, capsule and tint are all system-supplied.
struct SettingsSidebarView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @State private var query = ""
    @State private var highlighted: SettingsSearchEntry.ID?
    @FocusState private var searchFocused: Bool

    private var results: [SettingsSearchEntry] { SettingsSearchCatalog.results(for: query) }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSearchField(query: $query, focused: $searchFocused)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            if query.isEmpty {
                browse
            } else {
                found
            }
        }
        // The field sits under the toolbar's material, so it needs its own clearance from the top.
        .padding(.top, Theme.Spacing.md)
        .onExitCommand { query = "" }
        .background(focusShortcut)
    }

    private var browse: some View {
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

    @ViewBuilder private var found: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            // A second `List`, so result IDs and `SettingsTab` never share a selection namespace.
            List(selection: $highlighted) {
                Section("Results") {
                    ForEach(results) { entry in
                        SettingsSearchResultRow(entry: entry).tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)
            // Arrowing through results moves the pane with the selection, as System Settings does.
            .onChange(of: highlighted) { _, id in
                guard let entry = results.first(where: { $0.id == id }) else { return }
                navigation.select(entry.tab, revealing: entry.target)
            }
        }
    }

    /// ⌘F with no menu item to hang it on; zero-sized so it only ever contributes the shortcut.
    private var focusShortcut: some View {
        Button("Search Settings") { searchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// `List` hands back an optional selection; routing it through `select` records history.
    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { navigation.tab },
            set: { if let tab = $0 { navigation.select(tab) } }
        )
    }
}

private struct SettingsSearchResultRow: View {
    let entry: SettingsSearchEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.title).lineLimit(1)
                Text(entry.breadcrumb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: entry.tab.systemImage)
        }
    }
}
