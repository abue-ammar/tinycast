import SwiftUI

/// Row order comes from `ExtensionScreen`, so the palette's flat index matches the draw.
struct ExtensionListView: View {
    @Environment(\.isDarkAppearance) private var isDark
    let screen: ExtensionScreen
    let selection: Int
    let assetsPath: String?
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void

    var body: some View {
        Group {
            if screen.items.isEmpty {
                emptyState
            } else if screen.showsDetail {
                HStack(spacing: 0) {
                    rowList
                        .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle().fill(Theme.Colors.separator).frame(width: 1)
                    detailPane
                }
            } else if case .grid(let layout) = screen.kind {
                gridBody(layout: layout)
            } else {
                rowList
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if screen.isLoading {
            EmptyResults(text: "Loading…")
        } else if let empty = screen.emptyView {
            VStack(spacing: Theme.Spacing.md) {
                ExtensionIconView(
                    resolved: ExtensionImage.resolve(
                        empty.props["icon"], assetsPath: assetsPath, isDark: isDark),
                    size: 42)
                Text(empty.string("title") ?? "Nothing here")
                    .font(Theme.Typography.rowTitle)
                if let description = empty.string("description") {
                    Text(description)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyResults(text: "No results")
        }
    }

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(screen.rows) { row in
                        switch row {
                        case .header(let title, let subtitle, _):
                            SectionHeader(
                                title: [title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }
                                    .joined(separator: "  ·  "),
                                isFirst: row.id == screen.rows.first?.id)
                        case .item(let item):
                            ExtensionItemRow(
                                node: item.node, selected: item.index == selection,
                                assetsPath: assetsPath, compact: screen.showsDetail
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(item.index)
                                onActivate(item.index)
                            }
                            .onRightClick { onActions(item.index) }
                            .selectionFrame(item.index == selection)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selection == 0, proxy: proxy)
        }
    }

    /// Scroll id of the selected item, or nil when the selection is out of range.
    private var selectedRowID: String? {
        screen.items.indices.contains(selection) ? screen.items[selection].id : nil
    }

    /// Measured once for the whole grid: a tile's own `GeometryReader` would cost a pass per cell.
    private func gridBody(layout: ExtensionGridLayout) -> some View {
        GeometryReader { geometry in
            grid(
                layout: layout,
                tileWidth: layout.tileWidth(
                    inWidth: geometry.size.width - Theme.Spacing.md * 2,
                    spacing: Theme.Spacing.sm))
        }
    }

    private func grid(layout: ExtensionGridLayout, tileWidth: Double) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm),
                        count: layout.columns),
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(screen.items) { item in
                        ExtensionGridCell(
                            node: item.node, selected: item.index == selection,
                            assetsPath: assetsPath, layout: layout, width: tileWidth
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(item.index)
                            onActivate(item.index)
                        }
                        .onRightClick { onActions(item.index) }
                        .selectionFrame(item.index == selection)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selection < layout.columns, proxy: proxy)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if screen.items.indices.contains(selection),
            let detail = screen.items[selection].node.node("detail")
        {
            ExtensionDetailBody(
                markdown: detail.string("markdown"), metadata: detail.node("metadata"),
                isLoading: detail.bool("isLoading") ?? false, assetsPath: assetsPath)
        } else {
            Color.clear
        }
    }
}

/// One `List.Item`: icon, title, subtitle, then its accessories right-aligned.
private struct ExtensionItemRow: View {
    @Environment(\.isDarkAppearance) private var isDark
    let node: RenderNode
    let selected: Bool
    let assetsPath: String?
    let compact: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ExtensionIconView(
                resolved: ExtensionImage.resolve(node.props["icon"], assetsPath: assetsPath, isDark: isDark))
            Text(node.string("title") ?? "")
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                // A detail list is 290pt wide, and an accessory would otherwise win the squeeze.
                .layoutPriority(1)
            if !compact, let subtitle = node.string("subtitle"), !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            // Raycast draws the accessories it is given, and a quota row's signal is all in them.
            ExtensionAccessoriesView(
                accessories: node.array("accessories"), assetsPath: assetsPath)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

/// `List.Item.Accessory` values: text, a tag, a date, an icon, or a combination.
struct ExtensionAccessoriesView: View {
    @Environment(\.isDarkAppearance) private var isDark
    let accessories: [RenderValue]
    let assetsPath: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(accessories.enumerated()), id: \.offset) { _, accessory in
                if let fields = accessory.objectValue {
                    accessoryView(fields)
                }
            }
        }
    }

    @ViewBuilder
    private func accessoryView(_ fields: [String: RenderValue]) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let icon = fields["icon"] {
                ExtensionIconView(
                    resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark), size: 13)
            }
            if let tag = fields["tag"] {
                tagView(tag)
            }
            if let text = ExtensionAccessoriesView.label(fields["text"]) {
                Text(text)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(
                        ExtensionImage.color(fields["text"]?.objectValue?["color"], isDark: isDark)
                            ?? Theme.Colors.textSecondary
                    )
                    .lineLimit(1)
            }
            if let date = ExtensionAccessoriesView.date(fields["date"]) {
                Text(date, format: .relative(presentation: .numeric))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .help(fields["tooltip"]?.stringValue ?? "")
    }

    /// A tag is `{value, color}` or a bare string/date.
    @ViewBuilder
    private func tagView(_ tag: RenderValue) -> some View {
        let fields = tag.objectValue
        let text =
            ExtensionAccessoriesView.label(fields?["value"] ?? tag)
            ?? ExtensionAccessoriesView.date(fields?["value"] ?? tag).map {
                $0.formatted(date: .abbreviated, time: .omitted)
            }
        if let text {
            let color = ExtensionImage.color(fields?["color"], isDark: isDark) ?? Theme.Colors.textSecondary
            Text(text)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.16))
                )
                .lineLimit(1)
        }
    }

    /// `text` may be a string or `{value, color}`.
    static func label(_ value: RenderValue?) -> String? {
        guard let value else { return nil }
        if let text = value.stringValue { return text }
        return value.objectValue?["value"]?.stringValue
    }

    static func date(_ value: RenderValue?) -> Date? {
        guard let value else { return nil }
        if let date = value.dateValue { return date }
        return value.objectValue?["value"]?.dateValue
    }
}

