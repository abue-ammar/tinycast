import SwiftUI

/// The emoji and symbol picker: a sectioned grid whose ↑/↓ move by visual row, not by index.
struct EmojiScreen: PaletteScreen {
    let index: EmojiIndex
    let frequent: FrequentEmojiStore
    let pinned: PinnedEmojiStore
    let core: AppCore
    let vm: PaletteState
    let tone: EmojiSkinTone
    let defaultColumns: EmojiGridColumns
    let openActions: () -> Void

    private var columns: EmojiGridColumns {
        vm.emojiGridColumnsOverride ?? defaultColumns
    }

    /// The pins the grid shows; a stored glyph the catalog lacks must not shift any position.
    private var visiblePins: [String] {
        pinned.glyphs.filter { index.entry(for: $0) != nil }
    }

    private var isBrowsing: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pinned is the first section here, so a pin's position is also its flat selection index.
    private var pinsLeadGrid: Bool {
        isBrowsing && (vm.emojiCategoryFilter == .all || vm.emojiCategoryFilter == .pinned)
    }

    private var sections: [EmojiGridSection] {
        EmojiGrid.sections(
            query: vm.query, index: index, frequent: frequent, pinned: pinned,
            filter: vm.emojiCategoryFilter, jevGlyphs: core.jevEmoji.glyphs,
            askingJev: core.jevEmoji.isAsking)
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
        let pins = visiblePins
        return EmojiActionsMenu.content(
            entry: entry, core: core, target: vm.pasteTarget,
            pinPosition: pins.firstIndex(of: entry.glyph), pinCount: pins.count,
            canZoom: { columns.applying($0, default: defaultColumns) != nil },
            togglePin: { togglePin(entry) },
            movePin: { movePin(entry, by: $0) },
            zoom: zoom)
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

    /// ⌥↵ — the palette stays up, so a run of emoji goes over without re-summoning it.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .pin, let entry = entry(at: selection) else { return false }
        togglePin(entry)
        return true
    }

    /// ⌥⌘↑/↓ on the selected cell, when it is pinned.
    func movePin(_ delta: Int, at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        movePin(entry, by: delta)
    }

    func zoom(_ zoom: EmojiGridZoom) {
        guard let next = columns.applying(zoom, default: defaultColumns) else { return }
        vm.emojiGridColumnsOverride = next == defaultColumns ? nil : next
    }

    /// One visual row vertically, spilling into the neighbour by column; one cell horizontally.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let sections = sections
        let count = sections.reduce(0) { $0 + $1.entries.count }
        guard count > 0 else { return selection }
        switch axis {
        case .vertical:
            let geometry = EmojiGridGeometry(
                counts: sections.map(\.entries.count), columns: columns.rawValue)
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
        Group {
            if !index.isLoaded {
                EmptyResults(text: "Loading emoji…")
            } else if sections.isEmpty {
                EmptyResults(text: "No emoji found")
            } else {
                EmojiGridView(
                    sections: sections,
                    selection: selection,
                    tone: tone,
                    columns: columns,
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
        .onChange(of: vm.query, initial: true) { _, _ in
            core.jevEmoji.note(vm.query, index: index)
        }
        .onChange(of: index.isLoaded) { _, _ in
            core.jevEmoji.note(vm.query, index: index)
        }
    }

    private func togglePin(_ entry: EmojiEntry) {
        let position = visiblePins.firstIndex(of: entry.glyph)
        pinned.toggle(entry.glyph)
        if let position, pinsLeadGrid, vm.selection == position {
            // The neighbour sliding into the slot takes the selection, not the catalog copy.
            vm.selection = EmojiGridGeometry.selectionAfterRemovingPin(
                at: position, remainingCount: visiblePins.count)
        } else if isBrowsing, vm.emojiCategoryFilter == .all {
            vm.selection = max(vm.selection + (position == nil ? 1 : -1), 0)
        } else if vm.emojiCategoryFilter == .pinned {
            vm.selection = min(vm.selection, max(rows.count - 1, 0))
        }
    }

    private func movePin(_ entry: EmojiEntry, by delta: Int) {
        let pins = visiblePins
        guard let position = pins.firstIndex(of: entry.glyph),
            pins.indices.contains(position + delta)
        else { return }
        pinned.swap(entry.glyph, with: pins[position + delta])
        if pinsLeadGrid, vm.selection == position { vm.selection = position + delta }
    }
}

/// Actions menu for a cell, shown bottom-right on right-click like `ClipboardActionsMenu`.
@MainActor
enum EmojiActionsMenu {
    static func content(
        entry: EmojiEntry, core: AppCore, target: PasteTarget?, pinPosition: Int?, pinCount: Int,
        canZoom: (EmojiGridZoom) -> Bool, togglePin: @escaping () -> Void,
        movePin: @escaping (Int) -> Void, zoom: @escaping (EmojiGridZoom) -> Void
    )
        -> PopoverMenuContent
    {
        let noun = entry.category.itemTitle
        var items = [
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
                title: "Paste and Keep Window Open",
                icon: .paste(target, fallback: "macwindow"), shortcut: "⌥↵"
            ) {
                core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry)
            },
            PopoverMenuItem(
                title: pinPosition == nil ? "Pin \(noun)" : "Unpin \(noun)",
                systemImage: pinPosition == nil ? "pin" : "pin.slash",
                startsSection: true, shortcut: "⌘.", action: togglePin)
        ]
        if let pinPosition {
            items.append(
                PopoverMenuItem(
                    title: "Move Up in Pinned", systemImage: "arrow.up",
                    isEnabled: pinPosition > 0, shortcut: "⌥⌘↑"
                ) { movePin(-1) })
            items.append(
                PopoverMenuItem(
                    title: "Move Down in Pinned", systemImage: "arrow.down",
                    isEnabled: pinPosition < pinCount - 1, shortcut: "⌥⌘↓"
                ) { movePin(1) })
        }
        items.append(contentsOf: [
            PopoverMenuItem(
                title: "Actual Size", systemImage: "magnifyingglass",
                isEnabled: canZoom(.actualSize), startsSection: true, shortcut: "⌘0"
            ) { zoom(.actualSize) },
            PopoverMenuItem(
                title: "Zoom In", systemImage: "plus.magnifyingglass",
                isEnabled: canZoom(.zoomIn), shortcut: "⌘+"
            ) { zoom(.zoomIn) },
            PopoverMenuItem(
                title: "Zoom Out", systemImage: "minus.magnifyingglass",
                isEnabled: canZoom(.zoomOut), shortcut: "⌘-"
            ) { zoom(.zoomOut) }
        ])
        return PopoverMenuContent(header: entry.displayName, items: items)
    }
}
