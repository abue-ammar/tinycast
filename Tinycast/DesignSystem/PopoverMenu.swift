import SwiftUI

/// A menu row's leading glyph: a symbol, a bundled template asset, or an app icon from `IconCache`.
enum PopoverMenuIcon: Equatable {
    case symbol(String)
    case asset(String)
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

/// The palette's own menu, hosted by `MenuPanelController` in a window of its own.
struct PopoverMenu: View {
    var header: String?
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    /// Fixed, never intrinsic: a menu whose width tracked its longest row would jitter as it changes.
    var width: CGFloat = Theme.Size.menuWidth
    let onActivate: (Int) -> Void

    /// The palette arms this only once the pointer has moved of its own accord.
    @Environment(PaletteState.self) private var palette
    /// Set by the pointer so the reveal can tell its own move from a keyboard one.
    @State private var pointerSelection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Size.menuRowSpacing) {
            if let header { headerLabel(header) }
            rows
        }
        .padding(Theme.Spacing.sm)
        .frame(width: width)
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        )
    }

    private func headerLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xs / 2)
    }

    /// Rows alone scroll, under a header that keeps naming what they act on.
    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Size.menuRowSpacing) {
                    // Index-as-id is stable: a menu's rows never reorder while it is open.
                    ForEach(items.indices, id: \.self) { index in
                        PopoverMenuRow(item: items[index], selected: index == selection) {
                            onActivate(index)
                        }
                        .id(index)
                        .onContinuousHover { if case .active = $0 { hover(index) } }
                    }
                }
            }
            .frame(height: viewportHeight)
            // `never`, not `hidden`: hidden still lets AppKit claim the scroller's gutter.
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .overflowFade()
            .onChange(of: selection) {
                let byPointer = pointerSelection == selection
                pointerSelection = nil
                guard !byPointer else { return }
                proxy.scrollTo(selection)
            }
        }
    }

    /// Exact, because every row is one known height: no measuring pass, and no greedy scroll view.
    private var viewportHeight: CGFloat {
        let count = CGFloat(items.count)
        let pitch = Theme.Size.menuRowHeight + Theme.Size.menuRowSpacing
        return min(count * pitch - Theme.Size.menuRowSpacing, Theme.Size.menuRowsMaxHeight)
    }

    /// Armed only once the pointer has moved of its own accord, so a scroll past it lights nothing.
    private func hover(_ index: Int) {
        guard palette.hoverHighlightArmed, index != selection else { return }
        pointerSelection = index
        selection = index
    }
}

/// One menu row; highlight is selection-driven, so only one row is ever active.
private struct PopoverMenuRow: View {
    let item: PopoverMenuItem
    let selected: Bool
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
                case .asset(let name):
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(item.isDestructive ? Color.red : Color.secondary)
                        .frame(width: Theme.Size.menuBrandIcon, height: Theme.Size.menuBrandIcon)
                        .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                case .file(let path):
                    MenuFileIcon(path: path)
                }
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
            // Stated, not padded: the height maths above counts rows, so a row is one exact height.
            .frame(
                maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight,
                maxHeight: Theme.Size.menuRowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A menu row's app icon, seeded warm so the paste target paints on the first frame.
struct MenuFileIcon: View {
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
        .task(id: IconRequest(path)) {
            guard image == nil else { return }
            image = await IconCache.loadAsync(forFile: path)
        }
    }
}
