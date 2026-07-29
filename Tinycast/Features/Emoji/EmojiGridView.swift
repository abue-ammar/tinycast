import SwiftUI

/// One titled run of grid cells; `start` is the flat selection index of its first cell.
struct EmojiGridSection: Identifiable {
    let title: String
    let entries: [EmojiEntry]
    let start: Int

    var id: String { title }
}

enum EmojiGrid {
    static let columns = 8

    /// The visible sections for a query: ranked results while searching, otherwise Frequently Used + every category.
    @MainActor
    static func sections(
        query: String, index: EmojiIndex, frequent: FrequentEmojiStore
    ) -> [EmojiGridSection] {
        var sections: [EmojiGridSection] = []
        var start = 0
        func append(_ title: String, _ entries: [EmojiEntry]) {
            guard !entries.isEmpty else { return }
            sections.append(EmojiGridSection(title: title, entries: entries, start: start))
            start += entries.count
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            append("Frequently Used", frequent.top().compactMap { index.entry(for: $0) })
            for section in index.categorySections {
                append(section.category.title, section.entries)
            }
        } else {
            append("Results", index.search(query))
        }
        return sections
    }
}

/// One visual grid row of up to `EmojiGrid.columns` cells; `start` is the flat selection index of its first cell.
private struct EmojiGridRow: Identifiable {
    let id: String
    let start: Int
    let entries: [EmojiEntry]
}

/// Flat render order for one query: section headers and grid rows interleaved.
private enum EmojiGridItem: Identifiable {
    case header(id: String, title: String)
    case row(EmojiGridRow)

    var id: String {
        switch self {
        case .header(let id, _): return id
        case .row(let row): return row.id
        }
    }
}

/// A grid scroll request: reset and follow need different, estimation-safe scroll ops on the lazy grid, so the caller states which it wants instead of the grid guessing from one shared token.
struct EmojiScrollIntent: Equatable {
    enum Kind {
        /// Reset: clamp to the true top. `.top` on the first item is estimation-proof — nothing sits above it, so its offset can only be 0.
        case top
        /// Keyboard nav: minimal scroll-to-visible (nil anchor), which never repositions an already-visible row.
        case follow
    }

    var kind: Kind
    /// Distinguishes back-to-back intents of the same kind so `onChange` still fires.
    var nonce = UUID()
}

struct EmojiGridView: View {
    let sections: [EmojiGridSection]
    /// Flat selection index across all sections in order — the same single-source-of-truth contract as the list modes.
    let selection: Int
    let tone: EmojiSkinTone
    /// The pending scroll request; mouse selection leaves it untouched so clicking a row never yanks the scroll position.
    let scroll: EmojiScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    /// Header + row items in visible order; rows sit directly under the outer `LazyVStack` so `ScrollViewReader` can reach any of them even while off-screen — a cell nested in a `LazyVGrid` can't be scrolled to until realized, which broke keyboard scroll on key-hold.
    private var items: [EmojiGridItem] {
        var items: [EmojiGridItem] = []
        for section in sections {
            items.append(.header(id: section.id + "-header", title: section.title))
            var offset = 0
            var row = 0
            while offset < section.entries.count {
                let end = min(offset + EmojiGrid.columns, section.entries.count)
                items.append(
                    .row(
                        EmojiGridRow(
                            id: section.id + "-row-\(row)",
                            start: section.start + offset,
                            entries: Array(section.entries[offset..<end]))))
                offset = end
                row += 1
            }
        }
        return items
    }

    /// Scroll target for the current selection — the row that holds it (IDs are section-namespaced because a frequent emoji repeats inside its category).
    private var selectedRowID: String? {
        guard let section = sections.last(where: { selection >= $0.start }),
            selection - section.start < section.entries.count
        else { return nil }
        return section.id + "-row-\((selection - section.start) / EmojiGrid.columns)"
    }

    /// First header and first row, ID'd the same way as `items`; the header is the scroll-to-top target.
    private var firstItemID: String? { sections.first.map { $0.id + "-header" } }
    private var firstRowID: String? { sections.first.map { $0.id + "-row-0" } }

