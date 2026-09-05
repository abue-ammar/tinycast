import SwiftUI

/// A menu row's leading glyph: a symbol, a bundled template asset, or an app icon from `IconCache`.
enum PopoverMenuIcon: Equatable {
    case symbol(String)
    case asset(String)
    case file(path: String)
    /// No glyph and no slot: a run of rows under one repeated icon says more without it.
    case blank

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
    let isLoading: Bool
    var sectionTitle: String?
    var shortcut: String?
    /// A value the row states rather than a chord it runs — what a "Copy as" row copies.
    var detail: String?
    /// Destructive rows (delete) tint their icon + label red, matching the native menu convention.
    var isDestructive: Bool = false
    let action: () -> Void

    init(
        title: String, icon: PopoverMenuIcon, isLoading: Bool = false, sectionTitle: String? = nil,
        shortcut: String? = nil, detail: String? = nil,
        isDestructive: Bool = false, action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.sectionTitle = sectionTitle
        self.shortcut = shortcut
        self.detail = detail
        self.isDestructive = isDestructive
        self.action = action
    }

    init(
        title: String, systemImage: String, isLoading: Bool = false, sectionTitle: String? = nil,
        shortcut: String? = nil, isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), isLoading: isLoading,
            sectionTitle: sectionTitle, shortcut: shortcut,
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
    /// Fixed, never intrinsic: a width tracking the longest row would jitter as rows change.
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
                        VStack(alignment: .leading, spacing: Theme.Size.menuRowSpacing) {
                            if let sectionTitle = items[index].sectionTitle {
                                sectionLabel(sectionTitle)
                            }
                            PopoverMenuRow(item: items[index], selected: index == selection) {
                                onActivate(index)
                            }
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
        let rows = CGFloat(items.count)
        let headers = CGFloat(items.count { $0.sectionTitle != nil })
        let contentHeight = rows * Theme.Size.menuRowHeight
            + headers * (Theme.Size.menuRowHeight + Theme.Size.menuRowSpacing)
            + max(rows - 1, 0) * Theme.Size.menuRowSpacing
        return min(contentHeight, Theme.Size.menuRowsMaxHeight)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xs)
            .frame(
                maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight,
                maxHeight: Theme.Size.menuRowHeight, alignment: .bottomLeading)
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
                if item.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                } else {
                    switch item.icon {
                    case .blank:
                        EmptyView()
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
                }
                Text(item.title)
                    .font(Theme.Typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let detail = item.detail {
                    Text(detail)
                        // Smaller than the title it trails: a stated value, not a second label.
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // A notation opens with what identifies it, so the tail is what can go.
                        .truncationMode(.tail)
                }
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
                maxHeight: Theme.Size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(item.isLoading)
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
