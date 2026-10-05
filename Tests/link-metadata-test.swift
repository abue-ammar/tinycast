// Standalone test for Open Graph link metadata parsing and URL resolution.
import Foundation

@main
@MainActor
struct LinkMetadataTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        directImageURLDetection()
        standardOpenGraphExtraction()
        metadataExtractionWithTitleAndDescription()
        htmlTitleFallback()
        descriptionFallbacks()
        invertedAttributeOrder()
        singleQuoteAttributes()
        twitterCardFallback()
        htmlEntityDecoding()
        relativeURLResolution()
        commentedTagsIgnored()
        nonHttpSchemesRejected()
        clipboardItemWebURL()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func directImageURLDetection() {
        expect(
            LinkMetadataParser.isDirectImageURL(URL(string: "https://example.com/avatar.png")!),
            "png is direct image")
        expect(
            LinkMetadataParser.isDirectImageURL(URL(string: "https://example.com/photo.JPG")!),
            "uppercase JPG is direct image")
        expect(
            LinkMetadataParser.isDirectImageURL(URL(string: "https://example.com/pic.webp?w=200")!),
            "webp with query is direct image")
        expect(
            !LinkMetadataParser.isDirectImageURL(URL(string: "https://example.com/article.html")!),
            "html is not direct image")
        expect(
            !LinkMetadataParser.isDirectImageURL(URL(string: "https://example.com/swift")!),
            "extensionless web path is not direct image")
    }

    static func standardOpenGraphExtraction() {
        let base = URL(string: "https://example.com/blog/article")!
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Blog Post</title>
                <meta property="og:title" content="Test Title" />
                <meta property="og:image" content="https://cdn.example.com/hero.jpg" />
            </head>
            <body>Content</body>
            </html>
            """
        let extracted = LinkMetadataParser.extractOGImageURL(from: html, baseURL: base)
        expect(extracted == URL(string: "https://cdn.example.com/hero.jpg"), "extracts standard og:image")
    }

    static func metadataExtractionWithTitleAndDescription() {
        let base = URL(string: "https://github.com/swiftlang/swift")!
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Swift Programming Language</title>
                <meta property="og:title" content="Swift &amp; Friends" />
                <meta property="og:description" content="The Swift Programming Language repo" />
                <meta property="og:image" content="https://github.com/og.png" />
            </head>
            </html>
            """
        let meta = LinkMetadataParser.extractMetadata(from: html, baseURL: base)
        expect(meta.title == "Swift & Friends", "og:title parsed and decoded")
        expect(meta.description == "The Swift Programming Language repo", "og:description parsed")
        expect(meta.imageURL == URL(string: "https://github.com/og.png"), "og:image parsed")
    }

    static func htmlTitleFallback() {
        let base = URL(string: "https://example.com/docs")!
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>
                    Documentation &amp; Guides
                </title>
            </head>
            </html>
            """
        let meta = LinkMetadataParser.extractMetadata(from: html, baseURL: base)
        expect(meta.title == "Documentation & Guides", "falls back to normalized <title>")
        expect(meta.description == nil, "no description when not provided")
        expect(meta.imageURL == nil, "no image when not provided")
    }

    static func descriptionFallbacks() {
        let base = URL(string: "https://example.com/page")!
        let htmlTwitter = """
            <head>
                <meta name="twitter:description" content="Twitter card description" />
            </head>
            """
        let metaTwitter = LinkMetadataParser.extractMetadata(from: htmlTwitter, baseURL: base)
        expect(metaTwitter.description == "Twitter card description", "falls back to twitter:description")

        let htmlStandard = """
            <head>
                <meta name="description" content="Standard meta description" />
            </head>
            """
        let metaStandard = LinkMetadataParser.extractMetadata(from: htmlStandard, baseURL: base)
        expect(metaStandard.description == "Standard meta description", "falls back to meta name=description")
    }

    static func invertedAttributeOrder() {
        let base = URL(string: "https://example.com/page")!
        let html = """
            <head>
                <meta content="https://cdn.example.com/inverted.png" property="og:image">
            </head>
            """
        let extracted = LinkMetadataParser.extractOGImageURL(from: html, baseURL: base)
        expect(extracted == URL(string: "https://cdn.example.com/inverted.png"), "extracts content before property")
    }

    static func singleQuoteAttributes() {
        let base = URL(string: "https://example.com/page")!
        let html = "<meta property='og:image' content='https://cdn.example.com/single.png'>"
        let extracted = LinkMetadataParser.extractOGImageURL(from: html, baseURL: base)
        expect(extracted == URL(string: "https://cdn.example.com/single.png"), "extracts single-quoted attributes")
    }

    static func twitterCardFallback() {
        let base = URL(string: "https://example.com/page")!
        let html = """
            <head>
                <meta name="twitter:card" content="summary_large_image">
                <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
            </head>
            """
        let extracted = LinkMetadataParser.extractOGImageURL(from: html, baseURL: base)
        expect(extracted == URL(string: "https://cdn.example.com/twitter.jpg"), "falls back to twitter:image")
    }

    static func htmlEntityDecoding() {
        let base = URL(string: "https://example.com/page")!
        let html = """
            <meta property="og:image" content="https://cdn.example.com/img?w=1200&amp;h=630&amp;v=1" />
            """
        let extracted = LinkMetadataParser.extractOGImageURL(from: html, baseURL: base)
        expect(
            extracted == URL(string: "https://cdn.example.com/img?w=1200&h=630&v=1"),
            "decodes &amp; in image URL query parameters")
    }

    static func relativeURLResolution() {
        let base = URL(string: "https://example.com/subfolder/page.html")!

        let rootRelative = "<meta property=\"og:image\" content=\"/static/og.png\">"
        expect(
            LinkMetadataParser.extractOGImageURL(from: rootRelative, baseURL: base)
                == URL(string: "https://example.com/static/og.png"),
            "resolves root-relative path")

        let pathRelative = "<meta property=\"og:image\" content=\"images/thumb.png\">"
        expect(
            LinkMetadataParser.extractOGImageURL(from: pathRelative, baseURL: base)
                == URL(string: "https://example.com/subfolder/images/thumb.png"),
            "resolves path-relative path")

        let protocolRelative = "<meta property=\"og:image\" content=\"//assets.example.com/banner.jpg\">"
        expect(
            LinkMetadataParser.extractOGImageURL(from: protocolRelative, baseURL: base)
                == URL(string: "https://assets.example.com/banner.jpg"),
            "resolves protocol-relative URL")
    }

    static func commentedTagsIgnored() {
        let base = URL(string: "https://example.com")!
        let html = """
            <head>
                <!-- <meta property="og:image" content="https://example.com/old.png"> -->
                <meta property="og:image" content="https://example.com/new.png">
            </head>
            """
        let extracted = LinkMetadataParser.extractOGImageURL(from: html, baseURL: base)
        expect(extracted == URL(string: "https://example.com/new.png"), "ignores commented-out meta tags")
    }

    static func nonHttpSchemesRejected() {
        let base = URL(string: "https://example.com")!
        let html = "<meta property=\"og:image\" content=\"javascript:alert(1)\">"
        let extracted = LinkMetadataParser.extractOGImageURL(from: html, baseURL: base)
        expect(extracted == nil, "rejects non-http javascript: schemes")
    }

    static func clipboardItemWebURL() {
        let now = Date()
        let linkItem = ClipboardItem(
            id: UUID(), kind: .text, text: "https://github.com/swiftlang/swift",
            imagePath: nil, createdAt: now, sourceBundleID: nil, pinnedAt: nil)
        expect(
            linkItem.webURL == URL(string: "https://github.com/swiftlang/swift"),
            "ClipboardItem.webURL extracts valid web link")

        let bareHostItem = ClipboardItem(
            id: UUID(), kind: .text, text: "apple.com/mac",
            imagePath: nil, createdAt: now, sourceBundleID: nil, pinnedAt: nil)
        expect(
            bareHostItem.webURL == URL(string: "https://apple.com/mac"),
            "ClipboardItem.webURL adds https to bare host")

        let textItem = ClipboardItem(
            id: UUID(), kind: .text, text: "Hello world and welcome",
            imagePath: nil, createdAt: now, sourceBundleID: nil, pinnedAt: nil)
        expect(textItem.webURL == nil, "plain text has no webURL")
    }
}
