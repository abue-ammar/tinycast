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
        case partOfSpeech, sense(number: String?), subsense, note, phrase, example, paragraph
    }

    /// What an element started, so its end knows what to close.
    private enum Role {
        case none, ignored, headGroup, title, headword, syllables, homograph, pronunciation
        case senseNumber, sectionLabel, block, container
    }

    private struct Frame {
        let role: Role
        let style: Style?
        let isDefinition: Bool
    }

    /// Elements that end an auto-opened paragraph: the etymology, a sub-entry, a sense group.
    private static let containers: Set<String> = [
        "entry", "sg", "se1", "se2", "etym", "subEntry", "subEntryBlock",
        "semb", "idmsec", "pvsec", "csec", "drvsec", "x_xo1"
    ]

    private static let blocks: Set<String> = [
        "posg", "gramb", "msDict", "msThes", "note", "box", "cn", "exg", "x_xoh", "idm", "pvg", "cwg", "drvg"
    ]

    private static let sectionLabels: Set<String> = ["tg_idmb", "tg_pvb", "tg_cb"]

    /// Spans the stylesheet sets apart by margin alone, so their text abuts its neighbour's.
    private static let spacedBefore: Set<String> = [
        "trg", "ind", "frmg", "ps", "u", "xrg", "xrlabelGroup"
    ]

    private static let unspacedBefore: Set<Character> = [
        ",", ".", ";", ":", "!", "?", ")", "]", "、", "，", "。", "；", "：", "！", "？", "）", "】", "〕"
    ]

    /// The `| … |` or `/ … /` a pronunciation is printed between.
    private static let pronunciationFrame = CharacterSet.whitespaces.union(["|", "/"])

    private static let styles: [String: Style] = [
        "eg": .example, "ex": .example,
        "gg": .label, "lg": .label, "reg": .label, "ge": .label, "sy": .label, "pos": .label,
        "ps": .label, "ind": .label, "co": .label, "lev": .label, "fld": .label, "gr": .label,
        "cnt": .label, "usage": .label, "oup_label": .label, "ty_pinyin": .label,
        "inf": .strong, "f": .strong, "v": .strong, "l": .strong, "bold": .strong, "frm": .strong,
        "idm": .strong, "pv": .strong, "cw": .strong, "drv": .strong,
        "ff": .italic, "tx": .italic, "italic": .italic
    ]

    private(set) var blocks: [DictionaryEntry.Block] = []
    private var stack: [Frame] = []
    private var open: (kind: Kind, runs: [Run], depth: Int)?

    private var headwordPending = false
    private var headword = ""
    private var syllables = ""
    private var homograph = ""
    private var pronunciation: String?
    private var sectionLabel = ""
    private var senseNumber: String?
    private var wordBreakDue = false
    private var definitionJustEnded = false

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        let classes = Set((attributes["class"] ?? "").split(separator: " ").map(String.init))
        let followsDefinition = definitionJustEnded
        definitionJustEnded = false
        var role = role(for: classes, element: name)
        // A colon runs examples on from their definition; without one they start their own line.
        if role == .none, classes.contains("eg"), followsDefinition, !openEndsWithColon {
            role = .block
        }
        let style = classes.lazy.compactMap { Self.styles[$0] }.first
        if !classes.isDisjoint(with: Self.spacedBefore) { wordBreakDue = true }
        switch role {
        case .headGroup, .title:
            headwordPending = true
            headword = ""
            syllables = ""
            homograph = ""
            pronunciation = nil
        case .senseNumber:
            close()
            // A sense nested before any text of its parent's shares its line: `1 a`.
            senseNumber = senseNumber.map { $0 + " " } ?? ""
        case .sectionLabel:
            close()
            sectionLabel = ""
        case .block:
            openBlock(kind(for: classes))
        case .container:
            if case .partOfSpeech = open?.kind { close() }
        default:
            break
        }
        stack.append(Frame(role: role, style: style, isDefinition: classes.contains("df")))
    }

    func parser(
        _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard let frame = stack.popLast() else { return }
        definitionJustEnded = frame.isDefinition
        switch frame.role {
        case .headGroup, .title:
            emitHeadword()
            close()
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
        case .headword, .title: headword += string
        case .syllables: syllables += string
        case .homograph: homograph += string
        case .pronunciation: pronunciation = (pronunciation ?? "") + string
        case .senseNumber: senseNumber? += string.filter { $0.isNumber || $0.isLetter || $0 == " " }
        case .sectionLabel: sectionLabel += string
        case .ignored: break
        case .headGroup:
            // A usage note or cross-reference in the head group follows the headword it qualifies.
            if !string.allSatisfy(\.isWhitespace) { emitHeadword() }
            append(string)
        default: append(string)
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        close()
    }

    /// A record built from the plain Dictionary Development Kit template has no classes at all.
    private func role(for classes: Set<String>, element: String) -> Role {
        if stack.contains(where: { $0.role == .headGroup }) {
            if classes.contains("ty_hom") { return .homograph }
            if !classes.isDisjoint(with: ["hw", "hvg"]) { return .headword }
            if classes.contains("syl_txt") { return .syllables }
            if !classes.isDisjoint(with: ["prx", "pr"]) { return .pronunciation }
            return .none
        }
        if !classes.isDisjoint(with: ["hg", "hwg"]) { return .headGroup }
        if element == "h1" { return .title }
        if classes.contains("x_xoLblBlk") { return .sectionLabel }
        if classes.contains("ty_label"), !classes.isDisjoint(with: Self.sectionLabels) {
            return .sectionLabel
        }
        // A sense's `sn` is its number; a sub-sense's or example's is the bullet its block implies.
        if classes.contains("sn") {
            return classes.contains("tg_msDict") || isInExample ? .ignored : .senseNumber
        }
        if classes.contains("ty_label"), !classes.isDisjoint(with: ["tg_semb", "tg_se2"]) {
            return .senseNumber
        }
        if classes.contains("tg_se1") { return .ignored }
        if !classes.isDisjoint(with: Self.blocks) { return .block }
        if !classes.isDisjoint(with: Self.containers) || element == "p" { return .container }
        return .none
    }

    private func kind(for classes: Set<String>) -> Kind {
        if !classes.isDisjoint(with: ["posg", "gramb"]) { return .partOfSpeech }
        if !classes.isDisjoint(with: ["note", "box", "cn"]) { return .note }
        if !classes.isDisjoint(with: ["x_xoh", "idm", "pvg", "cwg", "drvg"]) { return .phrase }
        if classes.contains("t_subsense") { return .subsense }
        if classes.contains("eg") { return .example }
        if classes.contains("exg") { return pendingSense(or: .example) }
        defer { senseNumber = nil }
        return .sense(number: senseNumber)
    }

    private var openEndsWithColon: Bool {
        open?.runs.last?.text.trimmingCharacters(in: .whitespaces).hasSuffix(":") ?? false
    }

    private var isInExample: Bool {
        if case .example = open?.kind { return true }
        return false
    }

    private func pendingSense(or fallback: Kind) -> Kind {
        guard let number = senseNumber else { return fallback }
        senseNumber = nil
        return .sense(number: number)
    }

    private func emitHeadword() {
        guard headwordPending else { return }
        headwordPending = false
        close()
        let word = syllables.isEmpty ? headword : syllables
        blocks.append(
            .headword(
                word.collapsingWhitespace, homograph: homograph.collapsingWhitespace.nilIfEmpty,
                pronunciation: pronunciation?.trimmingCharacters(in: Self.pronunciationFrame)
                    .collapsingWhitespace.nilIfEmpty))
    }

    private func openBlock(_ kind: Kind) {
        close()
        open = (kind, [], stack.count)
    }

    private func append(_ text: String) {
        var string = text
        if wordBreakDue, let first = string.first(where: { !$0.isWhitespace }) {
            wordBreakDue = false
            if !Self.unspacedBefore.contains(first) { string = " " + string }
        }
        if open == nil {
            guard !string.allSatisfy(\.isWhitespace) else { return }
            // Loose text belongs to the nearest container, so it closes when that does.
            let depth = stack.lastIndex { $0.role == .container } ?? 0
            open = (pendingSense(or: .paragraph), [], depth)
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
        case .example: blocks.append(.example(runs))
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
                // A separator that trailed the previous block's text never leads this one.
                if result.isEmpty, text.isEmpty, character == "," || character == ";" { continue }
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
