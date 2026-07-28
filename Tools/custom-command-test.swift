import Foundation

@main
struct CustomCommandTests {
    static func main() async throws {
        let suiteName = "com.tinycast.custom-command-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = try await MainActor.run {
            let store = CustomCommandStore(defaults: defaults)
            let command = try store.add(
                name: "  Sleep Displays  ", command: "  /usr/bin/pmset displaysleepnow  ")
            precondition(command.name == "Sleep Displays")
            precondition(command.command == "/usr/bin/pmset displaysleepnow")
            precondition(CustomCommand.id(fromEntryID: command.entryID) == command.id)

            do {
                _ = try store.add(name: "sleep displays", command: "/usr/bin/true")
                preconditionFailure("Duplicate names must be rejected")
            } catch CustomCommandValidationError.duplicateName {
                // Expected.
            }

            try store.update(id: command.id, name: "Sleep Screens", command: "/usr/bin/true")
            precondition(store.command(id: command.id)?.name == "Sleep Screens")
            return store.command(id: command.id)!
        }

        await MainActor.run {
            let reloaded = CustomCommandStore(defaults: defaults)
            precondition(reloaded.commands == [original])
        }

        let success = await ShellCommandRunner.run("/usr/bin/true")
        precondition(success == .success)
        let homeDirectory = await ShellCommandRunner.run("test \"$PWD\" = \"$HOME\"")
        precondition(
            homeDirectory == .success,
            "Commands must start in the user's home directory")

        let failure = await ShellCommandRunner.run("printf 'expected failure' >&2; exit 7")
        guard case .nonZeroExit(let status, let stderr) = failure else {
            preconditionFailure("Expected a non-zero outcome")
        }
        precondition(status == 7)
        precondition(stderr == "expected failure")

        print("All custom command tests passed")
    }
}
