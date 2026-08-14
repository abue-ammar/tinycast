import SwiftUI

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

    /// Sized here rather than in `Theme`: this is the extensions surface, and the palette's own menus
    /// have no cap because they are short by construction.
    private enum Metrics {
        static let width: CGFloat = 300
        /// The panel less both bars, so a long panel is bounded by the window rather than clipped by it.
        static let maxHeight: CGFloat =
            Theme.Size.panelHeight - Theme.Size.headerHeight - Theme.Size.bottomBarHeight
    }

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
                    VStack(alignment: .leading, spacing: 1) {
                        // Index-as-id is stable: a panel's rows never reorder while it is open.
                        ForEach(items.indices, id: \.self) { index in
                            ExtensionActionRow(
                                item: items[index],
                                selected: index == selection,
                                onHover: { selection = index },
                                onActivate: { onActivate(index) }
                            )
                            .id(index)
                        }
                    }
                    .hideNativeScrollers()
                }
                .frame(maxHeight: Metrics.maxHeight)
                // Without this a panel shorter than the cap rubber-bands against nothing.
                .scrollBounceBehavior(.basedOnSize)
                .thinScrollbar()
                .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
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
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
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