    var body: some View {
        let items = items
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(_, let title):
                            SectionHeader(title: title, isFirst: item.id == items.first?.id)
                        case .row(let row):
                            EmojiGridRowView(
                                row: row, selection: selection, tone: tone,
                                onSelect: onSelect, onActivate: onActivate, onActions: onActions
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    if let firstItemID { proxy.scrollTo(firstItemID, anchor: .top) }
                case .follow:
                    guard let selectedRowID else { return }
                    // On the first row, snap to the top so its header shows too — a nil anchor won't, since the row is already visible.
                    if selectedRowID == firstRowID, let firstItemID {
                        proxy.scrollTo(firstItemID, anchor: .top)
                    } else {
                        proxy.scrollTo(selectedRowID, anchor: nil)
                    }
                }
            }
        }
    }
}

/// One grid row. All interaction (tap, double-tap, right-click, hover) lives here — once per row, not per cell — because a fast scroll realizes every cell and per-cell interaction machinery (notably the NSView-backed right-click catcher) at ~2k cells costs ~100 MB that lazy containers never release; per-row keeps that bounded to the handful of visible rows.
private struct EmojiGridRowView: View {
    let row: EmojiGridRow
    let selection: Int
    let tone: EmojiSkinTone
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    @State private var hoveredColumn: Int?
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<EmojiGrid.columns, id: \.self) { column in
                if column < row.entries.count {
                    EmojiCell(
                        glyph: row.entries[column].display(tone: tone),
                        selected: row.start + column == selection,
                        hovered: column == hoveredColumn
                    )
                } else {
                    // Empty trailing slots of a partial last row keep the columns aligned with full rows above.
                    Color.clear.frame(maxWidth: .infinity, minHeight: Theme.Size.emojiCell)
                }
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        // Single tap selects immediately; the double-tap paste rides along as a simultaneous gesture (the list rows' pattern).
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let column = column(at: value.location) { onSelect(row.start + column) }
            }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                guard let column = column(at: value.location) else { return }
                onSelect(row.start + column)
                onActivate()
            }
        )
        .onRightClick { point in
            if let column = column(at: point) { onActions(row.start + column) }
        }
        // Column hover, gated on real pointer movement like `armedHover`: cleared unless `hoverHighlightArmed`.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoveredColumn = AppCore.shared.palette.hoverHighlightArmed ? column(at: point) : nil
            case .ended:
                hoveredColumn = nil
            }
        }
    }

    /// Point → column, exact because cells split the width evenly with zero spacing; the empty trailing slots of a partial last row resolve to nil.
    private func column(at point: CGPoint) -> Int? {
        guard width > 0, point.x >= 0, point.x < width else { return nil }
        let column = min(
            Int(point.x / (width / CGFloat(EmojiGrid.columns))), EmojiGrid.columns - 1)
        return column < row.entries.count ? column : nil
    }
}

/// Pure content — no gestures, overlays or hover tracking; interaction is handled by `EmojiSectionGrid` so realized cells stay cheap.
private struct EmojiCell: View {
    let glyph: String
    let selected: Bool
    let hovered: Bool

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Text(glyph)
            .font(.system(size: 30))
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.emojiCell)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(fill)
            )
    }
}

/// Actions menu content for an emoji/symbol cell, shown bottom-right on right-click, mirroring `ClipboardActionsMenu`.
@MainActor
enum EmojiActionsMenu {
    static func content(entry: EmojiEntry, core: AppCore, target: PasteTarget?)
        -> PopoverMenuContent
    {
        PopoverMenuContent(
            header: entry.displayName,
            items: [
                PopoverMenuItem(
                    title: target?.pasteTitle ?? "Paste",
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
                ) {
                    core.pasteEmoji(entry)
                },
                PopoverMenuItem(
                    title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵"
                ) {
                    core.copyEmoji(entry)
                },
                PopoverMenuItem(
                    title: "Paste & Keep Window Open", icon: .paste(target, fallback: "macwindow")
                ) {
                    core.pasteEmojiKeepingWindowOpen(entry)
                },
            ]
        )
    }
}
