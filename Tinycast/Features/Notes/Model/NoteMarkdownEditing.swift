import Foundation

/// Plans Markdown-aware edits as pure replacements, so every gesture is testable without AppKit.
enum NoteMarkdownEditing {
    /// Nil means "not mine": the caller falls through to AppKit's native behaviour.
    static func plan(
        _ action: NoteEditAction, source: String, selection: NSRange, markdown: NoteMarkdown
    ) -> NoteEditPlan? {
        let text = source as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= text.length else { return nil }
        let document = Document(text: text, markdown: markdown)
        switch action {
        case .newline: return document.newline(at: selection)
        case .deleteBackward: return document.deleteBackward(at: selection)
        case .indent: return document.indent(selection)
        case .outdent: return document.outdent(selection)
        case .toggleInline(let style): return document.toggleInline(style, in: selection)
        case .toggleLink: return document.toggleLink(in: selection)
        case .setHeading(let level): return document.setHeading(level, in: selection)
        case .toggleList(let style): return document.toggleList(style, in: selection)
        case .toggleCodeBlock: return document.toggleCodeBlock(in: selection)
        case .toggleQuote: return document.toggleQuote(in: selection)
        case .toggleTask(let lineIndex): return document.toggleTask(lineIndex, keeping: selection)
        case .typedSpace: return document.typedSpace(at: selection)
        case .pasteURL(let string): return document.pasteURL(string, over: selection)
        }
    }

    /// Decided by the same span and line rules the toggles use, so a lit button always undoes.
    static func formatting(source: String, selection: NSRange, markdown: NoteMarkdown) -> NoteFormatting {
        let text = source as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= text.length else { return .plain }
        return Document(text: text, markdown: markdown).formatting(of: selection)
    }

    fileprivate typealias Line = NoteMarkdown.Line
    fileprivate typealias Unit = NoteMarkdownParser.Unit

    fileprivate struct Edit {
        let range: NSRange
        let replacement: String
    }

