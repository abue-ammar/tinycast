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
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func render(
        _ message: ChatMessage, current: ChatFindOccurrence?, citations: [String: Int] = [:]
    ) -> ChatRenderedText {
        guard case .text(let text)? = message.segments.first else { fatalError("a text segment") }
        return ChatMarkdownRenderer(
            ChatMarkdownSource(
                blocks: MarkdownBlock.parse(text),
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
