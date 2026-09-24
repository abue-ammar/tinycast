import Foundation

/// The size a Detail markdown image asks for through its URL's query.
@main
@MainActor
struct ExtensionImageSizeTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    static func hint(_ text: String) -> ExtensionImageSize? {
        ExtensionImageSize(url: URL(string: text)!)
    }

    static func main() {
        expect(hint("https://example.com/cover.jpg") == nil, "no query asks for no size")
        expect(hint("https://example.com/cover.jpg?v=2") == nil, "an unrelated query asks for no size")
        expect(
            hint("https://example.com/cover.jpg?raycast-width=120&raycast-height=180")
                == ExtensionImageSize(width: 120, height: 180),
            "both hints are read")
        expect(
            hint("https://example.com/cover.jpg?v=2&raycast-height=90")
                == ExtensionImageSize(width: nil, height: 90),
            "one hint among other parameters is read on its own")
        expect(
            hint("https://example.com/a.png?raycast-width=12.5")
                == ExtensionImageSize(width: 12.5, height: nil),
            "a fractional size is kept")
        expect(
            hint("https://example.com/a.png?raycast-width=0&raycast-height=-4") == nil,
            "a zero or negative size is ignored")
        expect(
            hint("https://example.com/a.png?raycast-width=wide&raycast-height=nan") == nil,
            "a size that is not a finite number is ignored")
        expect(
            hint("data:image/svg+xml;base64,PHN2Zy8+?raycast-width=48")
                == ExtensionImageSize(width: 48, height: nil),
            "an inline image's hint after its payload is read")
        expect(
            hint("data:image/png;base64,AAAA") == nil,
            "an inline image with no query asks for no size")

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("All image size checks passed")
    }
}
