import Foundation

// Spawns real `/bin/zsh`. The shell-environment cases point `ZDOTDIR` at a throwaway fixture so a run can never read or write the developer's own dotfiles; `/etc/zshrc` is still sourced for interactive shells, so every assertion is relative (the probe resolves with `-i`, not without) rather than absolute.
@main
struct CustomCommandTests {
    @MainActor
    static func main() async {
        let suiteName = "com.tinycast.custom-command-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("FAIL  could not create an isolated UserDefaults suite")
            exit(1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // MARK: Store

        let store = CustomCommandStore(defaults: defaults)
        let added = try? store.add(
            CustomCommand(
                name: "  Sleep Displays  ", command: "  /usr/bin/pmset displaysleepnow  ",
                requiresConfirmation: true))
        check("add trims the name", added?.name == "Sleep Displays")
        check("add trims the command", added?.command == "/usr/bin/pmset displaysleepnow")
        check("add keeps the flags", added?.requiresConfirmation == true)
        check(
            "the entry id round-trips to the UUID",
            added.map { CustomCommand.id(fromEntryID: $0.entryID) == $0.id } == true)

        guard let added else {
            print("FAIL  add returned nothing; the remaining cases need it")
            exit(1)
        }

        var duplicateRejected = false
        do {
            _ = try store.add(CustomCommand(name: "sleep displays", command: "/usr/bin/true"))
        } catch CustomCommandValidationError.duplicateName {
            duplicateRejected = true
        } catch {}
        check("a name differing only in case is rejected", duplicateRejected)

        try? store.update(
            CustomCommand(
                id: added.id, name: "Sleep Screens", command: "/usr/bin/true",
                loadsShellEnvironment: true))
        check("update keeps the id", store.command(id: added.id) != nil)
        check("update applies the new name", store.command(id: added.id)?.name == "Sleep Screens")
        check(
            "update applies a flag",
            store.command(id: added.id)?.loadsShellEnvironment == true)
        check(
            "update clears a flag left out of the draft",
            store.command(id: added.id)?.requiresConfirmation == false)

        let expected = store.commands
        check(
            "commands survive a reload with their flags",
            CustomCommandStore(defaults: defaults).commands == expected)

        // `replace` runs the import sanitizer, which must carry every flag through.
        store.replace(with: [
            CustomCommand(
                name: "Imported", command: "/usr/bin/true", loadsShellEnvironment: true,
                requiresConfirmation: true, showsConfirmation: true)
        ])
        check(
            "import preserves every flag",
            store.commands.first?.loadsShellEnvironment == true
                && store.commands.first?.requiresConfirmation == true
                && store.commands.first?.showsConfirmation == true)

        // MARK: Runner

        let succeeded = await ShellCommandRunner.run("/usr/bin/true")
        check("a zero exit reports success", succeeded == .success)

        let inHome = await ShellCommandRunner.run("test \"$PWD\" = \"$HOME\"")
        check("commands start in the user's home directory", inHome == .success)

        let marker = await ShellCommandRunner.run("test \"$TINYCAST\" = 1")
        check("the TINYCAST marker is exported so a shell config can detect us", marker == .success)

        let failed = await ShellCommandRunner.run("printf 'expected failure' >&2; exit 7")
        check(
            "a non-zero exit reports its status and stderr",
            failed == .nonZeroExit(status: 7, stderr: "expected failure"))

        // MARK: Shell environment

        // A throwaway ZDOTDIR proves interactive mode sources an rc file without depending on the developer's own dotfiles.
        let zdotdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-zdotdir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: zdotdir) }
        try? Data("alias tinycast_probe=true\n".utf8).write(
            to: zdotdir.appendingPathComponent(".zshrc"))
        setenv("ZDOTDIR", zdotdir.path, 1)
        // `/etc/zshrc` sources `/etc/zshrc_$TERM_PROGRAM`, which starts Terminal's session save/restore and writes to the real home.
        unsetenv("TERM_PROGRAM")

        let withEnvironment = await ShellCommandRunner.run(
            "tinycast_probe", loadingShellEnvironment: true)
        check(
            "loading the shell environment resolves an rc-file alias",
            withEnvironment == .success)

        // The exact symptom users reported: an alias that only exists in `.zshrc` is command-not-found.
        let withoutEnvironment = await ShellCommandRunner.run("tinycast_probe")
        var notFoundStatus: Int32 = 0
        if case .nonZeroExit(let status, _) = withoutEnvironment { notFoundStatus = status }
        check("the default shell exits 127 on an rc-file alias", notFoundStatus == 127)

        // The whole "an interactive shell can't block" argument rests on this: a config or command that prompts reads EOF.
        let prompted = await ShellCommandRunner.run(
            "read -r answer", loadingShellEnvironment: true)
        check("a command reading stdin fails instead of hanging", prompted != .success)

        unsetenv("ZDOTDIR")

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
