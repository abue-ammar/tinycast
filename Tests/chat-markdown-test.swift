import AppKit
import SwiftUI

/// The chat's selectable text: one attributed string whose find marks land where the index says.
@main
@MainActor
struct ChatMarkdownTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static let reply = """
        # Apple notes

        An apple a day, says [the guide](https://example.com/guide). Another apple follows.

        - First apple
          - Nested apple
        - Second item

        3. Numbered apple

        > Quoted apple

        ```swift
        let apple = 1
        ```

        | Fruit | Apple? |
        | - | - |
        | One | apple |
        | Two | apple |

        ## Second section

        A final paragraph.
        """

    static func main() {
        everyMatchLandsOnItsWord()
        textReadsAsTheReplyDoes()
        onlyWebAndMailLinksOpen()
        formulasAreOneCharacterEach()
        findSkipsFormulasButLandsAroundThem()
        formulasTypesetByTheirStructure()
        wideFormulasShrinkToTheLine()
        equationsStillArrivingHoldTheirPlace()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func render(
        _ message: ChatMessage, current: ChatFindOccurrence?, citations: [String: Int] = [:]
    ) -> ChatRenderedText {
        guard case .text(let text)? = message.segments.first else { fatalError("a text segment") }
        return ChatMarkdownRenderer(
            ChatMarkdownSource(
                blocks: MarkdownBlock.parse(text, midStream: message.isArriving(segmentAt: 0, of: 1)),
                highlight: ChatTextHighlight(query: "apple", current: current),
                citations: citations, prefix: [0], failed: false, metrics: .standard)
        ).render()
    }

    /// The paths the index hands out are the ones the renderer builds, leaf by leaf.
    static func everyMatchLandsOnItsWord() {
        let message = ChatMessage(role: .assistant, text: reply)
        let found = ChatFindIndex.occurrences(of: "apple", in: [message])
        expect(found.count == 11, "every apple in the reply is a stop of its own, got \(found.count)")
        let citations = ["https://example.com/guide": 1]
        for occurrence in found {
            let rendered = render(message, current: occurrence, citations: citations)
            guard let range = rendered.current else {
                expect(false, "the match at \(occurrence.leaf) #\(occurrence.index) is drawn as current")
                continue
            }
            let word = (rendered.string.string as NSString).substring(with: range)
            expect(
                word.lowercased() == "apple",
                "the current mark at \(occurrence.leaf) #\(occurrence.index) sits on its word, got \(word)")
        }
        let marks = render(message, current: nil)
        var tinted = 0
        marks.string.enumerateAttribute(
            .backgroundColor, in: NSRange(location: 0, length: marks.string.length)
        ) { value, range, _ in
            let word = (marks.string.string as NSString).substring(with: range)
            if value != nil, word.lowercased() == "apple" {
                tinted += 1
            }
        }
        expect(tinted == found.count, "every match takes the find tint, got \(tinted) of \(found.count)")
    }

    static func textReadsAsTheReplyDoes() {
        let rendered = render(
            ChatMessage(role: .assistant, text: reply), current: nil,
            citations: ["https://example.com/guide": 1])
        let text = rendered.string.string
        expect(text.hasPrefix("Apple notes\n"), "a heading is its own line")
        expect(text.contains("Second section\nA final paragraph"), "both sections share one rendered string")
        expect(
            text.contains("says the guide. [1]Another") || text.contains("says the guide.[1] Another"),
            "the citation closes the sentence that cited it: \(text.debugDescription)")
        expect(
            text.contains("•\tFirst apple\n•\tNested apple"), "bullets read as bullets, nested ones too")
        expect(text.contains("3.\tNumbered apple"), "a numbered list keeps its own start")
        expect(text.contains("let apple = 1"), "code is part of the selectable text")
        expect(!text.hasSuffix("\n"), "no empty line is left under the reply")
        expect(
            rendered.codeBlocks.map(\.code) == ["let apple = 1"]
                && rendered.codeBlocks.first?.language == "swift",
            "each code block is known, for its Copy button")
    }

    static func attachments(in string: NSAttributedString) -> [(range: NSRange, cell: NSTextAttachmentCell?)]
    {
        var found: [(NSRange, NSTextAttachmentCell?)] = []
        let whole = NSRange(location: 0, length: string.length)
        string.enumerateAttribute(.attachment, in: whole) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            found.append((range, attachment.attachmentCell as? NSTextAttachmentCell))
        }
        return found
    }

    /// Each formula is one attachment character carrying the source a copy puts back.
    static func formulasAreOneCharacterEach() {
        let text = "Roots \\(x^2\\) and $y$.\n\n$$\\frac{a}{b}$$\n\nAt $5 or $10, $\\foo$."
        let rendered = render(ChatMessage(role: .assistant, text: text), current: nil).string
        let found = attachments(in: rendered)
        expect(found.count == 3, "two inline formulas and one display formula, got \(found.count)")
        expect(
            found.allSatisfy { $0.range.length == 1 && $0.cell is MathAttachmentCell }, "each draws one cell")
        expect(
            found.map { $0.cell?.accessibilityRole() } == Array(repeating: .image, count: found.count)
                && found.first?.cell?.accessibilityLabel() == "\\(x^2\\)",
            "VoiceOver meets each formula as an image named by its source")
        let sources = found.map {
            rendered.attribute(ChatMarkdownRenderer.mathSource, at: $0.range.location, effectiveRange: nil)
                as? String
        }
        expect(
            sources == ["\\(x^2\\)", "$y$", "$$\\frac{a}{b}$$"],
            "each formula carries its source as written, got \(sources)")
        let plain = rendered.string
        expect(
            plain.contains("At $5 or $10, $\\foo$."),
            "prices and a formula outside the subset read as the reply wrote them")
        let display = found[2].range.location
        let style = rendered.attribute(.paragraphStyle, at: display, effectiveRange: nil) as? NSParagraphStyle
        expect(style?.alignment == .center, "a display formula is centred on its own line")
    }

    static func findSkipsFormulasButLandsAroundThem() {
        let message = ChatMessage(
            role: .assistant, text: "An apple $\\alpha_{apple}$ then apple \\(x\\) apple.")
        let found = ChatFindIndex.occurrences(of: "apple", in: [message])
        expect(found.count == 3, "the formula's source is not searched, got \(found.count)")
        for occurrence in found {
            guard let range = render(message, current: occurrence).current else {
                expect(false, "match \(occurrence.index) is drawn")
                continue
            }
            let rendered = render(message, current: occurrence).string.string as NSString
            expect(
                rendered.substring(with: range).lowercased() == "apple",
                "match \(occurrence.index) lands on its word past the formulas")
        }
    }

    static func formulasTypesetByTheirStructure() {
        guard let engine = MathLayoutEngine(size: 20),
            let fraction = MathFormula(tex: #"\frac{a}{b}"#, source: "", display: true),
            let letter = MathFormula(tex: "a", source: "", display: true),
            let squared = MathFormula(tex: "a^2", source: "", display: false),
            let fenced = MathFormula(
                tex: #"\left( \frac{\frac{a}{b}}{c} \right)"#, source: "", display: true),
            let spaced = MathFormula(tex: "a+b", source: "", display: false),
            let unary = MathFormula(tex: "-b", source: "", display: false)
        else {
            expect(false, "STIX Two Math and the formulas load")
            return
        }
        let a = engine.layout(letter)
        let over = engine.layout(fraction)
        expect(
            over.ascent > a.ascent && over.descent > a.descent, "a fraction stands above and below the line")
        let power = engine.layout(squared)
        expect(power.ascent > a.ascent && power.width > a.width, "a superscript rides up and to the right")
        let parens = engine.layout(fenced)
        expect(parens.height > engine.layout(fraction).height, "\\left( grows to hold what it fences")
        expect(
            engine.layout(spaced).width > engine.layout(unary).width,
            "a binary plus takes medium spaces, a leading minus none")
        expect(
            MathFormula(tex: #"\left( a \\ b \right)"#, source: "", display: true) == nil,
            "a row break inside \\left is refused rather than half-drawn")
    }

    /// Quick AI's narrow column shrinks a long equation rather than letting it run off the edge.
    static func wideFormulasShrinkToTheLine() {
        guard let engine = MathLayoutEngine(size: 20),
            let formula = MathFormula(
                tex: String(repeating: "a + ", count: 40) + "a", source: "", display: true)
        else {
            expect(false, "a long formula typesets")
            return
        }
        let box = engine.layout(formula)
        let cell = MathAttachmentCell(box: box, color: .labelColor, label: "")
        let container = NSTextContainer(size: CGSize(width: 200, height: 1000))
        container.lineFragmentPadding = 0
        let frame = cell.cellFrame(
            for: container, proposedLineFragment: CGRect(x: 0, y: 0, width: 200, height: 20),
            glyphPosition: .zero, characterIndex: 0)
        expect(
            box.width > 200 && abs(frame.width - 200) < 0.5, "the formula fits the line, got \(frame.width)")
        expect(
            abs(frame.height / frame.width - box.height / box.width) < 0.001, "it shrinks without distorting")
    }

    /// Mid-stream, an open display equation is a centred placeholder and an inline one is withheld.
    static func equationsStillArrivingHoldTheirPlace() {
        let text = "An apple \\(y\\) then apple.\n\n$$\n\\frac{apple}{b"
        let streaming = ChatMessage(role: .assistant, text: text, state: .streaming)
        let rendered = render(streaming, current: nil).string
        expect(
            rendered.string.hasSuffix("then apple.\n…") && !rendered.string.contains("frac"),
            "the unfinished equation draws as a placeholder, got \(rendered.string.debugDescription)")
        let dots = (rendered.string as NSString).range(of: "…")
        let style = rendered.attribute(.paragraphStyle, at: dots.location, effectiveRange: nil) as? NSParagraphStyle
        expect(style?.alignment == .center, "the placeholder sits where the equation will, centred")
        let found = ChatFindIndex.occurrences(of: "apple", in: [streaming])
        expect(found.count == 2, "find sees what is drawn mid-stream, got \(found.count)")
        for occurrence in found {
            let drawn = render(streaming, current: occurrence)
            guard let range = drawn.current else {
                expect(false, "match \(occurrence.index) is drawn mid-stream")
                continue
            }
            expect(
                (drawn.string.string as NSString).substring(with: range).lowercased() == "apple",
                "match \(occurrence.index) lands on its word mid-stream")
        }
        let inline = render(
            ChatMessage(role: .assistant, text: "Roots are \\(x = \\frac{1}{", state: .streaming), current: nil)
        expect(inline.string.string == "Roots are ", "an inline equation still arriving is withheld")
    }

    /// A reply is untrusted: one click on a `file:` or app-scheme link must launch nothing.
    static func onlyWebAndMailLinksOpen() {
        let text = """
            [web](https://example.com) [mail](mailto:a@example.com) \
            [file](file:///Applications/Calculator.app) [app](x-apple.systempreferences:security)
            """
        let rendered = render(ChatMessage(role: .assistant, text: text), current: nil).string
        var links: [String] = []
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let url = value as? URL { links.append(url.absoluteString) }
        }
        expect(
            links == ["https://example.com", "mailto:a@example.com"],
            "only web and mail links stay clickable, got \(links)")
    }
}
