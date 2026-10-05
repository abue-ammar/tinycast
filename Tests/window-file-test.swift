// Window management's lists as settings.json spells them: round trips, hand edits, bad records.

import CoreGraphics
import Foundation

@main
@MainActor
struct WindowFileTest {
    static var failures = 0

    static func main() {
        testCommandShortcuts()
        testCommandAliases()
        testCustomSizes()
        testLayouts()
        testRooms()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testCommandShortcuts() {
        let json = WindowManagementFileFormat.json(commandShortcuts: [.leftHalf: "ctrl+option+left"])
        let members = json.members ?? []
        check("every command is listed", members.count == WindowCommand.ID.allCases.count)
        check("in catalog order", members.first?.key == WindowCommand.ID.allCases.first?.rawValue)
        check("a bound one carries its chord", json["left-half"] == "ctrl+option+left")
        check("an unbound one is null", json["right-half"] == .null)

        let decoded = WindowManagementFileFormat.commandShortcuts(from: json)
        check(
            "the list reads back",
            decoded?.texts[.leftHalf] == "ctrl+option+left" && decoded?.texts[.rightHalf] == .some(nil))
        check("with nothing to report", decoded?.problems == [])

        let edited = WindowManagementFileFormat.commandShortcuts(
            from: .object(["left-half": 1, "no-such-command": "cmd+k"]))
        check(
            "a number is not a chord, so that command keeps its own",
            edited?.texts.keys.contains(.leftHalf) == false)
        check("one left out is unbound", edited?.texts[.rightHalf] == .some(nil))
        check("both mistakes are reported", edited?.problems.count == 2)
        check("a list is not an object", WindowManagementFileFormat.commandShortcuts(from: .array([])) == nil)
    }

    private static func testCommandAliases() {
        let json = WindowManagementFileFormat.json(commandAliases: [.leftHalf: "lh"])
        check("only a command with an alias is listed", json.members?.map(\.key) == ["left-half"])

        let decoded = WindowManagementFileFormat.commandAliases(from: json)
        check("the aliases read back", decoded?.texts[.leftHalf] == "lh")

        let edited = WindowManagementFileFormat.commandAliases(from: .object(["left-half": true]))
        check(
            "a flag is not an alias, so the command keeps its own, and is reported",
            edited?.texts.keys.contains(.leftHalf) == false && edited?.problems.count == 1)
    }

    private static func testCustomSizes() {
        let size = CustomWindowSize(
            name: "Reading", width: .init(60, .percent), height: .init(900, .points),
            anchor: .bottomLeft, offset: .init(x: 10, y: -20))
        let json = WindowManagementFileFormat.json(size, shortcut: "hyper+r", alias: "rd")
        check("units are spelled with the number", json["width"] == "60%" && json["height"] == "900pt")
        check("the id is lower case", json["id"] == .string(size.id.uuidString.lowercased()))

        let decoded = WindowManagementFileFormat.customSizes(from: .array([json]))
        check("a custom size round-trips", decoded?.records == [size])
        check("with its shortcut", decoded?.shortcuts == [size.id: "hyper+r"])
        check("and its alias", decoded?.aliases == [size.id: "rd"])

        let handWritten: SettingsFileJSON = .array([
            .object(["name": "Tall", "width": "50 %", "height": 800]),
            .object(["name": "Wide", "width": "wide", "height": "50%"]),
            .object(["name": "Odd", "width": "40%", "height": "40%", "position": "middle"])
        ])
        let first = WindowManagementFileFormat.customSizes(from: handWritten)
        let second = WindowManagementFileFormat.customSizes(from: handWritten)
        check(
            "a size written without an id gets the same one on every read",
            first?.records.first?.id == second?.records.first?.id)
        check(
            "a bare number reads as points, a spaced percent as percent",
            first?.records.first?.width == .init(50, .percent)
                && first?.records.first?.height == .init(800, .points))
        check("a size without a readable width is skipped", first?.records.map(\.name) == ["Tall", "Odd"])
        check(
            "a shortcut or alias left out keeps its value",
            first?.shortcuts.isEmpty == true && first?.aliases.isEmpty == true)
        check(
            "an unknown position falls back to the centre and is reported",
            first?.records.last?.anchor == .center && first?.problems.count == 2)
    }

    private static func testLayouts() {
        let display = WindowLayoutDisplay(uuid: "37D8832A-0000", name: "Built-in")
        let editor = WindowLayoutEntry(
            bundleID: "com.example.editor", argument: "~/Code", display: display,
            widthFraction: 2.0 / 3, heightFraction: 1, anchor: .left, offset: CGPoint(x: 4, y: -2))
        let browser = WindowLayoutEntry(
            bundleID: "com.example.browser", display: display, widthFraction: 1.0 / 3,
            anchor: .right)
        let layout = WindowLayout(
            name: "Coding", iconSymbol: "star", usesPreferredGap: false, entries: [editor, browser],
            frontmostEntryID: browser.id)
        let json = WindowManagementFileFormat.json(layout, shortcut: nil, alias: nil)
        check(
            "an app's display carries its id",
            json["apps"]?.items?.first?["display"]?["id"] == "37D8832A-0000")

        let decoded = WindowManagementFileFormat.layouts(from: .array([json]))
        let read = decoded?.records.first
        check("a layout keeps its id and name", read?.id == layout.id && read?.name == "Coding")
        check(
            "and its icon and gap",
            read?.iconSymbol == "star" && read?.usesPreferredGap == false)
        check(
            "every app keeps its place exactly",
            read?.entries.map(\.bundleID) == ["com.example.editor", "com.example.browser"]
                && read?.entries.first?.widthFraction == 2.0 / 3
                && read?.entries.first?.argument == "~/Code"
                && read?.entries.first?.offset == CGPoint(x: 4, y: -2)
                && read?.entries.last?.anchor == .right)
        check("the frontmost app is the one marked", read?.frontmostEntryID == read?.entries.last?.id)
        check(
            "reading the same text twice yields the same layout",
            WindowManagementFileFormat.layouts(from: .array([json]))?.records == decoded?.records)
        check(
            "null clears the shortcut and the alias",
            decoded?.shortcuts == [layout.id: nil] && decoded?.aliases == [layout.id: nil])

        let broken = WindowManagementFileFormat.layouts(
            from: .array([.object(["name": "Half", "apps": .array([.object(["app": "com.example.a"])])])]))
        check("an app without a display is skipped", broken?.records.first?.entries.isEmpty == true)
        check("and reported", broken?.problems.count == 1)
    }

    private static func testRooms() {
        let window = RoomWindow(
            bundleID: "com.example.notes", appName: "Notes", title: "Draft", windowID: 42,
            unitFrame: CGRect(x: 0, y: 0, width: 0.6, height: 1),
            cell: RoomGrid.Cell(column: 0, columns: 8, row: 0, rows: 12))
        let room = Room(
            name: "Writing", windows: [window], layout: .focus, layoutsByDisplay: ["abc": .columns],
            lastEnteredAt: Date(timeIntervalSince1970: 100))
        let json = WindowManagementFileFormat.json(room, shortcut: "ctrl+option+w", alias: "wr")
        let windowKeys = json["windows"]?.items?.first?.members?.map(\.key) ?? []
        check("a window's number never reaches the file", !windowKeys.contains("windowID"))
        check("nor does when the room was last entered", json["lastEnteredAt"] == nil)

        let decoded = WindowManagementFileFormat.rooms(from: .array([json]))
        var expected = room
        expected.lastEnteredAt = nil
        expected.windows[0].windowID = nil
        check("a room round-trips its configuration", decoded?.records == [expected])
        check(
            "with its shortcut and alias",
            decoded?.shortcuts == [room.id: "ctrl+option+w"] && decoded?.aliases == [room.id: "wr"])

        let edited = WindowManagementFileFormat.rooms(
            from: .array([
                .object(["name": "Later", "layout": "someday", "windows": .array([.object(["app": "a"])])]),
                .object(["windows": .array([])])
            ]))
        check("an unknown layout resets to Auto", edited?.records.first?.layout == .auto)
        check("a room with no name is skipped", edited?.records.count == 1)
        check("both are reported", edited?.problems.count == 2)

        let typed = WindowManagementFileFormat.rooms(from: .array([.object(["name": "Typed", "alias": 3])]))
        check(
            "an alias that isn't text is reported",
            typed?.aliases.isEmpty == true && typed?.problems.count == 1)
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
