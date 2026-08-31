import SwiftUI

/// File-scoped so a row and the cap that counts rows read one number.
private enum Metrics {
    static let width: CGFloat = 300
    /// The glyph slot plus its breathing room — the tallest thing a row contains.
    static let rowHeight: CGFloat = Theme.Size.menuIcon + Theme.Spacing.md * 2
    static let rowSpacing: CGFloat = 1
    /// Six rows and half of the seventh, so a long panel reads as scrollable rather than clipped.
    static let visibleRows: CGFloat = 6.5
    /// Rounded: a fractional height lands the glass edge on a half pixel.
    static var maxHeight: CGFloat { (visibleRows * (rowHeight + rowSpacing)).rounded() }

    /// Exact, because every row is one known height: no measuring pass, and no greedy scroll view.
    static func height(rows: Int) -> CGFloat {
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
    var header: String?
    let items: [ExtensionActionItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void

    /// The palette arms this only once the pointer has moved of its own accord.
    @Environment(PaletteState.self) private var palette
    /// A hovered row is already visible, so scrolling would drag the list under it.
    @State private var hoverSelection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let header {
                Text(header)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.xs / 2)
            }
            // The header stays put while rows move under it.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
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
                .frame(height: Metrics.height(rows: items.count))
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
        .padding(Theme.Spacing.sm)
        .frame(width: Metrics.width)
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
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
    let item: ExtensionActionItem
    let selected: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: Theme.Spacing.sm) {
                icon
                Text(item.title)
                    .font(Theme.Typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let shortcut = item.shortcut {
                    HStack(spacing: Theme.Spacing.xxs) {
                        ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                            KeyCapChip(text: String(glyph), style: .outline)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            // Fixed, not padded: the height maths above counts rows, so a row is one exact height.
            .frame(
                maxWidth: .infinity, minHeight: Metrics.rowHeight, maxHeight: Metrics.rowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
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
                .font(Theme.Typography.menuIcon)
                .symbolRenderingMode(item.icon.tint == nil ? .hierarchical : .monochrome)
                .foregroundStyle(item.icon.tint ?? Color.secondary)
                .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
        } else {
            ExtensionIconView(resolved: item.icon, size: Theme.Size.menuIcon)
        }
    }
}
