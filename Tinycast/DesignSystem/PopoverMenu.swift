import SwiftUI

/// A menu row's leading glyph: a symbol, or a real app icon from `IconCache`.
enum PopoverMenuIcon: Equatable {
    case symbol(String)
    case file(path: String)

    /// A paste row's glyph: the target app's icon when known, else a generic symbol.
    static func paste(_ target: PasteTarget?, fallback: String) -> PopoverMenuIcon {
        guard let path = target?.iconPath else { return .symbol(fallback) }
        return .file(path: path)
    }
}

/// One menu row; both the render path and the key handlers address rows through these.
struct PopoverMenuItem {
    let title: String
    let icon: PopoverMenuIcon
    var shortcut: String?
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

/// A menu's header and rows, built once and consumed by render and keyboard alike.
struct PopoverMenuContent {
    var header: String?
    let items: [PopoverMenuItem]
}

/// An in-window overlay menu, not a system popover, so it clips inside the palette.
struct PopoverMenu: View {
    var header: String?
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    /// Fixed, never intrinsic: a menu whose width tracked its longest row would jitter as it changes.
    var width: CGFloat = Theme.Size.menuWidth
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
            // Index-as-id is stable: a menu's rows never reorder while it is open.
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
        .frame(width: width)
        // Glass carries its own elevation, so a drop shadow on top reads heavy.
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        )
    }
}

/// One menu row; highlight is selection-driven, so only one row is ever active.
private struct PopoverMenuRow: View {
    let item: PopoverMenuItem
    let selected: Bool
    /// Fired on enter, so the owner can move selection and share one highlight.
    let onHover: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            // `sm`, not `lg`: the icon slot carries its own slack, so the gap reads wider.
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
            // The icon slot is the tallest element, so it pins one height for every row.
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

/// A menu row's app icon, seeded warm so the paste target paints on the first frame.
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
