import Foundation

@main
@MainActor
struct WebSearchTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        testQueryParsing()
        testURLRedirectDecoding()
        testURLNormalizer()
        testConsensusScoring()
        testHTMLToMarkdownConverter()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func testQueryParsing() {
        let q1 = WebSearchQuery(query: "swift 6 concurrency")
        expect(q1.category == .general, "default category is general")
        expect(q1.searchTerm == "swift 6 concurrency", "search term matches")

        let q2 = WebSearchQuery(query: "steve jobs !w")
        expect(q2.category == .wikipedia, "bang !w selects wikipedia")
        expect(q2.searchTerm == "steve jobs", "bang is removed from search term")

        let q3 = WebSearchQuery(query: "!news apple event")
        expect(q3.category == .news, "bang !news selects news")
        expect(q3.searchTerm == "apple event", "news bang stripped")

        let q4 = WebSearchQuery(query: "site:github.com tinycast")
        expect(q4.siteConstraint == "github.com", "site: extracted")
        expect(q4.searchTerm == "site:github.com tinycast", "site: preserved in query")
    }

    static func testURLRedirectDecoding() {
        let ddgRedirect = "https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Ftarget%3Fparam%3D1&rut=..."
        let decodedDDG = URLRedirectDecoder.decode(ddgRedirect)
        expect(decodedDDG?.absoluteString == "https://example.com/target?param=1", "DDG uddg decoded")

        let aolRedirect = "https://search.aol.com/aol/click/_ylt=.../RU=https%3A%2F%2Fswift.org%2Fabout/RK=2/..."
        let decodedAOL = URLRedirectDecoder.decode(aolRedirect)
        expect(decodedAOL?.absoluteString == "https://swift.org/about", "AOL RU decoded")

        let protoRelative = "//developer.apple.com/documentation"
        let decodedProto = URLRedirectDecoder.decode(protoRelative)
        expect(decodedProto?.absoluteString == "https://developer.apple.com/documentation", "protocol-relative decoded")
    }

    static func testURLNormalizer() {
        let dirtyURL = URL(string: "https://www.example.com/article?utm_source=twitter&utm_medium=social&fbclid=12345&id=42#heading")!
        let cleanURL = URLNormalizer.normalize(dirtyURL)
        expect(cleanURL.absoluteString == "https://example.com/article?id=42", "trackers, www, and fragment stripped")

        let key1 = URLNormalizer.deduplicationKey(for: URL(string: "https://www.example.com/page/")!)
        let key2 = URLNormalizer.deduplicationKey(for: URL(string: "https://example.com/page?utm_source=news")!)
        expect(key1 == key2, "deduplication keys match for canonical URLs")
    }

    static func testConsensusScoring() {
        let urlA = URL(string: "https://example.com/a")!
        let urlB = URL(string: "https://example.com/b")!

        let r1 = WebSearchResult(title: "Page A - DDG", url: urlA, snippet: "Short", engine: .duckDuckGo, rank: 1)
        let r2 = WebSearchResult(title: "Page B - DDG", url: urlB, snippet: "Snippet B", engine: .duckDuckGo, rank: 2)

        let r3 = WebSearchResult(title: "Page A - Brave", url: urlA, snippet: "Longer snippet for page A", engine: .brave, rank: 1)

        let results = ConsensusScorer.score(engineResults: [[r1, r2], [r3]])

        expect(results.count == 2, "deduplicated to 2 results")
        expect(results[0].url.absoluteString == "https://example.com/a", "Page A ranked top due to consensus")
        expect(results[0].score > results[1].score, "consensus score is higher")
        expect(results[0].snippet == "Longer snippet for page A", "picked best snippet")
    }

    static func testHTMLToMarkdownConverter() {
        let html = """
        <html>
        <head><title>Test Page</title><style>.hidden { display: none; }</style></head>
        <body>
        <nav><a href="/home">Home</a></nav>
        <article>
            <h1>Main Title</h1>
            <p>This is a <b>bold</b> paragraph with a <a href="https://example.com">link</a>.</p>
            <p>Here is <code>let x = 10</code> and an entity &amp; &lt; &gt; &#39;.</p>
            <pre><code>func hello() {\n    print("hi")\n}</code></pre>
            <ul>
                <li>Item 1</li>
                <li>Item 2</li>
            </ul>
        </article>
        <footer><p>Copyright 2026</p></footer>
        </body>
        </html>
        """

        let md = HTMLToMarkdownConverter.convert(html: html, maxCharacters: 1000)
        expect(md.contains("# Main Title"), "converted h1")
        expect(md.contains("**bold**"), "converted bold")
        expect(md.contains("[link](https://example.com)"), "converted link")
        expect(md.contains("& < > '"), "decoded entities")
        expect(md.contains("`let x = 10`"), "converted inline code")
        expect(md.contains("```"), "converted code block")
        expect(!md.contains("Copyright 2026"), "stripped footer")
        expect(!md.contains("<style>"), "stripped style")
    }
}
