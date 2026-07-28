import SwiftUI

/// A menu row's leading glyph: an SF Symbol, or a real app icon (the paste target) drawn from `IconCache`.
enum PopoverMenuIcon: Equatable {
    case symbol(String)
    case file(path: String)

    /// Glyph for a paste row: the target app's own icon when it's known, else the row's generic symbol.
    static func paste(_ target: PasteTarget?, fallback: String) -> PopoverMenuIcon {
        guard let path = target?.iconPath else { return .symbol(fallback) }
        return .file(path: path)
    }
}

/// One popover-menu row's data: the render path and the keyboard handlers both address rows through these, so a selection index can drive highlight and activation. Actions are pure — closing the menu is the caller's job (one central `onActivate`).
struct PopoverMenuItem {
    let title: String
    let icon: PopoverMenuIcon
    var shortcut: String? = nil
    /// Destructive rows (delete) tint their icon + label red, matching the native menu convention.
    var isDestructive: Bool = false
    let action: () -> Void

    init(
        title: String, icon: PopoverMenuIcon, shortcut: String? = nil, isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.isDestructive = isDestructive
        self.action = action
    }

    init(
        title: String, systemImage: String, shortcut: String? = nil, isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), shortcut: shortcut,
            isDestructive: isDestructive, action: action)
    }
}

/// A popover menu's header + rows, built once per feature and consumed by both the render path and `RootPaletteView`'s keyboard handlers.
struct PopoverMenuContent {
    var header: String? = nil
    let items: [PopoverMenuItem]
}

/// In-window overlay menu (not a system popover), anchored to a bottom corner so it stays clipped inside the palette, with a stock Liquid Glass surface. Data-driven so `selection` can highlight a row for keyboard navigation; `onActivate(index)` is the single path fired by both a click and Return.
struct PopoverMenu: View {
    var header: String? = nil
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void

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
            // Index-as-id is stable because a menu's rows never reorder while it is open, and the index is what selection/activation address.
            ForEach(items.indices, id: \.self) { index in
                PopoverMenuRow(
                    item: items[index],
                    selected: index == selection,
                    onHover: { selection = index },
                    onActivate: { onActivate(index) }
                )
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.Size.menuWidth)
        // Tahoe glass carries its own elevation/shadow; a hand-tuned drop shadow on top reads heavy and non-native, so we let the glass own it.
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        )
    }
}

/// A single menu row: leading SF Symbol, label, optional trailing shortcut glyph. Highlight is selection-driven (hover reports up so keyboard and mouse converge on one highlight), so there is never more than one active row.
private struct PopoverMenuRow: View {
    let item: PopoverMenuItem
    let selected: Bool
    /// Fired when the cursor enters the row so the owner can move selection here — keyboard and mouse then share one highlight.
    let onHover: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            // `sm`, not the row-standard `lg`: the 20pt icon slot carries 2–3pt of its own slack around the glyph, so a 10pt gap reads as ~12.
            HStack(spacing: Theme.Spacing.sm) {
                switch item.icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(Theme.Typography.menuIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.isDestructive ? Color.red : Color.secondary)
                        .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                case .file(let path):
                    MenuFileIcon(path: path)
                }
                Text(item.title)
                    .font(Theme.Typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                Spacer(minLength: Theme.Spacing.sm)
                if let shortcut = item.shortcut {
                    HStack(spacing: Theme.Spacing.xxs) {
                        ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                            KeyCapChip(text: String(glyph), style: .outline)
                        }
                    }
                }
            }
            // The icon slot is the tallest element on every row, so it pins one height for rows with and without a shortcut — no explicit minHeight needed.
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
}

/// App icon for a menu row (mirrors `AppIconView`): seeds from the warm `IconCache` so the paste target paints on the first frame, decoding off-main only on a miss.
private struct MenuFileIcon: View {
    let path: String
    @State private var image: NSImage?

    init(path: String) {
        self.path = path
        _image = State(initialValue: IconCache.cached(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
        .task(id: path) {
            guard image == nil else { return }
            image = await IconCache.loadAsync(forFile: path)
        }
    }
}
