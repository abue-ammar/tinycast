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

        let decoded = LauncherFileFormat.records(from: json) { _ in Record() }
        check(
            "the records read back",
            decoded?.records == ["com.apple.Safari": safari, "com.example.hidden": hidden])
        check("with nothing to report", decoded?.problems == [])

        check("a default record is empty", Record().isEmpty)
        check("a hidden one is not", !hidden.isEmpty)
    }

    private static func testHandEdits() {
        let current = Record(shortcut: "hyper+l", alias: "old", showInLauncher: false)
        let decoded = LauncherFileFormat.records(
            from: .object([
                "lock-screen": .object(["alias": "lock"]),
                "sleep": .object(["shortcut": 5, "alias": true, "showInLauncher": "no"]),
                "log-out": .object(["shortcut": .null, "alias": .null, "showInLauncher": true]),
                "restart": "cmd+r"
            ])) { _ in current }
        check(
            "a field left out keeps its value",
            decoded?.records["lock-screen"]
                == Record(shortcut: "hyper+l", alias: "lock", showInLauncher: false))
        check("a field of the wrong type keeps its value", decoded?.records["sleep"] == current)
        check("null clears", decoded?.records["log-out"] == Record())
        check("a record that isn't an object keeps its value", decoded?.records["restart"] == current)
        check("each mistake is reported", decoded?.problems.count == 4)
        let list = LauncherFileFormat.records(from: .array([])) { _ in Record() }
        check("a list is not an object", list == nil)
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
