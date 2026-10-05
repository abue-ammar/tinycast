// Launcher items as settings.json spells them: round trips, missing fields, bad records.

import Foundation

@main
@MainActor
struct LauncherFileTest {
    static var failures = 0

    static func main() {
        testRoundTrip()
        testHandEdits()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private typealias Record = LauncherFileFormat.Record

    private static func testRoundTrip() {
        let safari = Record(shortcut: "hyper+s", alias: "web", showInLauncher: true)
        let hidden = Record(shortcut: nil, alias: nil, showInLauncher: false)
        let json = LauncherFileFormat.json([("com.apple.Safari", safari), ("com.example.hidden", hidden)])
        check(
            "records keep the order given",
            json.members?.map(\.key) == ["com.apple.Safari", "com.example.hidden"])
        check(
            "every field is written, none as null",
            json["com.example.hidden"]?.members?.map(\.key) == ["shortcut", "alias", "showInLauncher"]
                && json["com.example.hidden"]?["shortcut"] == .null)

        let decoded = LauncherFileFormat.records(from: json)
        check(
            "the records read back",
            decoded?.records == ["com.apple.Safari": safari, "com.example.hidden": hidden])
        check("with nothing to report", decoded?.problems == [])

        check("a default record is empty", Record().isEmpty)
        check("a hidden one is not", !hidden.isEmpty)
    }

    private static func testHandEdits() {
        let decoded = LauncherFileFormat.records(
            from: .object([
                "lock-screen": .object(["alias": "lock"]),
                "sleep": .object(["shortcut": 5, "showInLauncher": "no"]),
                "restart": "cmd+r"
            ]))
        check(
            "a field left out reads as none, or as shown",
            decoded?.records["lock-screen"] == Record(shortcut: nil, alias: "lock", showInLauncher: true))
        check("a wrong type keeps the default", decoded?.records["sleep"] == Record())
        check("a record that isn't an object is skipped", decoded?.records["restart"] == nil)
        check("each mistake is reported", decoded?.problems.count == 3)
        check("a list is not an object", LauncherFileFormat.records(from: .array([])) == nil)
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}
