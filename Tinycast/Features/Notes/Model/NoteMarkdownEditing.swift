import Foundation

enum NoteMarkdownCommand: String, CaseIterable, Sendable {
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

enum NoteMarkdownEditing {
    static func plan(
        _ command: NoteMarkdownCommand,
        source: String,
        selection: NSRange
    ) -> NoteMarkdownEditPlan? {
        let text = source as NSString
        guard selection.location != NSNotFound, selection.location >= 0,
            NSMaxRange(selection) <= text.length
        else { return nil }
        switch command {
        case .bold:
            return inline(wrapper: "**", source: text, selection: selection)
        case .italic:
            return inline(wrapper: "_", source: text, selection: selection)
        case .strikethrough:
            return inline(wrapper: "~~", source: text, selection: selection)
        case .inlineCode:
            return inline(wrapper: "`", source: text, selection: selection)
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

    private static func inline(
        wrapper: String,
        source: NSString,
        selection: NSRange
    ) -> NoteMarkdownEditPlan {
        let wrapperLength = (wrapper as NSString).length
        if selection.length == 0 {
            let replacement = wrapper + wrapper
            return NoteMarkdownEditPlan(
                range: selection,
                replacement: replacement,
                selection: NSRange(location: selection.location + wrapperLength, length: 0))
        }

        let selected = source.substring(with: selection)
        if selected.hasPrefix(wrapper), selected.hasSuffix(wrapper),
            (selected as NSString).length >= wrapperLength * 2
        {
            let innerRange = NSRange(
                location: wrapperLength,
                length: (selected as NSString).length - wrapperLength * 2)
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
        let replacement = "---\n"
        return NoteMarkdownEditPlan(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(location: lineRange.location + 4, length: 0))
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
