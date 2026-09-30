import Foundation

/// How an extension's `open(target, "Cursor")` finds the app it names.
@main
@MainActor
struct ExtensionOpenTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    static let cursor = URL(fileURLWithPath: "/Applications/Cursor.app")
    static let code = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
    static let renamed = URL(fileURLWithPath: "/Applications/Ghostty Nightly.app")
    static let apps = [code, cursor, renamed]
    static let names: [URL: String] = [cursor: "Cursor", code: "Code", renamed: "Ghostty"]

    static func lookup(_ name: String, in list: [URL] = apps) -> URL? {
        ExtensionApplicationLookup.url(named: name, in: list, displayName: { names[$0] })
    }

    static func main() {
        expect(lookup("Cursor") == cursor, "an app is found by its file name")
        expect(lookup("cursor") == cursor, "the name ignores case")
        expect(lookup("Cursor.app") == cursor, "a trailing .app is ignored")
        expect(lookup("  Cursor ") == cursor, "surrounding whitespace is ignored")
        expect(lookup("Visual Studio Code") == code, "a file name with spaces matches")
        expect(lookup("Ghostty") == renamed, "an app is found by its display name")
        expect(lookup("Zed") == nil, "an unknown name finds nothing")
        expect(lookup("") == nil, "a blank name finds nothing")
        expect(lookup(".app") == nil, "a bare extension finds nothing")
        expect(lookup("Cursor", in: []) == nil, "no installed apps finds nothing")

        let shadow = URL(fileURLWithPath: "/Applications/Code.app")
        expect(
            lookup("Code", in: [code, shadow]) == shadow,
            "a file name match wins over an earlier display name match")

        var reads = 0
        _ = ExtensionApplicationLookup.url(named: "Cursor", in: apps) { url in
            reads += 1
            return names[url]
        }
        expect(reads == 0, "a file name match reads no bundle")

        print(failures == 0 ? "\nAll passed" : "\n\(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
