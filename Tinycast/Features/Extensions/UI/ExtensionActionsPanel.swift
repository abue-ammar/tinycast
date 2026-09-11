import SwiftUI

/// File-scoped so a row and the cap that counts rows read one number.
private struct Metrics {
    /// Owned here rather than in `DesignSystem`: an extension never moves a launcher surface.
    let interface: InterfaceMetrics

    var width: CGFloat { interface.scaled(300) }
    /// The glyph slot plus its breathing room — the tallest thing a row contains.
    var rowHeight: CGFloat { interface.size.menuIcon + interface.spacing.md * 2 }
    var rowSpacing: CGFloat { 1 }
    /// Six rows and half of the seventh, so a long panel reads as scrollable rather than clipped.
    var visibleRows: CGFloat { 6.5 }
    /// Rounded: a fractional height lands the glass edge on a half pixel.
    var maxHeight: CGFloat { (visibleRows * (rowHeight + rowSpacing)).rounded() }

    /// Exact, because every row is one known height: no measuring pass, and no greedy scroll view.
    func height(rows: Int) -> CGFloat {
        min(CGFloat(rows) * (rowHeight + rowSpacing) - rowSpacing, maxHeight)
    }
}

/// Its own type, not `PopoverMenuItem`: an extension names any icon and tints it.
struct ExtensionActionItem {
    let title: String
    let icon: ExtensionImage.Resolved
    var shortcut: String?
    var isDestructive = false
}

/// The ⌘K panel of a running command; not `PopoverMenu`, because it scrolls.
struct ExtensionActionsPanel: View {
    @Environment(\.metrics) private var metrics
    var header: String?
    let items: [ExtensionActionItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void

    /// The palette arms this only once the pointer has moved of its own accord.
    @Environment(PaletteState.self) private var palette
    /// A hovered row is already visible, so scrolling would drag the list under it.
    @State private var hoverSelection: Int?

    private var panel: Metrics { Metrics(interface: metrics) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let header {
                Text(header)
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, metrics.spacing.lg)
                    .padding(.top, metrics.spacing.xs)
                    .padding(.bottom, metrics.spacing.xs / 2)
            }
            // The header stays put while rows move under it.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: panel.rowSpacing) {
                        // Index-as-id is stable: a panel's rows never reorder while it is open.
                        ForEach(items.indices, id: \.self) { index in
                            ExtensionActionRow(
                                item: items[index],
                                selected: index == selection,
                                onActivate: { onActivate(index) }
                            )
                            .id(index)
                            .onContinuousHover { if case .active = $0 { hover(index) } }
                        }
                    }
                }
                .frame(height: panel.height(rows: items.count))
                // Without this a panel shorter than the cap rubber-bands against nothing.
                .scrollBounceBehavior(.basedOnSize)
                // `never`, not `hidden`: hidden still lets AppKit claim the scroller's gutter.
                .scrollIndicators(.never)
                .overflowFade()
                .onChange(of: selection) {
                    let movedByPointer = hoverSelection == selection
                    hoverSelection = nil
                    guard !movedByPointer else { return }
                    // No anchor: reveal the row, never re-centre the list around it.
                    proxy.scrollTo(selection)
                }
            }
        }
        .padding(metrics.spacing.sm)
        .frame(width: panel.width)
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
        )
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
            HStack(spacing: metrics.spacing.sm) {
                icon
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

    /// Drawn here, not by `ExtensionIconView`, whose scale would shrink the 20pt slot.
    @ViewBuilder
    private var icon: some View {
        if case .symbol(let name) = item.icon.source {
            Image(systemName: name)
                .font(metrics.typography.menuIcon)
                .symbolRenderingMode(item.icon.tint == nil ? .hierarchical : .monochrome)
                .foregroundStyle(item.icon.tint ?? Color.secondary)
                .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
        } else {
            ExtensionIconView(resolved: item.icon, size: metrics.size.menuIcon)
        }
    }
}
