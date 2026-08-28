import SwiftUI

/// Search Snippets: the enabled library filtered by the search field, previewed before it pastes.
struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// A disabled snippet is off everywhere, so the browser lists exactly what the launcher does.
    var rows: [StoredSnippet] {
        let enabled = store.snippets.filter { $0.snippet.isEnabled }
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return enabled }
        return enabled.filter { record in
            record.snippet.name.localizedCaseInsensitiveContains(query)
                || record.snippet.keyword?.localizedCaseInsensitiveContains(query) == true
        }
    }

    let primaryActionTitle = "Paste Snippet"

    private func record(at selection: Int) -> StoredSnippet? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let record = record(at: selection) else { return nil }
        return SnippetActionsMenu.content(record: record, core: core)
    }

    func activate(at selection: Int) {
        guard let record = record(at: selection) else { return }
        core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            let selected = record(at: selection)
            HStack(spacing: 0) {
                SnippetsList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { record in
                        vm.selection = rows.firstIndex(of: record) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { record in
                        if let index = rows.firstIndex(of: record) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: Theme.Size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(record: selected)
            }
        }
    }

    /// An empty library and an over-narrow filter are different problems with different answers.
    private var emptyMessage: String {
        if store.state == .loading { return "Loading snippets…" }
        return store.snippets.contains(where: { $0.snippet.isEnabled })
            ? "No matching snippets" : "No snippets yet"
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(record: StoredSnippet, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: record.snippet.name,
            items: [
                PopoverMenuItem(title: "Paste Snippet", systemImage: "text.quote", shortcut: "↵") {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
                },
                PopoverMenuItem(title: "Edit Snippet", systemImage: "pencil") {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    core.snippetCoordinator.editSnippet(record)
                },
                PopoverMenuItem(title: "Create Snippet", systemImage: "plus") {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    core.snippetCoordinator.editSnippet(nil)
                },
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder") {
                    core.snippetCoordinator.showSnippetInFinder(record)
                }
            ])
    }
}
