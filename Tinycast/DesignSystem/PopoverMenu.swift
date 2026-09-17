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
    let isEnabled: Bool
    var sectionTitle: String?
    var startsSection: Bool
    var shortcut: String?
    /// A value the row states rather than a chord it runs — what a "Copy as" row copies.
    var detail: String?
    /// Destructive rows (delete) tint their icon + label red, matching the native menu convention.
    var isDestructive: Bool = false
    let action: () -> Void

    /// What the keyboard and pointer may land on; a loading or disabled row only states itself.
    var isSelectable: Bool { isEnabled && !isLoading }

    init(
        title: String, icon: PopoverMenuIcon, isLoading: Bool = false, isEnabled: Bool = true,
        sectionTitle: String? = nil, startsSection: Bool = false, shortcut: String? = nil,
        detail: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.sectionTitle = sectionTitle
        self.startsSection = startsSection
        self.shortcut = shortcut
        self.detail = detail
        self.isDestructive = isDestructive
        self.action = action
    }

    init(
        title: String, systemImage: String, isLoading: Bool = false, isEnabled: Bool = true,
        sectionTitle: String? = nil, startsSection: Bool = false, shortcut: String? = nil,
        isDestructive: Bool = false, action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), isLoading: isLoading, isEnabled: isEnabled,
            sectionTitle: sectionTitle, startsSection: startsSection, shortcut: shortcut,
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
    enum Attachment {
        case none
        case bottomLeading
        case bottomTrailing
    }

    struct Search {
        enum Placement {
            case top
            case bottom
        }

        let placeholder: String
        let placement: Placement
    }

    struct SurfaceShape: Shape {
        let attachment: Attachment
        let radius: CGFloat
        let attachedRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: attachment == .bottomLeading ? attachedRadius : radius,
                bottomTrailingRadius: attachment == .bottomTrailing ? attachedRadius : radius,
                topTrailingRadius: radius,
                style: .continuous
            ).path(in: rect)
        }
    }

    var header: String?
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    /// Fixed, never intrinsic: a width tracking the longest row would jitter as rows change.
    var width: CGFloat?
    let onActivate: (Int) -> Void
    var attachment = Attachment.none
    let search: Search

    /// The palette arms this only once the pointer has moved of its own accord.
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @FocusState private var searchFocused: Bool
    /// Set by the pointer so the reveal can tell its own move from a keyboard one.
    @State private var pointerSelection: Int?

    private var listInset: CGFloat { metrics.spacing.md }
    var body: some View {
        let shape = SurfaceShape(
            attachment: attachment, radius: metrics.radius.menuPanel,
            attachedRadius: metrics.size.menuButton / 2)
        surfaceContent
            .frame(width: width ?? metrics.size.menuWidth)
            .glassEffect(.regular, in: shape)
    }

    private var surfaceContent: some View {
        VStack(spacing: 0) {
            if search.placement == .top {
                searchField
                searchSeparator
            }
            menuContent
            if search.placement == .bottom {
                searchSeparator
                searchField
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if let header {
                    headerLabel(header)
                    Color.clear.frame(height: metrics.size.menuRowSpacing)
                }
                Text("No Results")
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.size.menuRowHeight)
            }
            .padding(listInset)
        } else {
            rows
        }
    }

    private var searchField: some View {
        @Bindable var palette = palette
        let placeholder = search.placeholder
        return TextField("", text: $palette.menuQuery)
            .textFieldStyle(.plain)
            .font(metrics.typography.menuRow)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
            .lineLimit(1)
            .background(alignment: .leading) {
                if palette.menuQuery.isEmpty {
                    Text(placeholder)
                        .font(metrics.typography.menuRow)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.spacing.xl + metrics.spacing.sm)
            .frame(height: metrics.size.menuRowHeight)
            .offset(y: search.placement == .bottom ? -metrics.spacing.xxs / 2 : 0)
            .padding(.vertical, metrics.spacing.xxs / 2)
            .accessibilityLabel(placeholder)
            .onAppear { searchFocused = true }
    }

    private var searchSeparator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: Theme.Size.hairline)
            .accessibilityHidden(true)
    }

    private func headerLabel(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: metrics.size.menuSectionHeader, alignment: .leading)
            .padding(.horizontal, metrics.spacing.lg)
            .padding(.top, metrics.spacing.xs)
            .padding(.bottom, metrics.spacing.xs / 2)
    }

    /// The title and rows move as one surface, while row IDs still drive keyboard reveal.
    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let header {
                        headerLabel(header)
                        Color.clear.frame(height: metrics.size.menuRowSpacing)
                    }
                    // Index-as-id is stable: a menu's rows never reorder while it is open.
                    ForEach(items.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            rowBoundary(before: index)
                            VStack(alignment: .leading, spacing: 0) {
                                if let sectionTitle = items[index].sectionTitle {
                                    sectionLabel(sectionTitle, isFirst: index == 0)
                                }
                                PopoverMenuRow(
                                    item: items[index],
                                    selected: index == selection && items[index].isSelectable
                                ) {
                                    onActivate(index)
                                }
                            }
                            .onContinuousHover { if case .active = $0 { hover(index) } }
                        }
                        .id(index)
                    }
                }
                .padding(listInset)
            }
            .frame(height: viewportHeight + listInset * 2)
            // `never`, not `hidden`: hidden still lets AppKit claim the scroller's gutter.
            .scrollIndicators(.never)
            .scrollBounceBehavior(contentHeight > viewportCapacity ? .always : .basedOnSize)
            // The hosting view outlives a presentation, so a fresh one must not inherit the offset.
            .id(palette.menuPresentationToken)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) {
                let byPointer = pointerSelection == selection
                pointerSelection = nil
                guard !byPointer else { return }
                proxy.scrollTo(selection)
            }
        }
    }

    @ViewBuilder
    private func rowBoundary(before index: Int) -> some View {
        if index > 0, items[index].startsSection {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: Theme.Size.hairline)
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.sm)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if index > 0 {
            Color.clear.frame(height: metrics.size.menuRowSpacing)
        }
    }

    /// Exact, because every row is one known height: no measuring pass, and no greedy scroll view.
    private var viewportHeight: CGFloat {
        min(contentHeight, viewportCapacity)
    }

    private var viewportCapacity: CGFloat { metrics.size.menuRowsMaxHeight + headerExtent }

    private var contentHeight: CGFloat {
        let rows = CGFloat(items.count)
        let separators = CGFloat(items.dropFirst().filter(\.startsSection).count)
        let regularGaps = max(rows - 1 - separators, 0)
        let separatorHeight = metrics.spacing.sm * 2 + Theme.Size.hairline
        var contentHeight =
            headerExtent
            + rows * metrics.size.menuRowHeight + regularGaps * metrics.size.menuRowSpacing
            + separators * separatorHeight
        for (index, item) in items.enumerated() where item.sectionTitle != nil {
            contentHeight += metrics.size.menuSectionHeader + metrics.spacing.xxs
            if index > 0 { contentHeight += metrics.spacing.md }
        }
        return contentHeight
    }

    private var headerExtent: CGFloat {
        guard header != nil else { return 0 }
        return metrics.size.menuSectionHeader + metrics.spacing.xs * 1.5
            + metrics.size.menuRowSpacing
    }

    /// Tighter below than above, so a header belongs to the rows under it, not between two groups.
    private func sectionLabel(_ title: String, isFirst: Bool) -> some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                maxWidth: .infinity, minHeight: metrics.size.menuSectionHeader,
                maxHeight: metrics.size.menuSectionHeader, alignment: .leading
            )
            // `md`, matching a row's own inset, so header and icon share one edge.
            .padding(.horizontal, metrics.spacing.md)
            .padding(.top, isFirst ? 0 : metrics.spacing.md)
            .padding(.bottom, metrics.spacing.xxs)
    }

    /// Armed only once the pointer has moved of its own accord, so a scroll past it lights nothing.
    private func hover(_ index: Int) {
        guard palette.hoverHighlightArmed, items[index].isSelectable, index != selection else {
            return
        }
        pointerSelection = index
        selection = index
    }
}

