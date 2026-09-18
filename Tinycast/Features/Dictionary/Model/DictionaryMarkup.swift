import Foundation

/// Reads a Dictionary Services XHTML record, whose span classes are its only structure.
enum DictionaryMarkup {
    static func blocks(fromXHTML xhtml: String) -> [DictionaryEntry.Block] {
        let reader = Reader()
        let parser = XMLParser(data: Data(xhtml.utf8))
        parser.delegate = reader
        guard parser.parse() else { return [] }
        return reader.blocks
    }
}

private final class Reader: NSObject, XMLParserDelegate {
    private typealias Run = DictionaryEntry.Run
    private typealias Style = DictionaryEntry.Style

    private enum Kind {
        case partOfSpeech, sense(number: String?), subsense, note, phrase, paragraph
    }

    /// What an element started, so its end knows what to close.
    private enum Role {
        case none, ignored, headGroup, headword, syllables, homograph, pronunciation, senseNumber
        case sectionLabel, block, container
    }

    private struct Frame {
        let role: Role
        let style: Style?
    }

    /// Elements that end an auto-opened paragraph: the etymology, a sub-entry, a sense group.
    private static let containers: Set<String> = [
        "entry", "sg", "se1", "se2", "etym", "subEntry", "subEntryBlock"
    ]

    /// The `| … |` a pronunciation is printed between.
    private static let pronunciationFrame = CharacterSet.whitespaces.union(["|"])

    private static let styles: [String: Style] = [
        "eg": .example, "ex": .example,
        "gg": .label, "lg": .label, "reg": .label, "ge": .label, "sy": .label, "pos": .label,
        "inf": .strong, "f": .strong, "v": .strong, "l": .strong, "bold": .strong,
        "ff": .italic, "tx": .italic
    ]

    private(set) var blocks: [DictionaryEntry.Block] = []
    private var stack: [Frame] = []
    private var open: (kind: Kind, runs: [Run], depth: Int)?

    private var headword = ""
    private var syllables = ""
    private var homograph = ""
    private var pronunciation: String?
    private var sectionLabel = ""
    private var senseNumber: String?

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        let classes = Set((attributes["class"] ?? "").split(separator: " ").map(String.init))
        let role = role(for: classes)
        let style = classes.lazy.compactMap { Self.styles[$0] }.first
        switch role {
        case .headGroup:
            headword = ""
            syllables = ""
            homograph = ""
            pronunciation = nil
        case .senseNumber:
            senseNumber = ""
        case .sectionLabel:
            close()
            sectionLabel = ""
        case .block:
            openBlock(kind(for: classes))
        default:
            break
        }
        stack.append(Frame(role: role, style: style))
    }

    func parser(
        _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard let frame = stack.popLast() else { return }
        switch frame.role {
        case .headGroup:
            close()
            let word = syllables.isEmpty ? headword : syllables
            blocks.append(
                .headword(
                    word.collapsingWhitespace, homograph: homograph.collapsingWhitespace.nilIfEmpty,
                    pronunciation: pronunciation?.trimmingCharacters(in: Self.pronunciationFrame)
                        .nilIfEmpty))
        case .senseNumber:
            senseNumber = senseNumber?.collapsingWhitespace.nilIfEmpty
        case .sectionLabel:
            blocks.append(.section(sectionLabel.collapsingWhitespace))
        case .block:
            close()
        case .container:
            if let open, open.depth >= stack.count { close() }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch stack.last(where: { $0.role != .none })?.role {
        case .headword: headword += string
        case .syllables: syllables += string
        case .homograph: homograph += string
        case .pronunciation: pronunciation = (pronunciation ?? "") + string
        case .senseNumber: senseNumber? += string.filter(\.isNumber)
        case .sectionLabel: sectionLabel += string
        case .headGroup, .ignored: break
        default: append(string)
        }
    }

    private func role(for classes: Set<String>) -> Role {
        if stack.contains(where: { $0.role == .headGroup }) {
            if classes.contains("ty_hom") { return .homograph }
            if classes.contains("hw") { return .headword }
            if classes.contains("syl_txt") { return .syllables }
            if !classes.isDisjoint(with: ["prx", "pr"]), pronunciation == nil { return .pronunciation }
            return .none
        }
        if classes.contains("hg") { return .headGroup }
        if classes.contains("x_xoLblBlk") { return .sectionLabel }
        // A sense's `sn` is its number; a sub-sense's is the `•` its block already implies.
        if classes.contains("sn") { return classes.contains("tg_se2") ? .senseNumber : .ignored }
        if !classes.isDisjoint(with: ["posg", "msDict", "note", "x_xoh"]) { return .block }
        if !classes.isDisjoint(with: Self.containers) { return .container }
        return .none
    }

    private func kind(for classes: Set<String>) -> Kind {
        if classes.contains("posg") { return .partOfSpeech }
        if classes.contains("note") { return .note }
        if classes.contains("x_xoh") { return .phrase }
        if classes.contains("t_subsense") { return .subsense }
        defer { senseNumber = nil }
        return .sense(number: senseNumber)
    }

    private func openBlock(_ kind: Kind) {
        close()
        open = (kind, [], stack.count)
    }

    private func append(_ string: String) {
        if open == nil {
            guard !string.allSatisfy(\.isWhitespace) else { return }
            // Loose text belongs to the nearest container, so it closes when that does.
            let depth = stack.lastIndex { $0.role == .container } ?? 0
            open = (.paragraph, [], depth)
        }
        let style = stack.last { $0.style != nil }?.style ?? .plain
        guard var block = open else { return }
        if let last = block.runs.indices.last, block.runs[last].style == style {
            block.runs[last].text += string
        } else {
            block.runs.append(Run(text: string, style: style))
        }
        open = block
    }

    private func close() {
        guard let block = open else { return }
        open = nil
        let runs = block.runs.trimmed
        guard !runs.isEmpty else { return }
        switch block.kind {
        case .partOfSpeech: blocks.append(.partOfSpeech(runs))
        case .sense(let number): blocks.append(.sense(number: number, runs))
        case .subsense: blocks.append(.subsense(runs))
        case .note: blocks.append(.note(runs))
        case .phrase: blocks.append(.phrase(runs))
        case .paragraph: blocks.append(.paragraph(runs))
        }
    }
}

extension [DictionaryEntry.Run] {
    /// Whitespace collapsed across run boundaries, and none left at either end.
    fileprivate var trimmed: [DictionaryEntry.Run] {
        var result: [DictionaryEntry.Run] = []
        var endsInSpace = true
        for run in self {
            var text = ""
            for character in run.text {
                if character.isWhitespace {
                    if !endsInSpace { text.append(" ") }
                    endsInSpace = true
                } else {
                    text.append(character)
                    endsInSpace = false
                }
            }
            if !text.isEmpty { result.append(DictionaryEntry.Run(text: text, style: run.style)) }
        }
        if endsInSpace, let last = result.indices.last {
            result[last].text.removeLast()
            if result[last].text.isEmpty { result.removeLast() }
        }
        return result
    }
}

extension String {
    fileprivate var collapsingWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
