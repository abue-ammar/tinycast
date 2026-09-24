import SwiftUI

/// The `Detail` screen, and the pane a `List` shows when `isShowingDetail` is on.
struct ExtensionDetailBody: View {
    @Environment(\.metrics) private var metrics
    let markdown: String?
    let metadata: RenderNode?
    let isLoading: Bool
    let assetsPath: String?
    /// A list's detail pane is too narrow for a metadata sidebar.
    var stacksMetadata = false

    private static let stackedInset: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            markdownPane(trailing: stacksMetadata ? metadata : nil)
            if !stacksMetadata, let metadata {
                Rectangle().fill(Theme.Colors.separator).frame(width: 1)
                metadataPane(metadata)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func markdownPane(trailing metadata: RenderNode?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                if isLoading && (markdown ?? "").isEmpty {
                    Text("Loading…").foregroundStyle(.secondary)
                }
                if let markdown, !markdown.isEmpty {
                    ExtensionMarkdownView(markdown: markdown)
                }
                if let metadata {
                    ExtensionMetadataView(metadata: metadata, assetsPath: assetsPath, inline: true)
                        .padding(.top, (markdown ?? "").isEmpty ? 0 : metrics.spacing.xxl)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(
                .horizontal, stacksMetadata ? metrics.scaled(Self.stackedInset) : metrics.spacing.lg
            )
            .padding(.vertical, metrics.spacing.md)
            .hideNativeScrollers()
        }
        .frame(maxWidth: .infinity)
        .edgeDissolve()
        .thinScrollbar()
    }

    /// A `Detail.Metadata` sidebar's fixed width; the markdown pane takes what's left.
    private static let metadataWidth: CGFloat = 240

    private func metadataPane(_ metadata: RenderNode) -> some View {
        ScrollView {
            ExtensionMetadataView(metadata: metadata, assetsPath: assetsPath)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
        }
        .frame(width: metrics.scaled(Self.metadataWidth))
        .edgeDissolve()
        .thinScrollbar()
    }
}

/// `Detail.Metadata` — label / link / tag-list / separator rows.
struct ExtensionMetadataView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let metadata: RenderNode
    let assetsPath: String?
    var inline = false

    private static let inlineRowHeight: CGFloat = 28

    /// Stripes must count only real rows, so separators are dropped here.
    private var visibleChildren: [RenderNode] {
        inline
            ? metadata.children.filter { $0.type != "Detail.Metadata.Separator" }
            : metadata.children
    }

    var body: some View {
        VStack(alignment: .leading, spacing: inline ? 0 : metrics.spacing.lg) {
            ForEach(Array(visibleChildren.enumerated()), id: \.element.id) { index, child in
                switch child.type {
                case "Detail.Metadata.Label":
                    row(title: child.string("title"), index: index) {
                        HStack(spacing: metrics.spacing.xs) {
                            if let icon = child.props["icon"] {
                                ExtensionIconView(
                                    resolved: ExtensionImage.resolve(
                                        icon, assetsPath: assetsPath, isDark: isDark),
                                    size: 14)
                            }
                            Text(labelText(child))
                                .font(metrics.typography.rowTitle)
                                .textSelection(.enabled)
                        }
                    }
                case "Detail.Metadata.Link":
                    row(title: child.string("title"), index: index) {
                        if let target = child.string("target"), let url = URL(string: target) {
                            Link(child.string("text") ?? target, destination: url)
                                .font(metrics.typography.rowTitle)
                        } else {
                            Text(child.string("text") ?? "").font(metrics.typography.rowTitle)
                        }
                    }
                case "Detail.Metadata.TagList":
                    row(title: child.string("title"), index: index) {
                        ExtensionTagListView(tags: child.children, assetsPath: assetsPath)
                    }
                case "Detail.Metadata.Separator":
                    Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                default:
                    EmptyView()
                }
            }
        }
    }

