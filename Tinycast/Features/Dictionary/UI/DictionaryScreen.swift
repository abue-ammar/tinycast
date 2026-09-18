import SwiftUI

/// The search field is the term; the entry fills the palette instead of competing with a list.
struct DictionaryScreen: PaletteScreen {
    let core: AppCore
    let vm: PaletteState

    private var entry: DictionaryEntry? { DictionaryProvider.entry(for: vm.query) }

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
        if let entry { return AnyView(DictionaryEntryView(entry: entry)) }
        let isEmpty = vm.query.trimmingCharacters(in: .whitespaces).isEmpty
        return AnyView(EmptyResults(text: isEmpty ? "Type a word to define" : "No definition found"))
    }
}

private struct DictionaryEntryView: View {
    @Environment(\.metrics) private var metrics
    let entry: DictionaryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                    Text(entry.term)
                        .font(metrics.typography.calcResult.weight(.semibold))
                    if let pronunciation = entry.pronunciation {
                        Text(pronunciation)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                    Text(sense)
                        .font(metrics.typography.rowTitle)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.spacing.xl)
            .padding(.vertical, metrics.spacing.lg)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        // A new term starts at its headword, not wherever the last one was scrolled to.
        .id(entry.term)
    }
}
