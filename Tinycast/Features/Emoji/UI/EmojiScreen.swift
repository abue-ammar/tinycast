import SwiftUI

/// The emoji and symbol picker: a sectioned grid whose ↑/↓ move by visual row, not by index.
struct EmojiScreen: PaletteScreen {
    let index: EmojiIndex
    let frequent: FrequentEmojiStore
    let core: AppCore
    let vm: PaletteState
    let tone: EmojiSkinTone
    let openActions: () -> Void

    private var sections: [EmojiGridSection] {
        EmojiGrid.sections(query: vm.query, index: index, frequent: frequent)
    }

    /// Flat grid order across sections — what the selection indexes.
    var rows: [EmojiEntry] { sections.flatMap(\.entries) }

    var primaryActionTitle: String { vm.pasteTarget?.pasteTitle ?? "Paste" }

    private func entry(at selection: Int) -> EmojiEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        return EmojiActionsMenu.content(entry: entry, core: core, target: vm.pasteTarget)
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        core.emojiCoordinator.pasteEmoji(entry)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.emojiCoordinator.copyEmoji(entry)
        return true
    }

    /// ⌥↵, the one chord that leaves the palette up, so emoji can be pasted in a run.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry)
        return true
    }

    /// One visual row vertically, spilling into the neighbour by column; one cell horizontally.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let sections = sections
        let count = sections.reduce(0) { $0 + $1.entries.count }
        guard count > 0 else { return selection }
        switch axis {
        case .vertical:
            let geometry = EmojiGridGeometry(
                counts: sections.map(\.entries.count), columns: EmojiGrid.columns)
            return delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        case .horizontal:
            return min(max(selection + delta, 0), count - 1)
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let sections = sections
        if !index.isLoaded {
            EmptyResults(text: "Loading emoji…")
        } else if sections.isEmpty {
            EmptyResults(text: "No emoji found")
        } else {
            EmojiGridView(
                sections: sections,
                selection: selection,
                tone: tone,
                scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { flat in
                    vm.selection = flat
                    openActions()
                }
            )
        }
    }
}

/// Actions menu for a cell, shown bottom-right on right-click like `ClipboardActionsMenu`.
@MainActor
enum EmojiActionsMenu {
    static func content(
        entry: EmojiEntry, core: AppCore, target: PasteTarget?
    )
        -> PopoverMenuContent
    {
        PopoverMenuContent(
            header: entry.displayName,
            items: [
                PopoverMenuItem(
                    title: target?.pasteTitle ?? "Paste",
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
                ) {
                    core.emojiCoordinator.pasteEmoji(entry)
                },
                PopoverMenuItem(
                    title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵"
                ) {
                    core.emojiCoordinator.copyEmoji(entry)
                },
                PopoverMenuItem(
                    title: "Paste & Keep Window Open", icon: .paste(target, fallback: "macwindow")
                ) {
                    core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry)
                }
            ]
        )
    }
}