    /// `text` is a string or `{value, color}`; a Label can also carry only an icon.
    private func labelText(_ node: RenderNode) -> String {
        ExtensionAccessoriesView.label(node.props["text"])
            ?? node.date("text").map { $0.formatted(date: .abbreviated, time: .shortened) }
            ?? ""
    }

    @ViewBuilder
    private func row<Content: View>(
        title: String?, index: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        if inline {
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.xl) {
                Text(title ?? "")
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                content()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.xs)
            .frame(minHeight: metrics.scaled(Self.inlineRowHeight))
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                    .fill(index.isMultiple(of: 2) ? ExtensionColors.detailCardFill : .clear))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(metrics.typography.sectionHeader)
                        .foregroundStyle(.secondary)
                }
                content()
            }
        }
    }
}

private struct ExtensionTagListView: View {

    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let tags: [RenderNode]
    let assetsPath: String?

    var body: some View {
        // Wrapping matters here: a metadata tag list is frequently longer than the pane is wide.
        FlowLayout(spacing: metrics.spacing.xs) {
            ForEach(tags) { tag in
                let color =
                    ExtensionImage.color(tag.props["color"], isDark: isDark) ?? Theme.Colors.textSecondary
                HStack(spacing: 3) {
                    if let icon = tag.props["icon"] {
                        ExtensionIconView(
                            resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark),
                            size: 12)
                    }
                    Text(tag.string("text") ?? "")
                        .font(metrics.typography.rowTrailing)
                }
                .foregroundStyle(color)
                .padding(.horizontal, metrics.spacing.xs)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.16))
                )
            }
        }
    }
}

