import Foundation

@main
@MainActor
struct SystemActionTests {
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
        let actions = SystemActionCatalog.all
        expect(actions.count == 31, "catalog contains all 31 agreed actions")
        expect(actions.map(\.id) == SystemAction.ID.allCases, "catalog covers every ID once")
        expect(Set(actions.map { $0.name.lowercased() }).count == actions.count, "names are unique")
        expect(actions.allSatisfy { !$0.name.isEmpty }, "names are non-empty")
        expect(actions.allSatisfy { !$0.sfSymbol.isEmpty }, "symbols are non-empty")

        for action in actions {
            expect(
                SystemActionCatalog.action(forEntryID: action.entryID) == action,
                "\(action.id.rawValue) round-trips through its entry ID")
            expect(
                action.entryID == "system-action:" + action.id.rawValue,
                "\(action.id.rawValue) is namespaced")
        }

        let confirmed: Set<SystemAction.ID> = [
            .restart, .shutDown, .logOut, .emptyTrash, .quitAllApps
        ]
        expect(
            Set(actions.filter { $0.confirmation != .none }.map(\.id)) == confirmed,
            "only the agreed disruptive actions require confirmation")
        for action in actions {
            guard case .required(let title, let message) = action.confirmation else { continue }
            expect(
                !title.isEmpty && !message.isEmpty,
                "\(action.id.rawValue) carries confirmation copy")
        }
        expect(
            SystemActionCatalog.action(id: .quitAllApps).confirmation == .computed,
            "Quit All builds its own copy from the target count")
        expect(
            SystemActionCatalog.all.allSatisfy { SystemActionCatalog.action(id: $0.id) == $0 },
            "every action round-trips through its ID")
        expect(
            SystemActionCatalog.action(forEntryID: "system-action:unknown") == nil,
            "unknown entry IDs are rejected")
        expect(
            !actions.contains { $0.id.rawValue == "quit-all-apps-except-frontmost" },
            "Quit All Except Frontmost remains out of scope")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