    fileprivate struct Document {
        let text: NSString
        let markdown: NoteMarkdown

        private static let maximumLevel = 6
        private static let indentUnit = "    "

        // MARK: - Lists and quotes

        func newline(at selection: NSRange) -> NoteEditPlan? {
            guard selection.length == 0, let index = realLine(at: selection.location) else { return nil }
            let line = markdown.lines[index]
            let caret = selection.location
            guard let marker = line.markerRange, caret >= line.contentRange.location else { return nil }
            let isEmptyItem = text.substring(with: line.contentRange).allSatisfy(\.isWhitespace)
            switch line.kind {
            case .bullet, .ordered, .task:
                if isEmptyItem {
                    guard line.level == 0 else { return outdent(NSRange(location: caret, length: 0)) }
                    return renumbered(removing: marker, caret: line.range.location)
                }
                let lineStart = line.range.location
                let continuation =
                    "\n" + text.substring(with: NSRange(lineStart..<indentEnd(of: line)))
                    + nextMarker(after: line)
                return renumbered(inserting: continuation, at: caret)
            case .quote:
                if isEmptyItem {
                    return NoteEditPlan(
                        range: marker, replacement: "",
                        selection: NSRange(location: line.range.location, length: 0))
                }
                return inserting("\n" + text.substring(with: marker), at: caret)
            default:
                return nil
            }
        }

        func deleteBackward(at selection: NSRange) -> NoteEditPlan? {
            guard selection.length == 0, let index = realLine(at: selection.location) else { return nil }
            let line = markdown.lines[index]
            guard let marker = line.markerRange, selection.location == line.contentRange.location,
                selection.location > line.range.location
            else { return nil }
            switch line.kind {
            case .bullet, .ordered, .task:
                guard line.level == 0 else { return outdent(selection) }
                return renumbered(removing: marker, caret: line.range.location)
            case .quote:
                return NoteEditPlan(
                    range: marker, replacement: "",
                    selection: NSRange(location: line.range.location, length: 0))
            default:
                return nil
            }
        }

        func indent(_ selection: NSRange) -> NoteEditPlan? {
            let indexes = markdown.lineIndexes(intersecting: selection)
            guard let first = indexes.first, allListLines(indexes) else { return nil }
            guard indexes.allSatisfy({ markdown.lines[$0].level < Self.maximumLevel }) else { return nil }
            guard let parent = previousListLine(before: first),
                markdown.lines[first].level <= parent.level
            else { return nil }
            let edits = indexes.map {
                Edit(
                    range: NSRange(location: markdown.lines[$0].range.location, length: 0),
                    replacement: Self.indentUnit)
            }
            return renumbered(plan(edits, selection: selection))
        }

        func outdent(_ selection: NSRange) -> NoteEditPlan? {
            let indexes = markdown.lineIndexes(intersecting: selection)
            guard !indexes.isEmpty, allListLines(indexes) else { return nil }
            let edits = indexes.compactMap { index -> Edit? in
                let start = markdown.lines[index].range.location
                let end = indentEnd(of: markdown.lines[index])
                guard end > start else { return nil }
                let isTab = text.character(at: start) == Unit.tab
                let spaces = (start..<end).prefix { text.character(at: $0) == Unit.space }.count
                let length = isTab ? 1 : min(spaces, Self.indentUnit.utf16.count)
                guard length > 0 else { return nil }
                return Edit(range: NSRange(location: start, length: length), replacement: "")
            }
            return renumbered(plan(edits, selection: selection))
        }

        func toggleList(_ style: NoteEditAction.ListStyle, in selection: NSRange) -> NoteEditPlan? {
            let indexes = touchedLines(selection)
            var edits: [Edit] = []
            var handled = false
            for index in indexes {
                let line = self.line(index)
                let start = indentEnd(of: line)
                switch line.kind {
                case .blank where indexes.count > 1:
                    continue
                case .blank, .paragraph:
                    handled = true
                    edits.append(
                        Edit(
                            range: NSRange(location: start, length: 0),
                            replacement: Self.marker(for: style, bullet: "-")))
                case .bullet, .ordered, .task:
                    handled = true
                    let markerRange = NSRange(start..<line.contentRange.location)
                    let current = Self.style(of: line.kind)
                    let bullet =
                        current == .ordered ? "-" : text.substring(with: NSRange(location: start, length: 1))
                    let replacement =
                        current == style ? "" : Self.marker(for: style, bullet: bullet)
                    edits.append(Edit(range: markerRange, replacement: replacement))
                default:
                    continue
                }
            }
            guard handled else { return nil }
            return renumbered(plan(edits, selection: selection))
        }

        func toggleTask(_ lineIndex: Int, keeping selection: NSRange) -> NoteEditPlan? {
            guard markdown.lines.indices.contains(lineIndex) else { return nil }
            let line = markdown.lines[lineIndex]
            guard case .task(let checked) = line.kind, let box = line.checkboxRange else { return nil }
            return NoteEditPlan(
                range: NSRange(location: box.location + 1, length: 1),
                replacement: checked ? " " : "x", selection: selection)
        }

        func typedSpace(at selection: NSRange) -> NoteEditPlan? {
            guard selection.length == 0, let index = realLine(at: selection.location) else { return nil }
            let line = markdown.lines[index]
            guard line.kind == .paragraph else { return nil }
            let start = indentEnd(of: line)
            let typed = selection.location - start
            guard typed == 2 || typed == 3 else { return nil }
            let prefix = NSRange(start..<selection.location)
            guard ["[]", "[ ]"].contains(text.substring(with: prefix)) else { return nil }
            let task = "- [ ] "
            return NoteEditPlan(
                range: prefix, replacement: task,
                selection: NSRange(location: start + task.utf16.count, length: 0))
        }

        // MARK: - Headings, inline styles, links

        func setHeading(_ level: Int, in selection: NSRange) -> NoteEditPlan? {
            var edits: [Edit] = []
            var handled = false
            for index in touchedLines(selection) {
                let line = self.line(index)
                switch line.kind {
                case .heading(let current):
                    handled = true
                    guard let marker = line.markerRange else { continue }
                    edits.append(
                        Edit(range: marker, replacement: Self.headingMarker(current == level ? 0 : level)))
                case .paragraph:
                    handled = true
                    guard level > 0 else { continue }
                    let indentation = NSRange(line.range.location..<indentEnd(of: line))
                    edits.append(Edit(range: indentation, replacement: Self.headingMarker(level)))
                default:
                    continue
                }
            }
            guard handled else { return nil }
            return plan(edits, selection: selection)
        }

        func toggleInline(_ style: NoteEditAction.InlineStyle, in selection: NSRange) -> NoteEditPlan? {
            guard case let (line, range)? = styledLine(for: selection) else { return nil }
            guard range.length > 0 else {
                if let span = removableSpan(style, at: range, in: line) {
                    return unwrap(span, style, selection: range)
                }
                return wrap(word(at: range.location, in: line), style, caret: range.location)
            }
            let trimmed = trimmingWhitespace(range)
            guard trimmed.length > 0 else { return nil }
            if let span = removableSpan(style, at: range, in: line) {
                return unwrap(span, style, selection: trimmed)
            }
            return wrap(trimmed, style, caret: nil)
        }

        func toggleLink(in selection: NSRange) -> NoteEditPlan? {
            guard case let (line, range)? = styledLine(for: selection) else { return nil }
            let enclosing = removableLink(at: range, in: line)
            if let enclosing {
                let edits = enclosing.markerRanges.map { Edit(range: $0, replacement: "") }
                return plan(edits, selection: range)
            }
            let selected = text.substring(with: range)
            if range.length > 0, !Self.isWebURL(selected) {
                let replacement = "[\(selected)](url)"
                let urlStart = range.location + 1 + range.length + 2
                return NoteEditPlan(
                    range: range, replacement: replacement, selection: NSRange(location: urlStart, length: 3))
            }
            let replacement = "[](\(selected.isEmpty ? "url" : selected))"
            return NoteEditPlan(
                range: range, replacement: replacement,
                selection: NSRange(location: range.location + 1, length: 0))
        }

        func pasteURL(_ string: String, over selection: NSRange) -> NoteEditPlan? {
            let url = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isWebURL(url), selection.length > 0,
                case let (line, range)? = styledLine(for: selection), range == selection
            else { return nil }
            let overlapsLinkOrCode = line.inlines.contains {
                switch $0.kind {
                case .link, .code: NSIntersectionRange($0.range, selection).length > 0
                default: false
                }
            }
            guard !overlapsLinkOrCode else { return nil }
            let replacement = "[\(text.substring(with: selection))](\(url))"
            return NoteEditPlan(
                range: selection, replacement: replacement,
                selection: NSRange(location: selection.location + replacement.utf16.count, length: 0))
        }

        /// The span `toggleInline` unwraps: exact for a selection, enclosing for a caret.
        private func removableSpan(
            _ style: NoteEditAction.InlineStyle, at range: NSRange, in line: Line
        ) -> NoteMarkdown.Inline? {
            guard range.length > 0 else {
                return line.inlines.last {
                    Self.matches($0.kind, style) && $0.contentRange.location <= range.location
                        && range.location <= NSMaxRange($0.contentRange)
                }
            }
            let trimmed = trimmingWhitespace(range)
            guard trimmed.length > 0 else { return nil }
            return line.inlines.last {
                Self.matches($0.kind, style) && ($0.contentRange == trimmed || $0.range == trimmed)
            }
        }

        private func removableLink(at range: NSRange, in line: Line) -> NoteMarkdown.Inline? {
            line.inlines.last {
                guard case .link = $0.kind else { return false }
                return $0.range.location <= range.location && NSMaxRange(range) <= NSMaxRange($0.range)
            }
        }

        private func unwrap(
            _ span: NoteMarkdown.Inline, _ style: NoteEditAction.InlineStyle, selection: NSRange
        ) -> NoteEditPlan? {
            let edits = span.markerRanges.map { marker -> Edit in
                let length =
                    switch (span.kind, style) {
                    case (.strongEmphasis, .bold): 2
                    case (.strongEmphasis, _): 1
                    default: marker.length
                    }
                return Edit(range: NSRange(location: marker.location, length: length), replacement: "")
            }
            return plan(edits, selection: selection)
        }

        /// An empty range inserts the pair; `caret` keeps its place in the text when one is given.
        private func wrap(
            _ range: NSRange, _ style: NoteEditAction.InlineStyle, caret: Int?
        ) -> NoteEditPlan {
            let inner = text.substring(with: range)
            var open = Self.delimiter(for: style)
            var close = open
            if style == .code, inner.contains("`") {
                open = "`` "
                close = " ``"
            }
            let shift = open.utf16.count
            let selection =
                caret.map { NSRange(location: $0 + shift, length: 0) }
                ?? NSRange(location: range.location + shift, length: range.length)
            return NoteEditPlan(range: range, replacement: open + inner + close, selection: selection)
        }

        private func word(at caret: Int, in line: Line) -> NSRange {
            var start = caret
            var end = caret
            while start > line.contentRange.location, Unit.isAlphanumeric(text.character(at: start - 1)) {
                start -= 1
            }
            while end < NSMaxRange(line.contentRange), Unit.isAlphanumeric(text.character(at: end)) {
                end += 1
            }
            return NSRange(start..<end)
        }

        /// The one line an inline gesture acts on, with the selection clipped to its content.
        private func styledLine(for selection: NSRange) -> (Line, NSRange)? {
            let indexes = touchedLines(selection)
            guard indexes.count == 1, let index = indexes.first else { return nil }
            let line = self.line(index)
            guard !line.kind.isFenced, line.kind != .rule, line.kind != .table else { return nil }
            let end = min(NSMaxRange(selection), NSMaxRange(line.contentRange))
            guard selection.location <= end else { return nil }
            return (line, NSRange(selection.location..<end))
        }

        private func trimmingWhitespace(_ range: NSRange) -> NSRange {
            var start = range.location
            var end = NSMaxRange(range)
            while start < end, Unit.isWhitespace(text.character(at: start)) { start += 1 }
            while end > start, Unit.isWhitespace(text.character(at: end - 1)) { end -= 1 }
            return NSRange(start..<end)
        }

        // MARK: - Code blocks and quotes

        func toggleQuote(in selection: NSRange) -> NoteEditPlan? {
            let candidates = quoteCandidates(touchedLines(selection))
            guard !candidates.isEmpty else { return nil }
            let removing = candidates.allSatisfy { Self.isQuote(line($0).kind) }
            let edits = candidates.compactMap { index -> Edit? in
                let line = self.line(index)
                let start = indentEnd(of: line)
                guard removing else {
                    guard !Self.isQuote(line.kind) else { return nil }
                    return Edit(range: NSRange(location: start, length: 0), replacement: "> ")
                }
                let spaced = start + 1 < text.length && text.character(at: start + 1) == Unit.space
                return Edit(range: NSRange(location: start, length: spaced ? 2 : 1), replacement: "")
            }
            return plan(edits, selection: selection)
        }

        func toggleCodeBlock(in selection: NSRange) -> NoteEditPlan? {
            let indexes = touchedLines(selection)
            if let block = enclosingFence(indexes) { return unfence(block, selection: selection) }
            guard let first = indexes.first, let last = indexes.last,
                indexes.allSatisfy({ !line($0).kind.isFenced })
            else { return nil }
            let opening = self.line(first)
            let fence = "```"
            if indexes.count == 1, opening.kind == .blank {
                let at = opening.range.location
                return NoteEditPlan(
                    range: NSRange(location: at, length: 0), replacement: fence + "\n\n" + fence,
                    selection: NSRange(location: at + fence.utf16.count + 1, length: 0))
            }
            let body = NSRange(opening.range.location..<NSMaxRange(self.line(last).contentRange))
            let shift = fence.utf16.count + 1
            let after =
                selection.length == 0
                ? NSRange(location: selection.location + shift, length: 0)
                : NSRange(location: body.location + shift, length: body.length)
            return NoteEditPlan(
                range: body, replacement: fence + "\n" + text.substring(with: body) + "\n" + fence,
                selection: after)
        }

        /// A closing fence on the last line has no newline, so it takes the one before it.
        private func unfence(_ block: ClosedRange<Int>, selection: NSRange) -> NoteEditPlan? {
            let open = markdown.lines[block.lowerBound]
            let close = markdown.lines[block.upperBound]
            guard block.upperBound > block.lowerBound, close.kind == .fenceClose else {
                return plan([Edit(range: open.range, replacement: "")], selection: selection)
            }
            let terminated = NSMaxRange(close.contentRange) < NSMaxRange(close.range)
            let closeRange =
                terminated ? close.range : NSRange((close.range.location - 1)..<NSMaxRange(close.range))
            guard closeRange.location >= NSMaxRange(open.range) else {
                return plan(
                    [Edit(range: NSRange(open.range.location..<NSMaxRange(close.range)), replacement: "")],
                    selection: selection)
            }
            return plan(
                [Edit(range: open.range, replacement: ""), Edit(range: closeRange, replacement: "")],
                selection: selection)
        }

        /// Skips fenced, table and rule lines, and blank lines unless one is all that is touched.
        private func quoteCandidates(_ indexes: [Int]) -> [Int] {
            indexes.filter { index in
                let kind = line(index).kind
                if kind == .blank { return indexes.count == 1 }
                return !kind.isFenced && kind != .rule && kind != .table
            }
        }

        /// The fenced block holding every touched line; the virtual last line is never inside one.
        private func enclosingFence(_ indexes: [Int]) -> ClosedRange<Int>? {
            guard let first = indexes.first, let last = indexes.last else { return nil }
            return markdown.fenceBlocks.first { $0.contains(first) && $0.contains(last) }
        }

        private static func isQuote(_ kind: Line.Kind) -> Bool {
            if case .quote = kind { return true }
            return false
        }

        // MARK: - Formatting

        func formatting(of selection: NSRange) -> NoteFormatting {
            let indexes = touchedLines(selection)
            let lines = indexes.map(line)
            var result = NoteFormatting.plain
            result.headingLevel = sharedHeadingLevel(lines)
            let listed = lines.count > 1 ? lines.filter { $0.kind != .blank } : lines
            if let first = listed.first.flatMap({ Self.style(of: $0.kind) }),
                listed.allSatisfy({ Self.style(of: $0.kind) == first }) {
                result.list = first
            }
            let candidates = quoteCandidates(indexes)
            result.isQuote = !candidates.isEmpty && candidates.allSatisfy { Self.isQuote(line($0).kind) }
            result.isCodeBlock = enclosingFence(indexes) != nil
            if case let (line, range)? = styledLine(for: selection) {
                result.inlineStyles = Set(
                    NoteEditAction.InlineStyle.allCases.filter { removableSpan($0, at: range, in: line) != nil })
                result.isLink = removableLink(at: range, in: line) != nil
            }
            return result
        }

        /// Mirrors `setHeading`, which acts on heading and paragraph lines and skips the rest.
        private func sharedHeadingLevel(_ lines: [Line]) -> Int? {
            let levels = lines.compactMap { line -> Int? in
                switch line.kind {
                case .heading(let level): level
                case .paragraph: 0
                default: nil
                }
            }
            guard let first = levels.first, levels.allSatisfy({ $0 == first }) else { return nil }
            return first
        }

        // MARK: - Lines

        /// An empty note, or a caret after a final newline, touches a virtual empty line.
        private func touchedLines(_ selection: NSRange) -> [Int] {
            if selection.length == 0, selection.location == text.length, hasTrailingEmptyLine {
                return [markdown.lines.count]
            }
            return Array(markdown.lineIndexes(intersecting: selection))
        }

        private func line(_ index: Int) -> Line {
            guard index == markdown.lines.count else { return markdown.lines[index] }
            let end = NSRange(location: text.length, length: 0)
            return Line(
                kind: .blank, range: end, contentRange: end, markerRange: nil, checkboxRange: nil,
                level: 0, inlines: [])
        }

        private var hasTrailingEmptyLine: Bool {
            guard let last = markdown.lines.last else { return true }
            return NSMaxRange(last.contentRange) < NSMaxRange(last.range)
        }

        private func realLine(at location: Int) -> Int? {
            guard !(location == text.length && hasTrailingEmptyLine) else { return nil }
            return markdown.lineIndex(at: location)
        }

        private func indentEnd(of line: Line) -> Int {
            var index = line.range.location
            while index < NSMaxRange(line.contentRange), Unit.isSpaceOrTab(text.character(at: index)) {
                index += 1
            }
            return index
        }

        private func allListLines(_ indexes: Range<Int>) -> Bool {
            indexes.allSatisfy { markdown.lines[$0].kind.isList }
        }

        private func previousListLine(before index: Int) -> Line? {
            for line in markdown.lines[..<index].reversed() where line.kind != .blank {
                return line.kind.isList ? line : nil
            }
            return nil
        }

        private func nextMarker(after line: Line) -> String {
            let start = indentEnd(of: line)
            let bullet = text.substring(with: NSRange(location: start, length: 1))
            switch line.kind {
            case .ordered(let number):
                let digits = String(number).utf16.count
                let delimiter = text.substring(with: NSRange(location: start + digits, length: 1))
                return "\(number + 1)\(delimiter) "
            case .task:
                return bullet + " [ ] "
            default:
                return bullet + " "
            }
        }

        // MARK: - Renumbering

        private func inserting(_ string: String, at caret: Int) -> NoteEditPlan {
            NoteEditPlan(
                range: NSRange(location: caret, length: 0), replacement: string,
                selection: NSRange(location: caret + string.utf16.count, length: 0))
        }

        private func renumbered(inserting string: String, at caret: Int) -> NoteEditPlan? {
            renumbered(inserting(string, at: caret))
        }

        private func renumbered(removing range: NSRange, caret: Int) -> NoteEditPlan? {
            renumbered(
                NoteEditPlan(range: range, replacement: "", selection: NSRange(location: caret, length: 0)))
        }

        /// Folds the renumbering of the touched ordered runs into the same single replacement.
        private func renumbered(_ plan: NoteEditPlan?) -> NoteEditPlan? {
            guard let plan else { return nil }
            let edited = text.replacingCharacters(in: plan.range, with: plan.replacement) as NSString
            let written = NSRange(location: plan.range.location, length: plan.replacement.utf16.count)
            let after = Document(text: edited, markdown: NoteMarkdownParser.parse(edited as String))
            guard let fixes = after.plan(after.renumbering(around: written), selection: plan.selection)
            else { return plan }

            let delta = written.length - plan.range.length
            let start = min(plan.range.location, fixes.range.location)
            let end =
                NSMaxRange(fixes.range) > NSMaxRange(written)
                ? NSMaxRange(fixes.range) - delta : NSMaxRange(plan.range)
            let final = edited.replacingCharacters(in: fixes.range, with: fixes.replacement) as NSString
            let fixesDelta = fixes.replacement.utf16.count - fixes.range.length
            let replacement = final.substring(
                with: NSRange(location: start, length: end - start + delta + fixesDelta))
            return NoteEditPlan(
                range: NSRange(start..<end), replacement: replacement, selection: fixes.selection)
        }

        /// Each level counts up from its first number; a shallower line restarts deeper counters.
        private func renumbering(around range: NSRange) -> [Edit] {
            let lines = markdown.lines
            let touched = markdown.lineIndexes(intersecting: range)
            guard var first = touched.first, var last = touched.last else { return [] }
            let continuesRun = { (line: Line) in line.kind.isList || line.kind == .blank }
            while first > 0, continuesRun(lines[first - 1]) { first -= 1 }
            while last + 1 < lines.count, continuesRun(lines[last + 1]) { last += 1 }

            var nextNumber: [Int: Int] = [:]
            var edits: [Edit] = []
            for line in lines[first...last] {
                switch line.kind {
                case .blank:
                    continue
                case .bullet, .task:
                    nextNumber = nextNumber.filter { $0.key < line.level }
                case .ordered(let number):
                    nextNumber = nextNumber.filter { $0.key <= line.level }
                    let expected = nextNumber[line.level] ?? number
                    nextNumber[line.level] = expected + 1
                    guard expected != number else { continue }
                    let digits = NSRange(location: indentEnd(of: line), length: String(number).utf16.count)
                    edits.append(Edit(range: digits, replacement: String(expected)))
                default:
                    nextNumber.removeAll()
                }
            }
            return edits
        }

        /// Sorted, non-overlapping edits as one plan; the selection follows the text it covered.
        private func plan(_ edits: [Edit], selection: NSRange) -> NoteEditPlan? {
            let edits = edits.filter { $0.range.length > 0 || !$0.replacement.isEmpty }
            guard let first = edits.first, let last = edits.last else { return nil }
            var replacement = ""
            var cursor = first.range.location
            for edit in edits {
                replacement += text.substring(with: NSRange(cursor..<edit.range.location))
                replacement += edit.replacement
                cursor = NSMaxRange(edit.range)
            }
            let start = Self.map(selection.location, through: edits)
            let end = Self.map(NSMaxRange(selection), through: edits)
            return NoteEditPlan(
                range: NSRange(first.range.location..<NSMaxRange(last.range)), replacement: replacement,
                selection: NSRange(location: start, length: max(0, end - start)))
        }

        private static func map(_ position: Int, through edits: [Edit]) -> Int {
            var offset = 0
            for edit in edits {
                let written = edit.replacement.utf16.count
                if position >= NSMaxRange(edit.range) {
                    offset += written - edit.range.length
                } else {
                    guard position > edit.range.location else { break }
                    return edit.range.location + offset + min(position - edit.range.location, written)
                }
            }
            return position + offset
        }

        // MARK: - Syntax

        private static func marker(for style: NoteEditAction.ListStyle, bullet: String) -> String {
            switch style {
            case .bullet: bullet + " "
            case .ordered: "1. "
            case .task: bullet + " [ ] "
            }
        }

        private static func style(of kind: Line.Kind) -> NoteEditAction.ListStyle? {
            switch kind {
            case .bullet: .bullet
            case .ordered: .ordered
            case .task: .task
            default: nil
            }
        }

        private static func headingMarker(_ level: Int) -> String {
            level > 0 ? String(repeating: "#", count: level) + " " : ""
        }

        private static func delimiter(for style: NoteEditAction.InlineStyle) -> String {
            switch style {
            case .bold: "**"
            case .italic: "_"
            case .strikethrough: "~~"
            case .code: "`"
            }
        }

        private static func matches(
            _ kind: NoteMarkdown.Inline.Kind, _ style: NoteEditAction.InlineStyle
        ) -> Bool {
            switch (kind, style) {
            case (.strong, .bold), (.strongEmphasis, .bold), (.emphasis, .italic),
                (.strongEmphasis, .italic), (.strikethrough, .strikethrough), (.code, .code):
                true
            default:
                false
            }
        }

        private static func isWebURL(_ string: String) -> Bool {
            let lowercased = string.lowercased()
            let schemes = ["https://", "http://"]
            guard let scheme = schemes.first(where: lowercased.hasPrefix) else { return false }
            guard string.count > scheme.count, !string.contains(where: \.isWhitespace) else { return false }
            return URL(string: string) != nil
        }
    }
}
