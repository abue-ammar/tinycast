import Foundation

@main
@MainActor
struct DeepLinkTests {
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

    static func resolve(_ link: String) -> HotKeyAction? {
        URL(string: link).flatMap(EntryDeepLink.action(for:))
    }

    static func roundTrip(_ entryID: String) -> HotKeyAction? {
        EntryDeepLink.url(forEntryID: entryID).flatMap(EntryDeepLink.action(for:))
    }

    static func main() {
        for command in CommandID.allCases {
            if let action = command.hotKeyAction {
                expect(roundTrip(command.rawValue) == action, "\(command.rawValue) round-trips")
            } else {
                expect(
                    EntryDeepLink.url(forEntryID: command.rawValue) == nil,
                    "\(command.rawValue) has no shortcut, so it has no link")
            }
        }
        for action in SystemActionCatalog.all {
            expect(
                roundTrip(action.entryID) == .systemAction(id: action.id),
                "\(action.entryID) round-trips")
        }
        for command in WindowCommandCatalog.all {
            expect(
                roundTrip(command.entryID) == .windowCommand(id: command.id),
                "\(command.entryID) round-trips")
        }

        let id = UUID()
        let uuid = id.uuidString.lowercased()
        let stored: [(String, HotKeyAction)] = [
            (CustomWindowSize.entryIDPrefix + uuid, .customWindowSize(id: id)),
            (WindowLayout.entryIDPrefix + uuid, .windowLayout(id: id)),
            (Room.entryIDPrefix + uuid, .windowRoom(id: id)),
            (CustomQuickAction.entryIDPrefix + uuid, .quickAction(id: id)),
            (CustomCommand.entryIDPrefix + uuid, .customCommand(id: id)),
            (Quicklink.entryIDPrefix + uuid, .quicklink(id: id)),
            (AppleShortcut.entryIDPrefix + uuid, .appleShortcut(id: id)),
        ]
        for (entryID, action) in stored {
            expect(roundTrip(entryID) == action, "\(entryID) round-trips")
        }
        let snippet = "/Users/me/Snippets/Sign off ✍️.md"
        expect(
            roundTrip(StoredSnippet.entryIDPrefix + snippet) == .snippet(id: snippet),
            "a snippet's file path survives percent-encoding")

        expect(
            EntryDeepLink.url(forEntryID: "command:clipboard-history")?.absoluteString
                == "tinycast://command/clipboard-history",
            "a command's link reads as its entry ID")
        expect(
            EntryDeepLink.url(forEntryID: "window-command:left-half")?.absoluteString
                == "tinycast://window-command/left-half",
            "a window command's link reads as its entry ID")
        expect(
            resolve("TINYCAST://Window-Command/left-half") == .windowCommand(id: .leftHalf),
            "scheme and kind are case-insensitive")
        expect(
            resolve("tinycast://quicklink/\(id.uuidString.uppercased())") == .quicklink(id: id),
            "an uppercase UUID still resolves")

        expect(EntryDeepLink.url(forEntryID: "/Applications/Safari.app") == nil, "apps have no link")
        expect(EntryDeepLink.url(forEntryID: "command:nope") == nil, "an unknown command has no link")
        expect(
            EntryDeepLink.url(forEntryID: "extension:demo/search") == nil,
            "extension commands keep their own link")
        expect(
            resolve("raycast://command/clipboard-history") == nil,
            "built-in links are Tinycast's alone")
        expect(
            resolve("tinycast://extensions/demo/search") == nil,
            "extension links fall through to their own router")
        expect(resolve("tinycast://") == nil, "the bare scheme is not a command")
        expect(resolve("tinycast://command") == nil, "a kind without an ID is not a command")
        expect(resolve("tinycast://command/") == nil, "an empty ID is not a command")
        expect(resolve("tinycast://command/nope") == nil, "an unknown command does not resolve")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
