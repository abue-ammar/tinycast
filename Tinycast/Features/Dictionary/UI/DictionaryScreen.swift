import SwiftUI

/// The search field is the term; the entry fills the palette instead of competing with a list.
struct DictionaryScreen: PaletteScreen {
    let session: DictionarySession
    let core: AppCore
    let vm: PaletteState

    private var term: String { vm.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Only the answer for what is typed now, so ↵ never copies the word before it.
    private var entry: DictionaryEntry? {
        guard let lookup = session.lookup, lookup.term == term else { return nil }
        return lookup.entry
    }

    /// The one entry, so the footer and ⌘K act on it exactly as on a selected row.
    var rows: [DictionaryEntry] { entry.map { [$0] } ?? [] }

    var primaryActionTitle: String { "Copy Definition" }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry else { return nil }
        return PopoverMenuContent(
            header: entry.term,
            items: [
                PopoverMenuItem(title: "Copy Definition", systemImage: "doc.on.doc", shortcut: "↵") {
                    core.dictionaryCoordinator.copy(entry)
                },
                PopoverMenuItem(title: "Open in Dictionary", systemImage: "book", shortcut: "⌘↵") {
                    core.dictionaryCoordinator.openInDictionary(entry)
                }
            ])
    }

    func activate(at selection: Int) {
        guard let entry else { return }
        core.dictionaryCoordinator.copy(entry)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry else { return false }
        core.dictionaryCoordinator.openInDictionary(entry)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        if term.isEmpty { return AnyView(EmptyResults(text: "Type a word to define")) }
        // The previous page stays up while the next term resolves, so typing never flashes empty.
        if let shown = session.lookup?.entry { return AnyView(DictionaryEntryView(entry: shown)) }
        if session.lookup?.term == term { return AnyView(EmptyResults(text: "No definition found")) }
        return AnyView(Color.clear)
    }
}
