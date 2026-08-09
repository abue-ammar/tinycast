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

    /// Ranked results while searching, otherwise Frequently Used plus every category.
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
            append("Frequently Used", frequent.top().compactMap(index.entry(for:)))
            for section in index.categorySections {
                append(section.category.title, section.entries)
            }
        } else {
            append("Results", index.search(query))
        }
        return sections
    }
}

/// One grid row of up to `EmojiGrid.columns` cells; `start` is its first cell's flat index.
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

struct EmojiGridView: View {
    let sections: [EmojiGridSection]
    /// Flat selection index across all sections, as in the list modes.
    let selection: Int
    let tone: EmojiSkinTone
    /// The pending scroll request; mouse selection leaves it untouched.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    /// Headers + rows in visible order; rows are the scroll targets. docs/features/emoji.md
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

    /// The row holding the selection; IDs are section-namespaced, as frequents repeat.
    private var selectedRowID: String? {
        guard let section = sections.last(where: { selection >= $0.start }),
            selection - section.start < section.entries.count
        else { return nil }
        return section.id + "-row-\((selection - section.start) / EmojiGrid.columns)"
    }

    /// First grid row; selecting into it restores the origin instead, so its header shows.
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
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .applyTopScrollIntent(scroll, proxy: proxy)
            .onChange(of: scroll) { _, scroll in
                guard scroll.kind == .follow, let selectedRowID else { return }
                // Snap to the origin on the first row so its header shows too.
                if selectedRowID == firstRowID {
                    proxy.scrollToOrigin()
                } else {
                    proxy.reveal(selectedRowID)
                }
            }
        }
    }
}

/// One grid row, owning all interaction for its cells. See docs/features/emoji.md#rendering.
private struct EmojiGridRowView: View {
    let row: EmojiGridRow
    let selection: Int
    let tone: EmojiSkinTone
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    @Environment(PaletteState.self) private var palette
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
                    // Empty trailing slots keep a partial last row aligned with the full rows.
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
        // Single tap selects; the double-tap paste rides along as a simultaneous gesture.
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
        // Column hover, gated on real pointer movement like `armedHover`.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoveredColumn = palette.hoverHighlightArmed ? column(at: point) : nil
            case .ended:
                hoveredColumn = nil
            }
        }
    }

    /// Point → column; exact, as cells split the width evenly. Trailing slots resolve to nil.
    private func column(at point: CGPoint) -> Int? {
        guard width > 0, point.x >= 0, point.x < width else { return nil }
        let column = min(
            Int(point.x / (width / CGFloat(EmojiGrid.columns))), EmojiGrid.columns - 1)
        return column < row.entries.count ? column : nil
    }
}

/// Pure content: no gestures, overlays or hover tracking. See docs/features/emoji.md#rendering.
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
