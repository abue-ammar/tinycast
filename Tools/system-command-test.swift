import Foundation

@main
@MainActor
struct SystemCommandTests {
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
        let commands = SystemCommandCatalog.all
        expect(commands.map(\.id) == SystemCommand.ID.allCases, "catalog covers every ID once")
        expect(Set(commands.map(\.id)).count == commands.count, "IDs are unique")
        expect(Set(commands.map(\.entryID)).count == commands.count, "entry IDs are unique")
        expect(Set(commands.map { $0.name.lowercased() }).count == commands.count, "names are unique")
        expect(commands.allSatisfy { !$0.name.isEmpty }, "names are non-empty")
        expect(commands.allSatisfy { !$0.sfSymbol.isEmpty }, "symbols are non-empty")

        for command in commands {
            expect(
                SystemCommandCatalog.command(forEntryID: command.entryID) == command,
                "\(command.id.rawValue) round-trips through its entry ID")
            expect(
                command.entryID.hasPrefix("system-command:"),
                "\(command.id.rawValue) is namespaced")
        }

        let confirmed: Set<SystemCommand.ID> = []
        expect(
            Set(commands.filter { $0.confirmation == .required }.map(\.id)) == confirmed,
            "only the agreed disruptive commands require confirmation")
        expect(
            SystemCommandCatalog.command(forEntryID: "system-command:unknown") == nil,
            "unknown entry IDs are rejected")
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
