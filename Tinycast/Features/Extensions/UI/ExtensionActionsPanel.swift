import SwiftUI

/// File-scoped so a row and the cap that counts rows read one number, and can't drift into half a row.
private enum Metrics {
    static let width: CGFloat = 300
    /// The glyph slot plus its breathing room — the tallest thing a row contains.
    static let rowHeight: CGFloat = Theme.Size.menuIcon + Theme.Spacing.md * 2
    static let rowSpacing: CGFloat = 1
    /// Six rows and half of the seventh, so a long panel reads as scrollable rather than clipped.
    static let visibleRows: CGFloat = 6.5
    static var maxHeight: CGFloat { visibleRows * (rowHeight + rowSpacing) }
}

/// The ⌘K panel of a running command. Not `PopoverMenu`: an extension's panel is long, so it scrolls.
struct ExtensionActionsPanel: View {
    var header: String?
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void

    /// A hovered row is already visible, so scrolling to it would drag the list from under the cursor.
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
            // The header stays put while rows move under it, so what the panel belongs to stays read.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                        // Index-as-id is stable: a panel's rows never reorder while it is open.
                        ForEach(items.indices, id: \.self) { index in
                            ExtensionActionRow(
                                item: items[index],
                                selected: index == selection,
                                onHover: {
                                    hoverSelection = index
                                    selection = index
                                },
                                onActivate: { onActivate(index) }
                            )
                            .id(index)
                        }
                    }
                }
                .frame(maxHeight: Metrics.maxHeight)
                // Without this a panel shorter than the cap rubber-bands against nothing.
                .scrollBounceBehavior(.basedOnSize)
                // None, like a real menu: `thinScrollbar` wants floating bars, the native one cuts glass.
                .scrollIndicators(.hidden)
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
        // Glass carries its own elevation, so a drop shadow on top reads heavy.
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        )
    }
}

/// Its own row, not the palette's: that one is file-private, and this one may grow its own trimmings.
private struct ExtensionActionRow: View {
    let item: PopoverMenuItem
    let selected: Bool
    /// Fired on enter, so the owner can move selection and share one highlight.
    let onHover: () -> Void
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
            // Fixed, not padded: the cap above counts rows, so a row has to be one known height.
            .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHover() } }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(Theme.Typography.menuIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isDestructive ? Color.red : Color.secondary)
                .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
        case .file(let path):
            ExtensionIconView(
                resolved: ExtensionImage.Resolved(source: .file(path)), size: Theme.Size.menuIcon)
        }
    }
}
