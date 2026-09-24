import SwiftUI

/// One titled run of grid cells; `start` is the flat selection index of its first cell.
struct EmojiGridSection: Identifiable {
    let title: String
    let entries: [EmojiEntry]
    let start: Int
    var showsCount = true

    var id: String { title }
}

enum EmojiGrid {
    /// Ranked results while searching, otherwise pinned, frequent and catalog sections in order.
    @MainActor
    static func sections(
        query: String, index: EmojiIndex, frequent: FrequentEmojiStore,
        pinned: PinnedEmojiStore, filter: EmojiCategoryFilter,
        jevGlyphs: [String] = [], askingJev: Bool = false
    ) -> [EmojiGridSection] {
        var sections: [EmojiGridSection] = []
        var start = 0
        func append(_ title: String, _ entries: [EmojiEntry], showsCount: Bool = true) {
            guard !entries.isEmpty || !showsCount else { return }
            sections.append(
                EmojiGridSection(
                    title: title, entries: entries, start: start, showsCount: showsCount))
            start += entries.count
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            switch filter {
            case .all:
                append("Pinned", pinned.glyphs.compactMap(index.entry(for:)))
                append("Frequently Used", frequent.top().compactMap(index.entry(for:)))
                for section in index.categorySections {
                    append(section.category.title, section.entries)
                }
            case .pinned:
                append("Pinned", pinned.glyphs.compactMap(index.entry(for:)))
            case .frequentlyUsed:
                append("Frequently Used", frequent.top().compactMap(index.entry(for:)))
            case .category(let category):
                if let section = index.categorySections.first(where: { $0.category == category }) {
                    append(section.category.title, section.entries)
                }
            }
        } else {
            let ranked = index.search(query, frequent: frequent)
            func narrow(_ entries: [EmojiEntry]) -> [EmojiEntry] {
                switch filter {
                case .all:
                    return entries
                case .pinned:
                    let glyphs = Set(pinned.glyphs)
                    return entries.filter { glyphs.contains($0.glyph) }
                case .frequentlyUsed:
                    let glyphs = Set(frequent.top())
                    return entries.filter { glyphs.contains($0.glyph) }
                case .category(let category):
                    return entries.filter { $0.category == category }
                }
            }
            let jev = narrow(jevGlyphs.compactMap(index.entry(for:)))
            let jevSet = Set(jev.map(\.glyph))
            if !jev.isEmpty {
                append("Jev", jev)
            } else if askingJev {
                append("Asking Jev…", [], showsCount: false)
            }
            append("Results", narrow(ranked).filter { !jevSet.contains($0.glyph) })
        }
        return sections
    }
}

/// One grid row of cells; `start` is its first cell's flat selection index.
private struct EmojiGridRow: Identifiable {
    let id: String
    let start: Int
    let entries: ArraySlice<EmojiEntry>
    let isLastInSection: Bool

    subscript(column: Int) -> EmojiEntry {
        entries[entries.index(entries.startIndex, offsetBy: column)]
    }
}

/// Flat render order for one query: section headers and grid rows interleaved.
private enum EmojiGridItem: Identifiable {
    case header(id: String, title: String, count: Int, showsCount: Bool)
    case row(EmojiGridRow)

    var id: String {
        switch self {
        case .header(let id, _, _, _): return id
        case .row(let row): return row.id
        }
    }
}

struct EmojiGridView: View {

    @Environment(\.metrics) private var metrics
    let sections: [EmojiGridSection]
    /// Flat selection index across all sections, as in the list modes.
    let selection: Int
    let tone: EmojiSkinTone
    let columns: EmojiGridColumns
    /// The pending scroll request; mouse selection leaves it untouched.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    /// Headers + rows in visible order; rows are the scroll targets. docs/features/emoji.md
    private var items: [EmojiGridItem] {
        var items: [EmojiGridItem] = []
        for section in sections {
            items.append(
                .header(
                    id: section.id + "-header", title: section.title,
                    count: section.entries.count, showsCount: section.showsCount))
            var offset = 0
            var row = 0
            while offset < section.entries.count {
                let end = min(offset + columns.rawValue, section.entries.count)
                items.append(
                    .row(
                        EmojiGridRow(
                            id: section.id + "-row-\(row)",
                            start: section.start + offset,
                            entries: section.entries[offset..<end],
                            isLastInSection: end == section.entries.count)))
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
        return section.id + "-row-\((selection - section.start) / columns.rawValue)"
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
                        case .header(_, let title, let count, let showsCount):
                            EmojiSectionHeader(
                                title: title, count: count, showsCount: showsCount,
                                isFirst: item.id == items.first?.id)
                        case .row(let row):
                            EmojiGridRowView(
                                row: row, selection: selection, tone: tone, columns: columns,
                                onSelect: onSelect, onActivate: onActivate, onActions: onActions
                            )
                            .padding(
                                .bottom,
                                row.isLastInSection ? 0 : metrics.spacing.md
                            )
                            .selectionFrame(item.id == selectedRowID)
                        }
                    }
                }
                .padding(.horizontal, metrics.size.emojiGridInset)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            // Snap to the origin on the first grid row so its header shows too.
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selectedRowID == firstRowID, proxy: proxy
            )
        }
    }
}

