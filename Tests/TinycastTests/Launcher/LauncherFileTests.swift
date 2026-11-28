import Testing

@testable import Tinycast

@MainActor
struct LauncherFileTests {
    private typealias Record = LauncherFileFormat.Record

    @Test func writingPreservesRecordOrderAndIncludesEveryField() throws {
        let safari = Record(shortcut: "hyper+s", alias: "web", showInLauncher: true)
        let hidden = Record(shortcut: nil, alias: nil, showInLauncher: false)
        let json = LauncherFileFormat.json([("com.apple.Safari", safari), ("com.example.hidden", hidden)])
        let entries = try #require(json.members)
        #expect(entries.map(\.key) == ["com.apple.Safari", "com.example.hidden"])
        let hiddenJSON = try #require(json["com.example.hidden"])
        let fields = try #require(hiddenJSON.members)
        #expect(fields.map(\.key) == ["shortcut", "alias", "showInLauncher"])
        #expect(hiddenJSON["shortcut"] == .null)

        let decoded = try #require(LauncherFileFormat.records(from: json) { _ in Record() })
        #expect(decoded.records == ["com.apple.Safari": safari, "com.example.hidden": hidden])
        #expect(decoded.problems.isEmpty)
    }

    @Test func onlyTheDefaultRecordIsEmpty() {
        #expect(Record().isEmpty)
        #expect(!Record(shortcut: nil, alias: nil, showInLauncher: false).isEmpty)
    }

    @Test func handEditsKeepOmissionsAndInvalidValuesAndReportEachError() throws {
        let current = Record(shortcut: "hyper+l", alias: "old", showInLauncher: false)
        let decoded = try #require(LauncherFileFormat.records(
            from: .object([
                "lock-screen": .object(["alias": "lock"]),
                "sleep": .object(["shortcut": 5, "alias": true, "showInLauncher": "no"]),
                "log-out": .object(["shortcut": .null, "alias": .null, "showInLauncher": true]),
                "restart": "cmd+r"
            ])
        ) { _ in current })

        #expect(decoded.records["lock-screen"] == Record(shortcut: "hyper+l", alias: "lock", showInLauncher: false))
        #expect(decoded.records["sleep"] == current)
        #expect(decoded.records["log-out"] == Record())
        #expect(decoded.records["restart"] == current)
        #expect(decoded.problems.count == 4)
    }

    @Test func aListCannotBeDecodedAsRecords() {
        #expect(LauncherFileFormat.records(from: .array([])) { _ in Record() } == nil)
    }
}
