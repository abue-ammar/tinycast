import AppKit
import SwiftUI

/// Everything the text is drawn from; the view re-renders only when one of these changes.
struct ChatMarkdownSource: Equatable {
    let blocks: [MarkdownBlock]
    let highlight: ChatTextHighlight?
    let citations: [String: Int]
    let prefix: [Int]
    let failed: Bool
    let metrics: InterfaceMetrics
}

/// What the renderer made: the text, where each code block sits, and the current find match.
struct ChatRenderedText {
    let string: NSAttributedString
    let codeBlocks: [CodeBlock]
    let current: NSRange?

    struct CodeBlock {
        let block: NSTextBlock
        let range: NSRange
        let code: String
        let language: String?
    }
}

/// Markdown into one attributed string; each text takes `ChatFindIndex.leaves`' path for find.
@MainActor
struct ChatMarkdownRenderer {
    /// The strip a code block leaves above its code for the language and the Copy button.
    static let codeHeaderHeight: CGFloat = 16
    /// Marks the current match while the string is built; citations inserted later move it.
    private static let currentMatch = NSAttributedString.Key("TinycastChatFindCurrent")

    private let source: ChatMarkdownSource
    private var typography: InterfaceMetrics.Typography { source.metrics.typography }
    private var spacing: InterfaceMetrics.Spacing { source.metrics.spacing }

    init(_ source: ChatMarkdownSource) {
        self.source = source
    }

    private final class Output {
        let string = NSMutableAttributedString()
        var codeBlocks: [ChatRenderedText.CodeBlock] = []
    }

    /// Where a block sits: the text blocks around it (quote, code, cell) and a list's indent.
    private struct Context {
        var textBlocks: [NSTextBlock] = []
        var indent: CGFloat = 0
        var secondary = false
    }

    func render() -> ChatRenderedText {
        let output = Output()
        render(source.blocks, at: source.prefix, in: Context(), into: output)
        // The last paragraph's own break would draw an empty line under the reply.
        if output.string.string.hasSuffix("\n") {
            output.string.deleteCharacters(in: NSRange(location: output.string.length - 1, length: 1))
        }
        var current: NSRange?
        output.string.enumerateAttribute(
            Self.currentMatch, in: NSRange(location: 0, length: output.string.length)
        ) { value, range, stop in
            guard value != nil else { return }
            current = range
            stop.pointee = true
        }
        return ChatRenderedText(string: output.string, codeBlocks: output.codeBlocks, current: current)
    }

    private var bodyFont: NSFont { typography.textNSFont(.body) }

    private func textColor(_ context: Context) -> NSColor {
        if source.failed { return NSColor(Theme.Colors.destructive) }
        return context.secondary ? NSColor(Theme.Colors.textSecondary) : .labelColor
    }

