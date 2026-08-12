import Foundation

enum NoteMarkdownCommand: String, CaseIterable, Sendable, Hashable {
    case normal
    case heading1
    case heading2
    case heading3
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case blockquote
    case unorderedList
    case orderedList
    case taskList
    case codeBlock
    case horizontalRule
}

struct NoteMarkdownEditPlan: Sendable, Equatable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

enum NoteListEditingAction: Sendable {
    case newline
    case backspace
    case indent
    case outdent
}

enum NoteMarkdownEditing {
    static func plan(
        _ command: NoteMarkdownCommand,
        source: String,
        selection: NSRange,
        presentation: NoteMarkdownPresentation? = nil
    ) -> NoteMarkdownEditPlan? {
        let text = source as NSString
        guard selection.location != NSNotFound, selection.location >= 0,
            NSMaxRange(selection) <= text.length
        else { return nil }
        switch command {
        case .bold:
            return inline(
                wrapper: "**",
                source: text,
                context: inlineContext(
                    command, source: text, selection: selection, presentation: presentation))
        case .italic:
            return inline(
                wrapper: "_",
                source: text,
                context: inlineContext(
                    command, source: text, selection: selection, presentation: presentation))
        case .strikethrough:
            return inline(
                wrapper: "~~",
                source: text,
                context: inlineContext(
                    command, source: text, selection: selection, presentation: presentation))
        case .inlineCode:
            return inline(
                wrapper: "`",
                source: text,
                context: inlineContext(
                    command, source: text, selection: selection, presentation: presentation))
        case .link:
            return link(source: text, selection: selection)
        case .normal, .heading1, .heading2, .heading3, .blockquote,
            .unorderedList, .orderedList, .taskList:
            return block(command, source: text, selection: selection)
        case .codeBlock:
            return fencedCode(source: text, selection: selection)
        case .horizontalRule:
            return horizontalRule(source: text, selection: selection)
        }
    }

    static func activeCommands(
        selection: NSRange,
        presentation: NoteMarkdownPresentation
    ) -> Set<NoteMarkdownCommand> {
        let constructs = presentation.constructs.filter { construct in
            if selection.length == 0 {
                return selection.location >= construct.range.location
                    && selection.location <= NSMaxRange(construct.range)
            }
            return NSIntersectionRange(selection, construct.contentRange).length > 0
        }
        var commands = Set(constructs.compactMap { command(for: $0.kind) })
        if constructs.contains(where: { $0.kind == .strongEmphasis }) {
            commands.formUnion([.bold, .italic])
        }
        let blockCommands: Set<NoteMarkdownCommand> = [
            .heading1, .heading2, .heading3, .blockquote, .unorderedList,
            .orderedList, .taskList, .codeBlock
        ]
        if commands.isDisjoint(with: blockCommands) { commands.insert(.normal) }
        return commands
    }

    static func planListEdit(
        _ action: NoteListEditingAction,
        source: String,
        selection: NSRange
    ) -> NoteMarkdownEditPlan? {
        let text = source as NSString
        guard selection.location != NSNotFound,
            selection.location >= 0,
            NSMaxRange(selection) <= text.length
        else { return nil }
        switch action {
        case .newline:
            return continueList(in: text, selection: selection)
        case .backspace:
            return removeListPrefix(in: text, selection: selection)
        case .indent:
            return changeListIndent(in: text, selection: selection, outdent: false)
        case .outdent:
            return changeListIndent(in: text, selection: selection, outdent: true)
        }
    }

    private struct InlineContext {
        let selection: NSRange
        let removingWrapper: String?
    }

    private struct ListLine {
        let lineRange: NSRange
        let indentationRange: NSRange
        let prefixRange: NSRange
        let continuation: String
        let contentRange: NSRange
    }

