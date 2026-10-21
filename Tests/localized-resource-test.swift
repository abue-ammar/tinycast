import Foundation

/// Pins what `LocalizedStringResource.resolved()` returns, and that it stays off the slow path.
///
/// The bug it guards (issue #1667) is invisible in English: `String(localized:)` on a *resource*
/// re-reads the string table on every call, and the table's size is what sets the cost, so only a
/// translated build shows it. The semantic checks run anywhere. The performance check runs only
/// when the harness finds itself inside a built app that carries translations — copy the binary
/// into `Tinycast Dev.app/Contents/MacOS/` and run it with `-AppleLanguages '(zh-Hans)'` to see
/// the real cost.
@main
struct LocalizedResourceTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // Semantics, on keys this bundle may or may not carry.
        let absent = LocalizedStringResource(
            "tinycast-harness-absent-key", defaultValue: "Harness Fallback")
        check(
            "an absent key falls back to its default",
            absent.resolved() == "Harness Fallback")
        check(
            "an absent key with no default stays the key",
            LocalizedStringResource(stringLiteral: "tinycast-harness-absent-key").resolved()
                == "tinycast-harness-absent-key")

        // A key the app ships. Its expectation depends on whether this bundle carries the catalog,
        // so compare against the slow path rather than a hard-coded string.
        let present: LocalizedStringResource = "Cancel"
        check("a shipped key resolves like the slow path", present.resolved() == String(localized: present))
        check(
            "a format key resolves like the slow path",
            {
                let format: LocalizedStringResource = "%@ at %@"
                return format.resolved() == String(localized: format)
            }())

        // The regression itself. `String(localized:)` on a resource costs milliseconds per call once
        // a translated table is in play and microseconds otherwise; `resolved()` stays in the
        // microseconds in both cases, so the ceiling only bites where the bug would.
        let translated =
            Bundle.main.localizations.contains { $0 != "en" }
            && Bundle.main.path(forResource: Bundle.main.preferredLocalizations.first, ofType: "lproj")
                .map { FileManager.default.fileExists(atPath: $0 + "/Localizable.strings") } ?? false
        let iterations = 200
        func microseconds(_ resource: LocalizedStringResource) -> Double {
            _ = resource.resolved()
            let start = Date()
            for _ in 0..<iterations { _ = resource.resolved() }
            return Date().timeIntervalSince(start) * 1_000_000 / Double(iterations)
        }
        let fixed = microseconds(present)
        print(
            String(
                format: "      resolved(): %.2f µs/call (translations present: %@)",
                fixed, translated ? "yes" : "no"))
        check("resolving stays on the cached path (< 50 µs/call)", fixed < 50)

        if translated {
            // What the bug cost, measured the same way, so the gap is on the record.
            let start = Date()
            for _ in 0..<20 { _ = String(localized: present) }
            let slow = Date().timeIntervalSince(start) * 1_000_000 / 20
            print(String(format: "      String(localized:) on the same resource: %.1f µs/call", slow))
        }

        if failures > 0 {
            print("\n\(failures) failure(s)")
            exit(1)
        }
        print("\nall checks passed")
    }
}
