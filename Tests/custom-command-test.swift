import Foundation

// Spawns real `/bin/zsh`. The shell-environment cases point `ZDOTDIR` at a throwaway fixture so a run can never read or write the developer's own dotfiles; `/etc/zshrc` is still sourced for interactive shells, so every assertion is relative (the probe resolves with `-i`, not without) rather than absolute.
@main
struct CustomCommandTests {
    @MainActor
    static func main() async {
        let suiteName = "com.tinycast.custom-command-tests"
        let defaults = isolatedDefaults(suiteName)

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
                requiresConfirmation: true, showsConfirmation: true,
                arguments: [CustomCommandArgument(name: "  Query  ", isOptional: true)],
                showsOutput: true)
        ])
        check(
            "import preserves every flag",
            store.commands.first?.loadsShellEnvironment == true
                && store.commands.first?.requiresConfirmation == true
                && store.commands.first?.showsConfirmation == true
                && store.commands.first?.showsOutput == true)
        check(
            "import trims an argument name and keeps its optionality",
            store.commands.first?.arguments == [
                CustomCommandArgument(name: "Query", isOptional: true)
            ])

        store.replace(with: [
            CustomCommand(
                name: "Blanks", command: "/usr/bin/true",
                arguments: [
                    CustomCommandArgument(name: "Kept"), CustomCommandArgument(name: "   ")
                ])
        ])
        check(
            "a blank argument is dropped without losing the command",
            store.commands.first?.arguments == [CustomCommandArgument(name: "Kept")])

        // A command stored before arguments existed must still decode, not vanish with the whole set.
        let legacy = Data(
            """
            [{"id":"\(UUID().uuidString)","name":"Legacy","command":"/usr/bin/true"}]
            """.utf8)
        defaults.set(legacy, forKey: "customCommands")
        check(
            "a record written before arguments existed still loads",
            CustomCommandStore(defaults: defaults).commands.first?.name == "Legacy")

        // MARK: Runner

        let succeeded = await ShellCommandRunner.run("/usr/bin/true")
        check("a zero exit reports success", succeeded.succeeded)

        let inHome = await ShellCommandRunner.run("test \"$PWD\" = \"$HOME\"")
        check("commands start in the user's home directory", inHome.succeeded)

        let marker = await ShellCommandRunner.run("test \"$TINYCAST\" = 1")
        check("the TINYCAST marker is exported so a shell config can detect us", marker.succeeded)

        let failed = await ShellCommandRunner.run("printf 'expected failure' >&2; exit 7")
        check(
            "a non-zero exit reports its status and stderr",
            failed.termination == .exited(status: 7) && failed.standardError == "expected failure")

        // MARK: Streaming output

        /// Drains a streamed run, returning everything it printed and how it ended.
        func collect(_ session: ShellCommandSession) async -> (log: String, result: ShellCommandResult?) {
            var log = ""
            var result: ShellCommandResult?
            for await event in session.events {
                switch event {
                case .output(let text): log += text
                case .finished(let value): result = value
                }
            }
            // A pty ends every line with CR LF, and the trailing newline is never part of the
            // thing under test.
            return (
                log.replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines), result
            )
        }

        let simple = await collect(ShellCommandRunner.stream("echo captured"))
        check("a streamed run reports what it printed", simple.log.contains("captured"))
        check("a streamed run reports a clean exit", simple.result?.succeeded == true)

        // The reported bug: brew writes `==>` to stderr, and it must not be reordered behind stdout.
        let ordered = await collect(
            ShellCommandRunner.stream("printf 'one\\n'; printf 'two\\n' >&2; printf 'three\\n'"))
        let places = ["one", "two", "three"].map { ordered.log.range(of: $0)?.lowerBound }
        check(
            "both streams keep the order they were written in",
            places.allSatisfy { $0 != nil } && places[0]! < places[1]! && places[1]! < places[2]!)

        // A pipe would block-buffer this and deliver it all at exit; a pty must not.
        let live = ShellCommandRunner.stream("echo first; sleep 1; echo second")
        let began = Date()
        var firstOutputAt: TimeInterval?
        for await event in live.events {
            if case .output = event, firstOutputAt == nil {
                firstOutputAt = Date().timeIntervalSince(began)
            }
        }
        check(
            "output arrives while the command is still running",
            (firstOutputAt ?? .greatestFiniteMagnitude) < 0.5)

        let statused = await collect(ShellCommandRunner.stream("exit 7"))
        check(
            "a streamed run reports its exit status",
            statused.result?.termination == .exited(status: 7))

        let multibyte = await collect(
            ShellCommandRunner.stream("printf 'h\u{e9}llo w\u{f6}rld \u{2014} \u{fc}n\u{ef}code\\n'"))
        check(
            "a multi-byte character is never split into a replacement character",
            multibyte.log.contains("h\u{e9}llo w\u{f6}rld \u{2014} \u{fc}n\u{ef}code")
                && !multibyte.log.contains("\u{FFFD}"))

        // Stop must reach the whole chain, not just the shell in front of it.
        let stoppable = ShellCommandRunner.stream("sleep 43 & sleep 44")
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            stoppable.stop()
        }
        let stopped = await collect(stoppable)
        check(
            "a stopped run says so rather than reporting a signal",
            stopped.result?.termination == .stopped)
        try? await Task.sleep(for: .milliseconds(400))
        let survivors = await collect(ShellCommandRunner.stream("pgrep -f 'sleep 4[34]' | wc -l"))
        check(
            "stopping kills the whole command tree, not just the shell",
            survivors.log.trimmingCharacters(in: .whitespacesAndNewlines) == "0")

        // MARK: Working directory

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let atHome = await collect(ShellCommandRunner.stream("pwd"))
        check("a command with no folder starts at home", atHome.log.hasSuffix(home))

        let elsewhere = await collect(
            ShellCommandRunner.stream("pwd", workingDirectory: "/usr/lib"))
        check("a command runs in the folder it names", elsewhere.log.hasSuffix("/usr/lib"))

        let tilde = await collect(ShellCommandRunner.stream("pwd", workingDirectory: "~/"))
        check("a tilde path is expanded", tilde.log.hasSuffix(home))

        // Silently running somewhere else would be worse than not running at all.
        let gone = await collect(
            ShellCommandRunner.stream("pwd", workingDirectory: "/nope/does/not/exist"))
        var reportedMissing = false
        if case .launchFailed(let reason) = gone.result?.termination {
            reportedMissing = reason.contains("no longer exists")
        }
        check("a folder that has gone is reported, not ignored", reportedMissing)

        let notADirectory = await ShellCommandRunner.run("pwd", workingDirectory: "/etc/hosts")
        var rejectedFile = false
        if case .launchFailed = notADirectory.termination { rejectedFile = true }
        check("a file is not accepted as a working folder", rejectedFile)

        // MARK: One-line report

        let spoke = await ShellCommandRunner.run("echo first; echo 'all done'")
        check("the report shows the command's last line", spoke.lastOutputLine == "all done")

        let trailing = await ShellCommandRunner.run("printf 'only line\\n\\n\\n'")
        check("trailing blank lines are skipped", trailing.lastOutputLine == "only line")

        let mute = await ShellCommandRunner.run("true")
        check("a silent command offers no line to report", mute.lastOutputLine == nil)

        // MARK: Icon and folder round-trip

        store.replace(with: [
            CustomCommand(
                name: "Iconned", command: "/usr/bin/true",
                workingDirectory: "  ~/Developer  ", iconSymbol: "  hammer  ")
        ])
        check(
            "an icon and a folder are trimmed and kept",
            store.commands.first?.iconSymbol == "hammer"
                && store.commands.first?.workingDirectory == "~/Developer")

        store.replace(with: [
            CustomCommand(name: "Bare", command: "/usr/bin/true", workingDirectory: "   ")
        ])
        check(
            "a blank folder means home rather than an empty path",
            store.commands.first?.workingDirectory == nil)
        check(
            "a command with no icon falls back to the shared glyph",
            store.commands.first?.symbol == CustomCommand.sfSymbol)

        // MARK: Arguments

        let positional = await collect(
            ShellCommandRunner.stream(
                "test \"$1\" = alpha && test \"$2\" = beta", arguments: ["alpha", "beta"]))
        check("values arrive as positional parameters", positional.result?.succeeded == true)

        // The whole reason values are passed positionally: shell syntax in one is inert.
        let injected = await collect(
            ShellCommandRunner.stream(
                "printf '%s\\n' \"$1\"", arguments: ["; touch /tmp/tinycast-should-not-exist"]))
        check(
            "a value carrying shell syntax is data, not code",
            injected.log.contains("; touch /tmp/tinycast-should-not-exist")
                && !FileManager.default.fileExists(atPath: "/tmp/tinycast-should-not-exist"))

        // MARK: Argument session

        let session = CustomCommandArgumentSession()
        session.begin(
            command: CustomCommand(
                name: "Search", command: "open \"$1$2\"",
                arguments: [
                    CustomCommandArgument(name: "Engine"),
                    CustomCommandArgument(name: "Query", isOptional: true)
                ]))
        check("the form opens on the first argument", session.current?.name == "Engine")
        check("the prompt names the pending argument", session.prompt == "Engine…")
        check("more than one argument left means ↵ advances", !session.isLastArgument)
        check("submitting an incomplete form yields nothing", session.submit("google") == nil)
        check("the form advances to the next argument", session.current?.name == "Query")
        check("one argument left means ↵ runs", session.isLastArgument)
        check(
            "an answered argument shows its value",
            session.progress.map(\.value) == ["google", nil])

        check("backspace hands the previous answer back", session.retreat() == "google")
        check("retreating reopens that argument", session.current?.name == "Engine")
        check("retreating past the first is refused", session.retreat() == nil)

        _ = session.submit("google")
        let completed = session.submit("swift")
        check("the last answer completes the form", completed?.values == ["google", "swift"])
        check("a full form has nothing left pending", session.current == nil)
        check("submitting past the last argument is refused", session.submit("extra") == nil)

        session.cancel()
        check("cancelling ends the session", !session.isActive && session.prompt == nil)

        // MARK: Shell environment

        // A throwaway ZDOTDIR proves interactive mode sources an rc file without depending on the developer's own dotfiles.
        let zdotdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-zdotdir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        try? Data("alias tinycast_probe=true\n".utf8).write(
            to: zdotdir.appendingPathComponent(".zshrc"))
        setenv("ZDOTDIR", zdotdir.path, 1)
        // `/etc/zshrc` sources `/etc/zshrc_$TERM_PROGRAM`, which starts Terminal's session save/restore and writes to the real home.
        unsetenv("TERM_PROGRAM")

        let withEnvironment = await ShellCommandRunner.run(
            "tinycast_probe", loadingShellEnvironment: true)
        check(
            "loading the shell environment resolves an rc-file alias",
            withEnvironment.succeeded)

        // The exact symptom users reported: an alias that only exists in `.zshrc` is command-not-found.
        let withoutEnvironment = await ShellCommandRunner.run("tinycast_probe")
        check(
            "the default shell exits 127 on an rc-file alias",
            withoutEnvironment.termination == .exited(status: 127))

        // The whole "an interactive shell can't block" argument rests on this: a config or command that prompts reads EOF.
        let prompted = await ShellCommandRunner.run(
            "read -r answer", loadingShellEnvironment: true)
        check("a command reading stdin fails instead of hanging", !prompted.succeeded)

        unsetenv("ZDOTDIR")

        try? FileManager.default.removeItem(at: zdotdir)
        discardSuite(suiteName, defaults)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}

/// `removePersistentDomain` only empties the domain; cfprefsd still leaves the plist on disk.
private func discardSuite(_ name: String, _ defaults: UserDefaults) {
    defaults.removePersistentDomain(forName: name)
    UserDefaults.standard.removeSuite(named: name)
    CFPreferencesAppSynchronize(name as CFString)
    try? FileManager.default.removeItem(
        at: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(name).plist"))
}

/// A fixed suite name stops cfprefsd accumulating a plist per run; the domain is cleared at both ends.
private func isolatedDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
