import SwiftUI

/// File-scoped so a row and the cap that counts rows read one number.
private struct Metrics {
    /// Owned here rather than in `DesignSystem`: an extension never moves a launcher surface.
    let interface: InterfaceMetrics

    var width: CGFloat { interface.scaled(320) }
    /// The glyph slot plus its breathing room — the tallest thing a row contains.
    var rowHeight: CGFloat { interface.size.menuIcon + interface.spacing.md * 2 }
    var rowSpacing: CGFloat { 1 }
    var listInset: CGFloat { interface.spacing.md }
    /// Five rows and half of the sixth, so a long panel reads as scrollable rather than clipped.
    var visibleRows: CGFloat { 5.5 }
    /// Rounded: a fractional height lands the glass edge on a half pixel.
    var rowsMaxHeight: CGFloat { (visibleRows * (rowHeight + rowSpacing)).rounded() }
    var headerHeight: CGFloat {
        interface.size.menuSectionHeader + interface.spacing.xs * 1.5 + rowSpacing
    }
    /// Exact, not measured; a capped viewport ends mid-row, never on a separator.
    func extent(
        items: [ExtensionActionItem], hasHeader: Bool, hairline: CGFloat
    ) -> (content: CGFloat, viewport: CGFloat) {
        let header = hasHeader ? headerHeight : 0
        let capacity = rowsMaxHeight + header
        var offset = header
        var fold: CGFloat = 0
        for (index, item) in items.enumerated() {
            if index > 0 { offset += item.startsSection ? listInset * 2 + hairline : rowSpacing }
            let midRow = (offset + rowHeight / 2).rounded(.down)
            if midRow <= capacity { fold = midRow }
            offset += rowHeight
        }
        return (offset, offset > capacity ? fold : offset)
    }
}

/// Its own type, not `PopoverMenuItem`: an extension names any icon and tints it.
struct ExtensionActionItem {
    let title: String
    let icon: ExtensionImage.Resolved
    var shortcut: String?
    var isDestructive = false
    var startsSection = false
}

/// The ⌘K panel of a running command; extension artwork and tints stay feature-owned.
struct ExtensionActionsPanel: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    var header: String?
    let items: [ExtensionActionItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void

    /// The palette arms this only once the pointer has moved of its own accord.
    @Environment(PaletteState.self) private var palette
    /// A hovered row is already visible, so scrolling would drag the list under it.
    @State private var hoverSelection: Int?

    private var panel: Metrics { Metrics(interface: metrics) }
    /// One device pixel: a point-wide rule reads heavy against the glass.
    private var hairline: CGFloat { 1 / displayScale }

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: metrics.radius.menuPanel,
            bottomLeadingRadius: metrics.radius.menuPanel,
            bottomTrailingRadius: metrics.size.menuButton / 2,
            topTrailingRadius: metrics.radius.menuPanel,
            style: .continuous)
        return VStack(spacing: 0) {
            listContent
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: hairline)
                .accessibilityHidden(true)
            ExtensionMenuSearchField(
                placeholder: "Search for actions…", height: panel.rowHeight,
                verticalOffset: -metrics.spacing.xxs / 2)
        }
        .frame(width: panel.width)
        .glassEffect(.regular, in: shape)
    }

    @ViewBuilder
    private var listContent: some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                headerLabel
                Text("No Results")
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: panel.rowHeight)
            }
            .padding(panel.listInset)
        } else {
            actionRows
        }
    }

    private var actionRows: some View {
        let extent = panel.extent(items: items, hasHeader: header != nil, hairline: hairline)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Index-as-id is stable: a panel's rows never reorder while it is open.
                    ForEach(items.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            // Inside the first row's target, so revealing that row brings the title.
                            if index == 0 { headerLabel }
                            rowBoundary(before: index)
                            ExtensionActionRow(
                                item: items[index],
                                selected: index == selection,
                                onActivate: { onActivate(index) }
                            )
                            .onContinuousHover { if case .active = $0 { hover(index) } }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, panel.listInset)
            }
            // A margin, not padding: a revealed end row keeps its inset instead of meeting the edge.
            .contentMargins(.vertical, panel.listInset, for: .scrollContent)
            .frame(height: extent.viewport + panel.listInset * 2)
            .scrollBounceBehavior(extent.content > extent.viewport ? .always : .basedOnSize)
            // `never`, not `hidden`: hidden still lets AppKit claim the scroller's gutter.
            .scrollIndicators(.never)
            .onChange(of: selection) {
                let movedByPointer = hoverSelection == selection
                hoverSelection = nil
                guard !movedByPointer else { return }
                // No anchor: reveal the row, never re-centre the list around it.
                proxy.scrollTo(selection)
            }
        }
    }

    @ViewBuilder
    private var headerLabel: some View {
        if let header {
            Text(header)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: metrics.size.menuSectionHeader, alignment: .leading)
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.xs / 2)
            Color.clear.frame(height: panel.rowSpacing)
        }
    }

    @ViewBuilder
    private func rowBoundary(before index: Int) -> some View {
        if index > 0, items[index].startsSection {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: hairline)
                .padding(.horizontal, metrics.spacing.md)
                // The list inset, so a row sits as far from this hairline as from the search one.
                .padding(.vertical, panel.listInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if index > 0 {
            Color.clear.frame(height: panel.rowSpacing)
        }
    }

    /// Armed only once the pointer has moved of its own accord, so a scroll past it lights nothing.
    private func hover(_ index: Int) {
        guard palette.hoverHighlightArmed, index != selection else { return }
        hoverSelection = index
        selection = index
    }
}

/// Its own row, not the palette's: that one is file-private.
private struct ExtensionActionRow: View {
    @Environment(\.metrics) private var metrics
    let item: ExtensionActionItem
    let selected: Bool
    let onActivate: () -> Void

    private var panel: Metrics { Metrics(interface: metrics) }

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: metrics.spacing.md) {
                ExtensionIconView(
                    resolved: item.icon, size: metrics.size.menuIcon, usesMenuSymbolStyle: true)
                Text(item.title)
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if let shortcut = item.shortcut {
                    HStack(spacing: metrics.spacing.xxs) {
                        ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                            KeyCapChip(text: String(glyph), style: .outline)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            // Fixed, not padded: the height maths above counts rows, so a row is one exact height.
            .frame(
                maxWidth: .infinity, minHeight: panel.rowHeight, maxHeight: panel.rowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