/// One `Grid.Item`: content sized to the tile the `Grid`'s props ask for, title underneath.
private struct ExtensionGridCell: View {
    @Environment(\.isDarkAppearance) private var isDark
    let node: RenderNode
    let selected: Bool
    let assetsPath: String?
    let layout: ExtensionGridLayout
    let width: Double
    @State private var hovered = false

    private var content: RenderValue? { node.props["content"] }

    /// A tile may be a bare `{color}` swatch instead, which has no image to resolve.
    private var swatch: Color? {
        guard let fields = content?.objectValue else { return nil }
        return ExtensionImage.color((fields["value"]?.objectValue ?? fields)["color"], isDark: isDark)
    }

    private var height: Double { width / layout.aspectRatio }

    private var contentSize: CGSize {
        let inset = width * layout.inset.fraction
        return CGSize(width: width - inset * 2, height: height - inset * 2)
    }

    private var background: Color {
        if selected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : ExtensionColors.gridItemFill
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            tile
            if let title = node.string("title") {
                Text(title)
                    .font(Theme.Typography.rowTrailing)
                    .lineLimit(1)
            }
            if let subtitle = node.string("subtitle") {
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .armedHover($hovered)
    }

    private var tile: some View {
        tileContent
            .frame(width: contentSize.width, height: contentSize.height)
            .clipShape(RoundedRectangle(cornerRadius: contentRadius, style: .continuous))
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: ExtensionGridLayout.tileRadius, style: .continuous)
                    .fill(background)
            )
            // A tile filled edge to edge hides that fill, so the ring is what marks the selection.
            .overlay {
                RoundedRectangle(cornerRadius: ExtensionGridLayout.tileRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
                    .opacity(selected ? 1 : 0)
            }
    }

    /// Filling content shares the tile's corner; inset artwork is small enough to need a tighter one.
    private var contentRadius: Double {
        layout.inset == .zero ? ExtensionGridLayout.tileRadius : Theme.Radius.thumbnail
    }

    /// `content` is an `ImageLike` or `{value, tooltip}` wrapping one — both `resolve`'s job.
    @ViewBuilder
    private var tileContent: some View {
        let resolved = ExtensionImage.resolve(content, assetsPath: assetsPath, isDark: isDark)
        if resolved == nil, let swatch {
            Rectangle().fill(swatch)
        } else {
            ExtensionGridContentView(resolved: resolved, fills: layout.fills, size: contentSize)
        }
    }
}

/// A tile's image, scaled to the tile it is given — unlike `ExtensionIconView`'s fixed icon box.
private struct ExtensionGridContentView: View {
    @Environment(\.isDarkAppearance) private var isDark
    let resolved: ExtensionImage.Resolved?
    let fills: Bool
    /// Passed down rather than measured: the grid already knows every tile's size.
    let size: CGSize
    @State private var loaded: NSImage?

    var body: some View {
        content
            // Keyed on appearance too: an inline SVG's palette resolves at decode.
            .task(id: ExtensionImage.LoadKey(source: resolved?.source, isDark: isDark)) {
                loaded = await ExtensionImage.load(resolved, isDark: isDark, animates: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch resolved?.source {
        case .symbol(let name):
            // A symbol has no artwork to scale, so it takes a share of the tile rather than all of it.
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(resolved?.tint == nil ? .hierarchical : .monochrome)
                .foregroundStyle(resolved?.tint ?? Theme.Colors.textSecondary)
                .padding(min(size.width, size.height) * 0.2)
        case .glyph(let text):
            Text(text)
                .font(.system(size: min(size.width, size.height) * 0.72))
        case .file, .fileIcon, .remote, .inline:
            if let loaded {
                image(loaded)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    /// The tile is clipped already, so the faint fill needs no corner of its own.
    private var placeholder: some View { Rectangle().fill(Theme.Colors.iconPlaceholder) }

    @ViewBuilder
    private func image(_ image: NSImage) -> some View {
        // Only a multi-frame image pays for `NSImageView`; a still stays on SwiftUI's path.
        if image.isAnimated {
            AnimatedImageView(image: image)
                .scaleEffect(fills ? coverScale(image) : 1)
        } else {
            // A `tintColor` masks the artwork, which is what colours a `currentColor` SVG.
            Image(nsImage: image)
                .resizable()
                .renderingMode(resolved?.tint == nil ? .original : .template)
                .aspectRatio(contentMode: fills ? .fill : .fit)
                .foregroundStyle(resolved?.tint ?? .primary)
        }
    }

    /// `NSImageView` only ever fits proportionally, so `Grid.Fit.Fill` scales that draw up to cover.
    private func coverScale(_ image: NSImage) -> Double {
        let scales = [size.width / image.size.width, size.height / image.size.height]
        guard let low = scales.min(), let high = scales.max(), low > 0, high.isFinite else { return 1 }
        return high / low
    }
}