    private static func continueList(
        in source: NSString,
        selection: NSRange
    ) -> NoteMarkdownEditPlan? {
        guard selection.length == 0,
            let line = listLine(in: source, at: selection.location),
            selection.location >= line.contentRange.location
        else { return nil }
        let content = source.substring(with: line.contentRange)
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            return NoteMarkdownEditPlan(
                range: line.prefixRange,
                replacement: "",
                selection: NSRange(location: line.prefixRange.location, length: 0))
        }
        let indentation = source.substring(with: line.indentationRange)
        let insertion = "\n" + indentation + line.continuation
        return NoteMarkdownEditPlan(
            range: selection,
            replacement: insertion,
            selection: NSRange(
                location: selection.location + (insertion as NSString).length,
                length: 0))
    }

    private static func removeListPrefix(
        in source: NSString,
        selection: NSRange
    ) -> NoteMarkdownEditPlan? {
        guard selection.length == 0,
            let line = listLine(in: source, at: selection.location),
            selection.location == line.contentRange.location
        else { return nil }
        return NoteMarkdownEditPlan(
            range: line.prefixRange,
            replacement: "",
            selection: NSRange(location: line.prefixRange.location, length: 0))
    }

    private static func changeListIndent(
        in source: NSString,
        selection: NSRange,
        outdent: Bool
    ) -> NoteMarkdownEditPlan? {
        let lineRange = source.coveringLineRange(for: selection)
        let original = source.substring(with: lineRange) as NSString
        var changes: [PrefixChange] = []
        var location = 0
        while location < original.length {
            let line = original.lineRange(for: NSRange(location: location, length: 0))
            guard let list = listLine(in: original, at: line.location) else { return nil }
            let indentation = original.substring(with: list.indentationRange)
            let editRange: NSRange
            let replacementLength: Int
            if outdent {
                if indentation.hasPrefix("\t") {
                    editRange = NSRange(location: line.location, length: 1)
                } else {
                    let spaces = indentation.prefix(4).prefix { $0 == " " }.count
                    guard spaces > 0 else { return nil }
                    editRange = NSRange(location: line.location, length: spaces)
                }
                replacementLength = 0
            } else {
                editRange = NSRange(location: line.location, length: 0)
                replacementLength = 4
            }
            changes.append(PrefixChange(range: editRange, replacementLength: replacementLength))
            location = NSMaxRange(line)
        }
        var replacement = original as String
        for change in changes.reversed() {
            replacement = (replacement as NSString).replacingCharacters(
                in: change.range,
                with: outdent ? "" : "    ")
        }
        let relativeStart = selection.location - lineRange.location
        let relativeEnd = NSMaxRange(selection) - lineRange.location
        let mappedStart = map(relativeStart, through: changes)
        let mappedEnd = map(relativeEnd, through: changes)
        return NoteMarkdownEditPlan(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location + mappedStart,
                length: max(0, mappedEnd - mappedStart)))
    }

    private static func listLine(in source: NSString, at location: Int) -> ListLine? {
        guard source.length > 0 else { return nil }
        let probe = min(location, source.length - 1)
        let lineRange = source.lineRange(for: NSRange(location: probe, length: 0))
        var contentEnd = NSMaxRange(lineRange)
        while contentEnd > lineRange.location, isNewline(source.character(at: contentEnd - 1)) {
            contentEnd -= 1
        }
        var markerLocation = lineRange.location
        while markerLocation < contentEnd {
            let character = source.character(at: markerLocation)
            guard character == 0x20 || character == 0x09 else { break }
            markerLocation += 1
        }
        let indentationRange = NSRange(
            location: lineRange.location,
            length: markerLocation - lineRange.location)
        let body = source.substring(
            with: NSRange(location: markerLocation, length: contentEnd - markerLocation))
        let prefix: String
        let continuation: String
        if body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ") || body.hasPrefix("- [X] ") {
            prefix = String(body.prefix(6))
            continuation = "- [ ] "
        } else if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") {
            prefix = String(body.prefix(2))
            continuation = prefix
        } else if let orderedLength = orderedPrefixLength(in: body) {
            prefix = String(body.prefix(orderedLength))
            let number = Int(body.prefix { $0.isNumber }) ?? 0
            continuation = "\(number + 1). "
        } else {
            return nil
        }
        let prefixLength = (prefix as NSString).length
        let prefixRange = NSRange(location: markerLocation, length: prefixLength)
        return ListLine(
            lineRange: lineRange,
            indentationRange: indentationRange,
            prefixRange: prefixRange,
            continuation: continuation,
            contentRange: NSRange(
                location: NSMaxRange(prefixRange),
                length: contentEnd - NSMaxRange(prefixRange)))
    }

    private static func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2028 || character == 0x2029
    }

    private static func inline(
        wrapper: String,
        source: NSString,
        context: InlineContext
    ) -> NoteMarkdownEditPlan {
        let selection = context.selection
        let wrapperLength = (wrapper as NSString).length
        if selection.length == 0 {
            let replacement = wrapper + wrapper
            return NoteMarkdownEditPlan(
                range: selection,
                replacement: replacement,
                selection: NSRange(location: selection.location + wrapperLength, length: 0))
        }

        let selected = source.substring(with: selection)
        let removingWrapper = context.removingWrapper ?? wrapper
        let removingLength = (removingWrapper as NSString).length
        if selected.hasPrefix(removingWrapper), selected.hasSuffix(removingWrapper),
            (selected as NSString).length >= removingLength * 2
        {
            let innerRange = NSRange(
                location: removingLength,
                length: (selected as NSString).length - removingLength * 2)
            let replacement = (selected as NSString).substring(with: innerRange)
            return NoteMarkdownEditPlan(
                range: selection,
                replacement: replacement,
                selection: NSRange(location: selection.location, length: innerRange.length))
        }

        let leading = selected.prefix { $0.isWhitespace }
        let trailing = selected.reversed().prefix { $0.isWhitespace }.reversed()
        let leadingLength = (String(leading) as NSString).length
        let trailingLength = (String(trailing) as NSString).length
        let innerLength = max(0, selection.length - leadingLength - trailingLength)
        let inner = source.substring(
            with: NSRange(location: selection.location + leadingLength, length: innerLength))
        let replacement = String(leading) + wrapper + inner + wrapper + String(trailing)
        return NoteMarkdownEditPlan(
            range: selection,
            replacement: replacement,
            selection: NSRange(
                location: selection.location + leadingLength + wrapperLength,
                length: innerLength))
    }

    private static func inlineContext(
        _ command: NoteMarkdownCommand,
        source: NSString,
        selection: NSRange,
        presentation: NoteMarkdownPresentation?
    ) -> InlineContext {
        guard selection.length > 0,
            let construct = presentation?.constructs.first(where: {
                $0.contentRange == selection && matches(command, kind: $0.kind)
            }),
            let marker = construct.markerRanges.first
        else { return InlineContext(selection: selection, removingWrapper: nil) }
        let literalMarker = source.substring(with: marker)
        let wrapper: String
        if case .strongEmphasis = construct.kind {
            let length = command == .bold ? 2 : 1
            wrapper = (literalMarker as NSString).substring(
                with: NSRange(location: 0, length: min(length, marker.length)))
        } else {
            wrapper = literalMarker
        }
        return InlineContext(selection: construct.range, removingWrapper: wrapper)
    }

    private static func matches(
        _ command: NoteMarkdownCommand,
        kind: NoteMarkdownPresentation.Construct.Kind
    ) -> Bool {
        switch (command, kind) {
        case (.bold, .strong), (.bold, .strongEmphasis),
            (.italic, .emphasis), (.italic, .strongEmphasis),
            (.strikethrough, .strikethrough), (.inlineCode, .inlineCode):
            return true
        default:
            return false
        }
    }

    private static func command(
        for kind: NoteMarkdownPresentation.Construct.Kind
    ) -> NoteMarkdownCommand? {
        switch kind {
        case .heading(let level):
            return switch level {
            case 1: .heading1
            case 2: .heading2
            case 3: .heading3
            default: nil
            }
        case .strong: return .bold
        case .emphasis: return .italic
        case .strongEmphasis: return nil
        case .strikethrough: return .strikethrough
        case .inlineCode: return .inlineCode
        case .link: return .link
        case .blockquote: return .blockquote
        case .unorderedList: return .unorderedList
        case .orderedList: return .orderedList
        case .task: return .taskList
        case .codeBlock: return .codeBlock
        case .image, .horizontalRule: return nil
        }
    }

    private static func link(source: NSString, selection: NSRange) -> NoteMarkdownEditPlan {
        if selection.length == 0 {
            return NoteMarkdownEditPlan(
                range: selection,
                replacement: "[text](url)",
                selection: NSRange(location: selection.location + 7, length: 3))
        }
        let selected = source.substring(with: selection)
        let replacement = "[\(selected)](url)"
        return NoteMarkdownEditPlan(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + selection.length + 3, length: 3))
    }

    private static func block(
        _ command: NoteMarkdownCommand,
        source: NSString,
        selection: NSRange
    ) -> NoteMarkdownEditPlan {
        let lineRange = source.coveringLineRange(for: selection)
        let original = source.substring(with: lineRange)
        let hasTrailingNewline = original.hasSuffix("\n") || original.hasSuffix("\r")
        var lines = original.components(separatedBy: .newlines)
        if hasTrailingNewline, lines.last?.isEmpty == true { lines.removeLast() }
        let allRequested = command != .normal && lines.allSatisfy { hasPrefix(for: command, line: $0) }
        var prefixChanges: [PrefixChange] = []
        var originalLineLocation = 0
        let transformed = lines.enumerated().map { index, line in
            let stripped = stripOutermostPrefix(from: line)
            let indentationLength = (stripped.indentation as NSString).length
            let contentLength = (stripped.content as NSString).length
            let oldPrefixLength = (line as NSString).length - indentationLength - contentLength
            let newPrefix = command == .normal || allRequested
                ? "" : prefix(for: command, index: index)
            let newPrefixLength = (newPrefix as NSString).length
            prefixChanges.append(
                PrefixChange(
                    range: NSRange(
                        location: originalLineLocation + indentationLength,
                        length: oldPrefixLength),
                    replacementLength: newPrefixLength))
            originalLineLocation += (line as NSString).length + 1
            return stripped.indentation + newPrefix + stripped.content
        }
        var replacement = transformed.joined(separator: "\n")
        if hasTrailingNewline { replacement += "\n" }
        let relativeStart = selection.location - lineRange.location
        let relativeEnd = NSMaxRange(selection) - lineRange.location
        let mappedStart = map(relativeStart, through: prefixChanges)
        let mappedEnd = map(relativeEnd, through: prefixChanges)
        return NoteMarkdownEditPlan(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location + mappedStart,
                length: max(0, mappedEnd - mappedStart)))
    }

    private struct PrefixChange {
        let range: NSRange
        let replacementLength: Int
    }

    private static func map(_ location: Int, through changes: [PrefixChange]) -> Int {
        var delta = 0
        for change in changes {
            guard location >= change.range.location else { break }
            if location <= NSMaxRange(change.range) {
                let offset = change.range.length == 0
                    ? change.replacementLength
                    : min(location - change.range.location, change.replacementLength)
                return change.range.location + delta + offset
            }
            delta += change.replacementLength - change.range.length
        }
        return location + delta
    }

    private static func fencedCode(source: NSString, selection: NSRange) -> NoteMarkdownEditPlan {
        let lineRange = source.coveringLineRange(for: selection)
        let selected = source.substring(with: lineRange)
        if selected.hasPrefix("```\n"), selected.hasSuffix("```\n") {
            let value = (selected as NSString).substring(
                with: NSRange(location: 4, length: (selected as NSString).length - 8))
            return NoteMarkdownEditPlan(
                range: lineRange,
                replacement: value,
                selection: NSRange(location: lineRange.location, length: (value as NSString).length))
        }
        let suffix = selected.hasSuffix("\n") ? "```\n" : "\n```"
        let replacement = "```\n" + selected + suffix
        return NoteMarkdownEditPlan(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(location: lineRange.location + 4, length: (selected as NSString).length))
    }

    private static func horizontalRule(source: NSString, selection: NSRange) -> NoteMarkdownEditPlan {
        let lineRange = source.coveringLineRange(for: selection)
        let line = source.substring(with: lineRange)
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NoteMarkdownEditPlan(
                range: lineRange,
                replacement: "---\n",
                selection: NSRange(location: lineRange.location + 4, length: 0))
        }
        let replacement = line.hasSuffix("\n") || line.hasSuffix("\r")
            ? "---\n" : "\n---\n"
        return NoteMarkdownEditPlan(
            range: NSRange(location: NSMaxRange(lineRange), length: 0),
            replacement: replacement,
            selection: NSRange(
                location: NSMaxRange(lineRange) + (replacement as NSString).length,
                length: 0))
    }

    private static func prefix(for command: NoteMarkdownCommand, index: Int) -> String {
        switch command {
        case .heading1: "# "
        case .heading2: "## "
        case .heading3: "### "
        case .blockquote: "> "
        case .unorderedList: "- "
        case .orderedList: "\(index + 1). "
        case .taskList: "- [ ] "
        default: ""
        }
    }

    private static func hasPrefix(for command: NoteMarkdownCommand, line: String) -> Bool {
        let stripped = stripOutermostPrefix(from: line)
        let originalPrefixLength = (line as NSString).length
            - (stripped.indentation as NSString).length
            - (stripped.content as NSString).length
        guard originalPrefixLength > 0 else { return false }
        let body = String(line.dropFirst(stripped.indentation.count))
        switch command {
        case .heading1: return body.hasPrefix("# ") && !body.hasPrefix("## ")
        case .heading2: return body.hasPrefix("## ") && !body.hasPrefix("### ")
        case .heading3: return body.hasPrefix("### ") && !body.hasPrefix("#### ")
        case .blockquote: return body.hasPrefix("> ")
        case .unorderedList: return body.hasPrefix("- ") && !body.hasPrefix("- [")
        case .orderedList:
            return orderedPrefixLength(in: body) != nil
        case .taskList:
            return body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ") || body.hasPrefix("- [X] ")
        default:
            return false
        }
    }

    private static func stripOutermostPrefix(from line: String)
        -> (indentation: String, content: String)
    {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        var body = String(line.dropFirst(indentation.count))
        if body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ") || body.hasPrefix("- [X] ") {
            body.removeFirst(6)
        } else if let orderedLength = orderedPrefixLength(in: body) {
            body.removeFirst(orderedLength)
        } else if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ")
            || body.hasPrefix("> ")
        {
            body.removeFirst(2)
        } else {
            let hashes = body.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), body.dropFirst(hashes).hasPrefix(" ") {
                body.removeFirst(hashes + 1)
            }
        }
        return (indentation, body)
    }

    private static func orderedPrefixLength(in line: String) -> Int? {
        let digits = line.prefix { $0.isNumber }.count
        guard digits > 0 else { return nil }
        let suffix = line.dropFirst(digits)
        return suffix.hasPrefix(". ") ? digits + 2 : nil
    }
}

private extension NSString {
    func coveringLineRange(for selection: NSRange) -> NSRange {
        if length == 0 { return NSRange(location: 0, length: 0) }
        let location = min(selection.location, length - 1)
        let effectiveLength = selection.length == 0 ? 0 : min(selection.length, length - location)
        return lineRange(for: NSRange(location: location, length: effectiveLength))
    }
}