/// Count trails the title without changing the shared section header used by the other screens.
private struct EmojiSectionHeader: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let count: Int
    var showsCount = true
    let isFirst: Bool

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(title)
                .foregroundStyle(Theme.Colors.textSecondary)
            if showsCount {
                Text(count, format: .number)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .font(metrics.typography.sectionHeader)
        .padding(.top, isFirst ? metrics.spacing.xs : metrics.spacing.emojiSectionSpacing)
        .padding(.bottom, metrics.spacing.md)
    }
}

/// One grid row, owning all interaction for its cells. See docs/features/emoji.md#rendering.
private struct EmojiGridRowView: View {
    @Environment(\.metrics) private var metrics
    let row: EmojiGridRow
    let selection: Int
    let tone: EmojiSkinTone
    let columns: EmojiGridColumns
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    @Environment(PaletteState.self) private var palette
    @State private var hoveredColumn: Int?

    private var spacing: CGFloat { metrics.spacing.md }

    /// The palette has a fixed metric width, so cells can be square without a measuring render pass.
    private var cellSize: CGFloat {
        let count = CGFloat(columns.rawValue)
        let contentWidth = metrics.size.panelWidth - metrics.size.emojiGridInset * 2
        return (contentWidth - spacing * (count - 1)) / count
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<columns.rawValue, id: \.self) { column in
                if column < row.entries.count {
                    EmojiCell(
                        glyph: row[column].display(tone: tone),
                        selected: row.start + column == selection,
                        hovered: column == hoveredColumn,
                        size: cellSize
                    )
                } else {
                    // Empty trailing slots keep a partial last row aligned with the full rows.
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        .onChange(of: palette.hoverDisarmToken) { hoveredColumn = nil }
    }

    /// Point → column, rejecting the gap between cells and empty slots in a partial row.
    private func column(at point: CGPoint) -> Int? {
        guard point.x >= 0 else { return nil }
        let pitch = cellSize + spacing
        let column = Int(point.x / pitch)
        let positionInCell = point.x - CGFloat(column) * pitch
        guard column < row.entries.count, positionInCell <= cellSize else { return nil }
        return column
    }
}

/// Pure content: no gestures, overlays or hover tracking. See docs/features/emoji.md#rendering.
private struct EmojiCell: View {
    @Environment(\.metrics) private var metrics
    let glyph: String
    let selected: Bool
    let hovered: Bool
    let size: CGFloat

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.emojiCell
    }

    private var glyphSize: CGFloat { min(max(size * 0.48, 30), 52) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.emojiCell, style: .continuous)
        return ZStack {
            shape.fill(fill)
            if selected {
                // A blurred duplicate keeps every colour in the glyph instead of inventing a tint.
                selectedHalo
                    .opacity(0.25)
                    .clipShape(shape)
            }
            Text(glyph)
                .font(.system(size: glyphSize))
            if selected {
                // Let the same colours tint the slim outer ring, then restore a crisp light edge.
                selectedHalo
                    .mask(shape.strokeBorder(lineWidth: 2))
                shape.strokeBorder(Theme.Colors.emojiSelectionBorder, lineWidth: 2)
                shape.inset(by: 2)
                    .strokeBorder(Theme.Colors.emojiInnerBorder, lineWidth: 1)
            } else if hovered {
                ZStack {
                    shape.strokeBorder(
                        Theme.Colors.emojiHoverBorder, lineWidth: 2)
                    shape.inset(by: 2)
                        .strokeBorder(Theme.Colors.emojiInnerBorder, lineWidth: 1)
                }
                .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
    }

    /// Oversized before blur so its multi-colour wash reaches every corner of the selected tile.
    private var selectedHalo: some View {
        Text(glyph)
            .font(.system(size: size))
            .scaleEffect(1.6)
            .blur(radius: max(16, size * 0.28))
            .saturation(2)
            .opacity(0.76)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
