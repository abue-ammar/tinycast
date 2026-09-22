import SwiftUI

struct SettingsSidebarView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(\.appearsActive) private var appearsActive
    @State private var query = ""
    @State private var highlighted: SettingsSearchEntry.ID?
    @State private var searching = false

    private var results: [SettingsSearchEntry] { SettingsSearchCatalog.results(for: query) }

    var body: some View {
        VStack(spacing: 0) {
            if query.isEmpty {
                browse
            } else {
                found
            }
        }
        .searchable(text: $query, isPresented: $searching, placement: .sidebar, prompt: "Search")
        .onExitCommand { query = "" }
        .background(focusShortcut)
    }

    private var browse: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.title)
                        } icon: {
                            SettingsTabIcon(
                                systemImage: tab.systemImage,
                                tint: appearsActive
                                    ? (navigation.tab == tab ? Color.primary : Color.accentColor)
                                    : Color.secondary)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Pin the style before mounting; the implicit sidebar style paints icons a frame late.
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var found: some View {
        if results.isEmpty {
            // Greedy: a finite max height here becomes a constraint that shrinks the whole window.
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Button("Search Settings") { searching = true }
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
            SettingsTabIcon(systemImage: entry.tab.systemImage, tint: .accentColor)
        }
        // Centred, not first-baseline: the tile sits against a two-line title and breadcrumb.
        .labelStyle(CenteredLabelStyle())
    }
}

private struct CenteredLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

/// The glyph on a tinted tile, so every row's icon reads at one weight whatever its symbol's shape.
private struct SettingsTabIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .frame(width: Theme.Size.settingsSidebarGlyph, height: Theme.Size.settingsSidebarGlyph)
            .foregroundStyle(tint)
            .padding(Theme.Spacing.xs)
            .background(
                tint.opacity(0.1),
                in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
    }
}
