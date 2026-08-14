import SwiftUI

/// Sized here rather than in `Theme`: this is the extensions surface, and the palette's own menus
/// need no cap because they are short by construction.
///
/// File-scoped so the row and the height that counts rows read the same numbers. A cap expressed in
/// points would drift the moment a row's padding changed, and the panel would cut a row in half.
private enum Metrics {
    static let width: CGFloat = 300
    /// The glyph slot plus its breathing room — the tallest thing a row contains.
    static let rowHeight: CGFloat = Theme.Size.menuIcon + Theme.Spacing.md * 2
    static let rowSpacing: CGFloat = 1
    /// Six rows and half of the seventh, so a long panel reads as scrollable rather than clipped.
    static let visibleRows: CGFloat = 6.5
    static var maxHeight: CGFloat { visibleRows * (rowHeight + rowSpacing) }
}

/// The ⌘K panel of a running extension command.
///
/// Separate from `PopoverMenu` on purpose. An extension declares its own action panel, and a real one
/// runs to a dozen rows or more — the GIF search extension ships fourteen — so this scrolls where the
/// palette's own menus never need to. Keeping it here means the palette's menu can change, or this
/// one can, without the other having to move.
struct ExtensionActionsPanel: View {
    var header: String?
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void

    /// Set when the pointer moved the highlight, and cleared the moment it is read. A hovered row is
    /// already visible by definition, so scrolling to it would drag the list out from under the cursor.
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
                // No scrollbar at all, like a real macOS menu: the half row the cap leaves showing is
                // the affordance. `thinScrollbar` is tuned to the palette's floating bars, and the
                // native scroller draws through the glass corner.
                .scrollIndicators(.hidden)
                .onChange(of: selection) {
                    let movedByPointer = hoverSelection == selection
                    hoverSelection = nil
                    guard !movedByPointer else { return }
                    // No anchor: scroll the least that reveals the row, so a keyboard step near the
                    // middle doesn't re-centre the whole list under the reader's eye.
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

/// One action row. Its own, not the palette's: that one is file-private, and an extension's row is
/// free to grow a badge or a submenu chevron without the launcher's menus inheriting it.
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
