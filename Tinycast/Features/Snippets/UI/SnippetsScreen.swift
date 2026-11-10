import SwiftUI

struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void

    /// A disabled snippet is off everywhere, so the browser lists what the launcher does, pins first.
    var rows: [StoredSnippet] {
        let enabled = store.snippets.filter { $0.snippet.isEnabled }
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        let matches =
            query.isEmpty
            ? enabled
            : enabled.filter { record in
                record.snippet.name.localizedCaseInsensitiveContains(query)
                    || record.snippet.keyword?.localizedCaseInsensitiveContains(query) == true
            }
        return matches.filter(\.snippet.isPinned) + matches.filter { !$0.snippet.isPinned }
    }

    let primaryActionTitle = String(localized: "Paste Snippet")

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

    /// ⌘↵ copies the expansion instead of pasting it.
    func secondary(at selection: Int) -> Bool {
        guard let record = record(at: selection) else { return false }
        core.snippetCoordinator.copySnippetFromPalette(id: record.id)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .newItem {
            core.snippetCoordinator.editSnippet(nil)
            return true
        }
        guard let record = record(at: selection) else { return false }
        switch shortcut {
        case .edit:
            core.snippetCoordinator.editSnippet(record)
        case .pin:
            togglePinned(record)
        case .showInFinder:
            core.snippetCoordinator.showSnippetInFinder(record)
        case .delete:
            Task { await core.snippetCoordinator.deleteSnippet(id: record.id) }
        default: return false
        }
        return true
    }

    /// The row jumps between the pinned block and the rest, so the selection goes with it.
    private func togglePinned(_ record: StoredSnippet) {
        Task {
            await core.snippetCoordinator.toggleSnippetPinned(id: record.id)
            if let index = rows.firstIndex(where: { $0.id == record.id }) { vm.selection = index }
        }
    }

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
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(record: selected)
            }
        }
    }

    /// An empty library and an over-narrow filter are different problems with different answers.
    private var emptyMessage: String {
        if store.state == .loading { return String(localized: "Loading snippets…") }
        return store.snippets.contains(where: { $0.snippet.isEnabled })
            ? String(localized: "No matching snippets") : String(localized: "No snippets yet")
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(record: StoredSnippet, core: AppCore) -> PopoverMenuContent {
        let isPinned = record.snippet.isPinned
        return PopoverMenuContent(
            header: record.snippet.name,
            items: [
                PopoverMenuItem(
                    title: isPinned ? String(localized: "Unpin Snippet") : String(localized: "Pin Snippet"),
                    systemImage: isPinned ? "pin.slash" : "pin", shortcut: "⌘."
                ) {
                    Task { await core.snippetCoordinator.toggleSnippetPinned(id: record.id) }
                },
                PopoverMenuItem(
                    title: String(localized: "Paste Snippet"), systemImage: "text.quote", startsSection: true,
                    shortcut: "↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy to Clipboard"), systemImage: "doc.on.doc", shortcut: "⌘↵"
                ) {
                    core.snippetCoordinator.copySnippetFromPalette(id: record.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Edit Snippet"), systemImage: "pencil", startsSection: true,
                    shortcut: "⌘E"
                ) {
                    core.snippetCoordinator.editSnippet(record)
                },
                PopoverMenuItem(
                    title: String(localized: "Create Snippet"), systemImage: "plus", shortcut: "⌘N"
                ) {
                    core.snippetCoordinator.editSnippet(nil)
                },
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "folder", startsSection: true,
                    shortcut: "⌘F"
                ) {
                    core.snippetCoordinator.showSnippetInFinder(record)
                },
                PopoverMenuItem(
                    title: String(localized: "Delete Snippet"), systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) {
                    Task { await core.snippetCoordinator.deleteSnippet(id: record.id) }
                }
            ])
    }
}