    /// `first` numbers the blocks when a list item renders its later blocks one at a time.
    private func render(
        _ blocks: [MarkdownBlock], at path: [Int], in context: Context, into output: Output,
        first: Int = 0, spacingAfter: CGFloat? = nil
    ) {
        for (offset, block) in blocks.enumerated() {
            let position = first + offset
            let leaf = path + [position]
            let after = spacingAfter ?? spacing.lg
            switch block {
            case .heading(let level, let text):
                inline(text, font: headingFont(level), leaf: leaf, in: context, into: output) { style in
                    style.paragraphSpacingBefore = position > 0 ? spacing.sm : 0
                    style.paragraphSpacing = after
                }
            case .paragraph(let text):
                inline(text, font: bodyFont, leaf: leaf, in: context, into: output) { style in
                    style.paragraphSpacing = after
                }
            case .bulletList(let items):
                list(items, start: nil, at: leaf, in: context, into: output, after: after)
            case .numberedList(let start, let items):
                list(items, start: start, at: leaf, in: context, into: output, after: after)
            case .code(let language, let text):
                code(language: language, text: text, leaf: leaf, in: context, into: output, after: after)
            case .quote(let inner):
                let bar = Self.fullWidthBlock()
                bar.setWidth(Theme.Size.markdownQuoteBar, type: .absoluteValueType, for: .border, edge: .minX)
                bar.setBorderColor(NSColor(Theme.Colors.border), for: .minX)
                bar.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .minX)
                bar.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
                bar.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
                var inside = context
                inside.textBlocks.append(bar)
                inside.indent = 0
                inside.secondary = true
                render(inner, at: leaf, in: inside, into: output, spacingAfter: spacing.sm)
            case .table(let table):
                self.table(table, at: leaf, in: context, into: output, after: after)
            case .rule:
                let line = Self.fullWidthBlock()
                line.setWidth(Theme.Size.hairline, type: .absoluteValueType, for: .border, edge: .maxY)
                line.setBorderColor(NSColor(Theme.Colors.separator), for: .maxY)
                line.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
                line.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
                output.string.append(
                    NSAttributedString(
                        string: "\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 1),
                            .paragraphStyle: paragraphStyle(in: context, extra: [line])
                        ]))
            }
        }
    }

    /// A block with no width lays out without its box: no fill, no border, no bounds.
    private static func fullWidthBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        return block
    }

    private func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: typography.textNSFont(.title2, weight: .semibold)
        case 2: typography.textNSFont(.title3, weight: .semibold)
        default: typography.textNSFont(.headline)
        }
    }

    private func paragraphStyle(in context: Context, extra: [NSTextBlock] = []) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing.chatLine
        style.textBlocks = context.textBlocks + extra
        style.firstLineHeadIndent = context.indent
        style.headIndent = context.indent
        return style
    }

    /// One drawn text, as one paragraph: its inline Markdown, find's marks, then citations.
    private func inline(
        _ text: String, font: NSFont, leaf: [Int], in context: Context, into output: Output,
        marker: String? = nil, extraBlocks: [NSTextBlock] = [], alignment: NSTextAlignment = .natural,
        style configure: (NSMutableParagraphStyle) -> Void = { _ in }
    ) {
        let parsed = MarkdownBlock.inline(text)
        let drawn = attributed(parsed, font: font, color: textColor(context))
        mark(drawn, leaf: leaf)
        insertCitations(into: drawn, from: parsed)
        let style = paragraphStyle(in: context, extra: extraBlocks)
        style.alignment = alignment
        configure(style)
        let line = NSMutableAttributedString()
        if let marker {
            line.append(
                NSAttributedString(
                    string: marker,
                    attributes: [.font: bodyFont, .foregroundColor: NSColor(Theme.Colors.textSecondary)]))
        }
        line.append(drawn)
        line.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        output.string.append(line)
    }

    /// Emphasis, strong, code, strikethrough and links, from Foundation's inline parse.
    private func attributed(
        _ parsed: AttributedString, font: NSFont, color: NSColor
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
                }
                if intent.contains(.emphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
                }
                if intent.contains(.code) {
                    runFont = typography.textNSFont(.body, monospaced: true)
                    attributes[.backgroundColor] = NSColor(Theme.Colors.controlSurface)
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link { attributes[.link] = link }
            attributes[.font] = runFont
            result.append(
                NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }

    /// Every match takes the find tint; the current one the solid mark, and the tag found later.
    private func mark(_ text: NSMutableAttributedString, leaf: [Int]) {
        guard let highlight = source.highlight else { return }
        let plain = text.string
        for (index, range) in ChatFindIndex.ranges(of: highlight.query, in: plain).enumerated() {
            let span = NSRange(range, in: plain)
            let isCurrent = highlight.current?.leaf == leaf && highlight.current?.index == index
            let tint = isCurrent ? Theme.Colors.findCurrent : Theme.Colors.findMatch
            text.addAttribute(.backgroundColor, value: NSColor(tint), range: span)
            guard isCurrent else { continue }
            text.addAttribute(.foregroundColor, value: NSColor(Theme.Colors.findCurrentInk), range: span)
            text.addAttribute(Self.currentMatch, value: true, range: span)
        }
    }

    /// After find, whose matches count the text as the reply wrote it, without the numbers.
    private func insertCitations(into text: NSMutableAttributedString, from parsed: AttributedString) {
        let plain = String(parsed.characters)
        for anchor in ChatCitations.anchors(in: parsed, numbers: source.citations).reversed() {
            let index = plain.index(plain.startIndex, offsetBy: anchor.offset)
            let marker = NSAttributedString(
                string: "[\(anchor.number)]",
                attributes: [
                    .font: typography.textNSFont(.caption1), .baselineOffset: spacing.xs,
                    .link: anchor.url
                ])
            text.insert(marker, at: NSRange(index..<index, in: plain).location)
        }
    }

    private func list(
        _ items: [MarkdownBlock.Item], start: Int?, at path: [Int], in context: Context,
        into output: Output, after: CGFloat
    ) {
        // Wide enough for the list's longest number, so every item's text starts on one line.
        let digits = start.map { String($0 + max(items.count - 1, 0)).count + 1 } ?? 1
        let width = ceil(bodyFont.pointSize * 0.62 * CGFloat(digits)) + spacing.md
        for (offset, item) in items.enumerated() {
            var inside = context
            inside.indent = context.indent + width
            let marker: String
            if let checked = item.checked {
                marker = checked ? "☑" : "☐"
            } else if let start {
                marker = "\(start + offset)."
            } else {
                marker = "•"
            }
            let itemPath = path + [offset]
            for (index, block) in item.blocks.enumerated() {
                let isEnd = offset == items.count - 1 && index == item.blocks.count - 1
                let blockAfter = isEnd ? after : spacing.xs
                guard index == 0, case .paragraph(let text) = block else {
                    render(
                        [block], at: itemPath, in: inside, into: output, first: index,
                        spacingAfter: blockAfter)
                    continue
                }
                inline(
                    text, font: bodyFont, leaf: itemPath + [0], in: inside, into: output,
                    marker: "\(marker)\t"
                ) { style in
                    style.firstLineHeadIndent = context.indent
                    style.tabStops = [NSTextTab(textAlignment: .natural, location: inside.indent)]
                    style.paragraphSpacing = blockAfter
                }
            }
        }
    }

    private func code(
        language: String?, text: String, leaf: [Int], in context: Context, into output: Output,
        after: CGFloat
    ) {
        let box = Self.fullWidthBlock()
        box.backgroundColor = NSColor(Theme.Colors.cardFill)
        box.setBorderColor(NSColor(Theme.Colors.cardStroke))
        box.setWidth(Theme.Size.hairline, type: .absoluteValueType, for: .border)
        box.setWidth(spacing.xl, type: .absoluteValueType, for: .padding, edge: .minX)
        box.setWidth(spacing.xl, type: .absoluteValueType, for: .padding, edge: .maxX)
        // The header strip above the code holds the language and the Copy button.
        box.setWidth(
            spacing.md + Self.codeHeaderHeight + spacing.sm, type: .absoluteValueType, for: .padding,
            edge: .minY)
        box.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .maxY)
        box.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        let font = typography.textNSFont(.callout, monospaced: true)
        let style = paragraphStyle(in: context, extra: [box])
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        let body = NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: textColor(context)])
        mark(body, leaf: leaf)
        let start = output.string.length
        body.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        body.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: body.length))
        output.string.append(body)
        output.codeBlocks.append(
            ChatRenderedText.CodeBlock(
                block: box, range: NSRange(location: start, length: body.length), code: text,
                language: language))
        spacer(after, in: context, into: output)
    }

    /// A block's bottom margin is painted with its fill, so the gap under a code block is a line.
    private func spacer(_ height: CGFloat, in context: Context, into output: Output) {
        let style = paragraphStyle(in: context)
        style.lineSpacing = 0
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        output.string.append(
            NSAttributedString(
                string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: style]))
    }

    private func table(
        _ table: MarkdownBlock.Table, at path: [Int], in context: Context, into output: Output,
        after: CGFloat
    ) {
        let grid = NSTextTable()
        grid.numberOfColumns = max(table.header.count, 1)
        grid.layoutAlgorithm = .automaticLayoutAlgorithm
        grid.collapsesBorders = true
        grid.hidesEmptyCells = false
        grid.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        grid.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
        let rows = [table.header] + table.rows
        for (row, cells) in rows.enumerated() {
            for column in 0..<grid.numberOfColumns {
                let cell = NSTextTableBlock(
                    table: grid, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(spacing.sm, type: .absoluteValueType, for: .padding)
                cell.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .maxX)
                if row > 0 {
                    cell.setWidth(Theme.Size.hairline, type: .absoluteValueType, for: .border, edge: .minY)
                    cell.setBorderColor(NSColor(Theme.Colors.cardStroke), for: .minY)
                }
                if row == 0 { cell.backgroundColor = NSColor(Theme.Colors.cardFill) }
                var inside = context
                inside.secondary = context.secondary || row == 0
                inside.indent = 0
                inline(
                    column < cells.count ? cells[column] : "",
                    font: row == 0 ? typography.textNSFont(.subheadline, weight: .medium) : bodyFont,
                    leaf: path + [row, column], in: inside, into: output, extraBlocks: [cell],
                    alignment: alignment(table, column))
            }
        }
    }

    private func alignment(_ table: MarkdownBlock.Table, _ column: Int) -> NSTextAlignment {
        guard column < table.alignments.count else { return .natural }
        switch table.alignments[column] {
        case .leading: return .natural
        case .center: return .center
        case .trailing: return .right
        }
    }
}