/// One menu row; highlight is selection-driven, so only one row is ever active.
private struct PopoverMenuRow: View {
    let item: PopoverMenuItem
    let selected: Bool
    let onActivate: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: metrics.spacing.md) {
                if item.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                } else {
                    switch item.icon {
                    case .blank:
                        EmptyView()
                    case .symbol(let name):
                        Image(
                            systemName: SystemSymbolName.resolve(
                                name, isDark: colorScheme == .dark)
                        )
                        .font(
                            .system(
                                size: metrics.scaled(Theme.Typography.menuSymbolSize),
                                weight: Theme.Typography.menuSymbolWeight)
                        )
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            item.isDestructive ? Color.red : Theme.Colors.menuSymbol
                        )
                        .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    case .asset(let name):
                        Image(name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(item.isDestructive ? Color.red : Color.secondary)
                            .frame(width: metrics.size.menuBrandIcon, height: metrics.size.menuBrandIcon)
                            .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    case .file(let path):
                        MenuFileIcon(path: path)
                    }
                }
                Text(item.title)
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if let detail = item.detail {
                    Text(detail)
                        // Smaller than the title it trails: a stated value, not a second label.
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // A notation opens with what identifies it, so the tail is what can go.
                        .truncationMode(.tail)
                }
                if let shortcut = item.shortcut {
                    HStack(spacing: metrics.spacing.xxs) {
                        ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                            KeyCapChip(text: String(glyph), style: .outline)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            // Stated, not padded: the height maths above counts rows, so a row is one exact height.
            .frame(
                maxWidth: .infinity, minHeight: metrics.size.menuRowHeight,
                maxHeight: metrics.size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
            .opacity(item.isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!item.isSelectable)
    }
}

/// A menu row's app icon, seeded warm so the paste target paints on the first frame.
struct MenuFileIcon: View {
    let path: String
    @State private var image: NSImage?
    @Environment(\.metrics) private var metrics

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
        .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
        .task(id: IconRequest(path)) {
            guard image == nil else { return }
            image = await IconCache.loadAsync(forFile: path)
        }
    }
}
