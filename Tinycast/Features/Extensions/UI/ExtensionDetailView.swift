import SwiftUI

/// The `Detail` screen, and the detail pane a `List` shows beside its rows when `isShowingDetail` is on.
struct ExtensionDetailBody: View {
    let markdown: String?
    let metadata: RenderNode?
    let isLoading: Bool
    let assetsPath: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if isLoading && (markdown ?? "").isEmpty {
                    Text("Loading…").foregroundStyle(.secondary)
                }
                if let markdown, !markdown.isEmpty {
                    ExtensionMarkdownView(markdown: markdown)
                }
                if let metadata {
                    if markdown?.isEmpty == false {
                        Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                    }
                    ExtensionMetadataView(metadata: metadata, assetsPath: assetsPath)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
    }
}

/// `Detail.Metadata` — label / link / tag-list / separator rows.
struct ExtensionMetadataView: View {
    let metadata: RenderNode
    let assetsPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(metadata.children) { child in
                switch child.type {
                case "Detail.Metadata.Label":
                    row(title: child.string("title")) {
                        HStack(spacing: Theme.Spacing.xs) {
                            if let icon = child.props["icon"] {
                                ExtensionIconView(
                                    resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath),
                                    size: 14)
                            }
                            Text(labelText(child))
                                .font(Theme.Typography.rowTitle)
                                .textSelection(.enabled)
                        }
                    }
                case "Detail.Metadata.Link":
                    row(title: child.string("title")) {
                        if let target = child.string("target"), let url = URL(string: target) {
                            Link(child.string("text") ?? target, destination: url)
                                .font(Theme.Typography.rowTitle)
                        } else {
                            Text(child.string("text") ?? "").font(Theme.Typography.rowTitle)
                        }
                    }
                case "Detail.Metadata.TagList":
                    row(title: child.string("title")) {
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
    private func row<Content: View>(title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }
}

private struct ExtensionTagListView: View {
    let tags: [RenderNode]
    let assetsPath: String?

    var body: some View {
        // Wrapping matters here: a metadata tag list is frequently longer than the pane is wide.
        FlowLayout(spacing: Theme.Spacing.xs) {
            ForEach(tags) { tag in
                let color = ExtensionImage.color(tag.props["color"]) ?? Theme.Colors.textSecondary
                HStack(spacing: 3) {
                    if let icon = tag.props["icon"] {
                        ExtensionIconView(
                            resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath), size: 12)
                    }
                    Text(tag.string("text") ?? "")
                        .font(Theme.Typography.rowTrailing)
                }
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Spacing.xs)
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

/// Renders an extension's markdown. `AttributedString`'s markdown parser handles inline styling; block
/// structure (headings, lists, code fences, rules) is laid out here so a Detail reads like a document
/// rather than one run-on paragraph.
struct ExtensionMarkdownView: View {
    let markdown: String

    private enum Block: Identifiable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(index: Int, text: String)
        case quote(String)
        case code(String)
        case rule
        case image(URL)

        var id: String {
            switch self {
            case .heading(let level, let text): return "h\(level):\(text)"
            case .paragraph(let text): return "p:\(text)"
            case .bullet(let text): return "b:\(text)"
            case .numbered(let index, let text): return "n\(index):\(text)"
            case .quote(let text): return "q:\(text)"
            case .code(let text): return "c:\(text)"
            case .rule: return "rule:\(UUID().uuidString)"
            case .image(let url): return "img:\(url.absoluteString)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Self.parse(markdown)) { block in
                switch block {
                case .heading(let level, let text):
                    Text(inline(text))
                        .font(.system(size: headingSize(level), weight: .semibold))
                        .padding(.top, Theme.Spacing.xs)
                case .paragraph(let text):
                    Text(inline(text))
                        .font(Theme.Typography.rowTitle)
                        .textSelection(.enabled)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text)).font(Theme.Typography.rowTitle)
                    }
                case .numbered(let index, let text):
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Text("\(index).").foregroundStyle(.secondary).monospacedDigit()
                        Text(inline(text)).font(Theme.Typography.rowTitle)
                    }
                case .quote(let text):
                    HStack(spacing: Theme.Spacing.sm) {
                        Rectangle().fill(Theme.Colors.separator).frame(width: 2)
                        Text(inline(text))
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(.secondary)
                    }
                case .code(let text):
                    ScrollView(.horizontal) {
                        Text(text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(Theme.Spacing.sm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .hideNativeScrollers()
                case .rule:
                    Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                case .image(let url):
                    ExtensionMarkdownImage(url: url)
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

        func flushParagraph() {
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
        guard let url = URL(string: target), url.scheme?.hasPrefix("http") == true else { return nil }
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

/// A remote image inside a Detail's markdown, capped so a large asset can't push the layout around.
private struct ExtensionMarkdownImage: View {
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
                .frame(maxWidth: .infinity, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 120)
            }
        }
        .task(id: url) { image = await ExtensionIconCache.loadRemoteAsync(url, asIcon: false) }
    }
}