/// Left-to-right wrapping row. SwiftUI has no built-in wrap, and tag lists need one.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total = CGSize(width: 0, height: 0)
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > width {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Inline styling comes from `AttributedString`; block structure is laid out here.
struct ExtensionMarkdownView: View {
    @Environment(\.metrics) private var metrics
    let markdown: String

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(index: Int, text: String)
        case quote(String)
        case code(String)
        case rule
        case image(URL)
        case table([[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            // Positional, so a live image keeps its last frame while the next one decodes.
            ForEach(Array(Self.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(inline(text))
                        .font(.system(size: headingSize(level), weight: .semibold))
                        .padding(.top, metrics.spacing.xs)
                case .paragraph(let text):
                    Text(inline(text))
                        .font(metrics.typography.rowTitle)
                        .textSelection(.enabled)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: metrics.spacing.sm) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text)).font(metrics.typography.rowTitle)
                    }
                case .numbered(let index, let text):
                    HStack(alignment: .top, spacing: metrics.spacing.sm) {
                        Text("\(index).").foregroundStyle(.secondary).monospacedDigit()
                        Text(inline(text)).font(metrics.typography.rowTitle)
                    }
                case .quote(let text):
                    HStack(spacing: metrics.spacing.sm) {
                        Rectangle().fill(Theme.Colors.separator).frame(width: 2)
                        Text(inline(text))
                            .font(metrics.typography.rowTitle)
                            .foregroundStyle(.secondary)
                    }
                case .code(let text):
                    ScrollView(.horizontal) {
                        Text(text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(metrics.spacing.sm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(ExtensionColors.detailCardFill)
                    )
                    .hideNativeScrollers()
                case .rule:
                    Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                case .image(let url):
                    ExtensionMarkdownImage(url: url)
                case .table(let rows):
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(rows.indices, id: \.self) { r in
                            GridRow {
                                ForEach(rows[r].indices, id: \.self) { c in
                                    Text(inline(rows[r][c])).fontWeight(r == 0 ? .semibold : nil)
                                        .padding(.vertical, metrics.spacing.lg)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(r == 0 ? ExtensionColors.detailCardFill : .clear)
                                        .border(Theme.Colors.separator, width: 0.5)
                                }
                            }
                        }
                    }
                    .font(metrics.typography.rowTitle).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 17
        case 3: return 15
        default: return 14
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var fence: [String]?
        var numberedIndex = 0
        var table: [[String]] = []

        func flushParagraph() {
            if !table.isEmpty { blocks.append(.table(table)); table.removeAll() }
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in source.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false)
        {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let body = fence {
                    blocks.append(.code(body.joined(separator: "\n")))
                    fence = nil
                } else {
                    flushParagraph()
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence?.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                numberedIndex = 0
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if trimmed.hasPrefix("|") {
                if !paragraph.isEmpty { flushParagraph() }
                let row = trimmed.replacingOccurrences(
                    of: #"(?<!\\)((?:\\\\)*)\\\|"#, with: "$1\u{0}", options: .regularExpression)
                let cells = row.split(separator: "|", omittingEmptySubsequences: false).dropFirst()
                    .dropLast(row.hasSuffix("|") ? 1 : 0)
                    .map {
                        $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{0}", with: "|")
                    }
                if cells.allSatisfy({ $0.contains("-") && $0.allSatisfy(":-".contains) }) { continue }
                table.append(cells)
                continue
            }
            // A standalone image is the one block AttributedString can't show inline.
            if let url = standaloneImageURL(trimmed) {
                flushParagraph()
                blocks.append(.image(url))
                continue
            }
            if trimmed.hasPrefix("#") {
                flushParagraph()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: min(level, 4), text: text))
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }
            if let match = trimmed.firstMatch(ofNumberedList: ()) {
                flushParagraph()
                numberedIndex += 1
                blocks.append(.numbered(index: numberedIndex, text: match))
                continue
            }
            paragraph.append(trimmed)
        }
        if let body = fence { blocks.append(.code(body.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    private static func standaloneImageURL(_ line: String) -> URL? {
        guard line.hasPrefix("!["), let open = line.lastIndex(of: "("), line.hasSuffix(")") else {
            return nil
        }
        let inner = line[line.index(after: open)..<line.index(before: line.endIndex)]
        let target = inner.split(separator: " ").first.map(String.init) ?? String(inner)
        guard let url = URL(string: target), let scheme = url.scheme,
            scheme.hasPrefix("http") || scheme == "data"
        else { return nil }
        return url
    }
}

extension String {
    /// `1. text` → `text`, for ordered-list detection.
    fileprivate func firstMatch(ofNumberedList: Void) -> String? {
        let digits = prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}

/// An image inside a Detail's markdown, at its own size or the one its URL asks for.
private struct ExtensionMarkdownImage: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Group {
                    if image.isAnimated {
                        AnimatedImageView(image: image)
                    } else {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    }
                }
                .frame(maxWidth: maxWidth ?? (size == nil ? image.size.width : .infinity), maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous))
                .frame(maxWidth: .infinity)
            } else {
                RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                    .fill(ExtensionColors.detailCardFill)
                    .frame(height: 120)
            }
        }
        // Keyed on the appearance too: an inline SVG's palette resolves at decode, not in the URL.
        .task(id: ExtensionImage.LoadKey(source: source, isDark: isDark)) {
            // A slow remote load must not show the previous row's image meanwhile.
            if url.scheme != "data" { image = nil }
            let loaded =
                url.scheme == "data"
                ? await ExtensionIconCache.loadInlineAsync(
                    url, palette: ExtensionImage.svgPalette(isDark: isDark))
                : await ExtensionIconCache.loadRemoteAsync(url, asIcon: false)
            if !Task.isCancelled { image = loaded }
        }
    }

    private var source: ExtensionImage.Source {
        url.scheme == "data" ? .inline(url) : .remote(url)
    }

    private var size: ExtensionImageSize? { ExtensionImageSize(url: url) }

    private var maxWidth: CGFloat? { size?.width.map { CGFloat($0) } }

    private var maxHeight: CGFloat { size?.height.map { CGFloat($0) } ?? .infinity }
}
