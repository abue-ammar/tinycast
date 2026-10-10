import Foundation

// Spawns real `/bin/zsh`; `ZDOTDIR` is a fixture, so every assertion is relative.
@main
struct CustomCommandTests {
    @MainActor
    static func main() async {
        // The app has no controlling terminal; an inherited one gets `zsh -i` stopped by SIGTTOU.
        setsid()
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

        // MARK: Editor

        let editor = CustomCommandEditorSession(command: nil)
        check("a new editor starts on its name", editor.focusedField == .name)
        check("an empty editor cannot save", !editor.canSave)
        check(
            "a new editor preserves command defaults",
            editor.draft().isEnabled && editor.draft().showsInRootSearch
                && !editor.loadsShellEnvironment && !editor.requiresConfirmation
                && !editor.showsConfirmation && !editor.showsOutput && editor.arguments.isEmpty
                && editor.workingDirectory.isEmpty && editor.iconSymbol == nil)
        editor.name = "   "
        editor.shellCommand = "/usr/bin/true"
        check("a whitespace-only name cannot save", !editor.canSave)
        editor.name = "Test Command"
        editor.shellCommand = "\n "
        check("a whitespace-only script cannot save", !editor.canSave)
        editor.shellCommand = "/usr/bin/true"
        check("a named nonempty script can save", editor.canSave)
        editor.advanceFocus(backwards: true)
        check("Shift-Tab wraps to the last option", editor.focusedField == .output)
        editor.advanceFocus(backwards: false)
        check("Tab wraps back to the name", editor.focusedField == .name)
        for _ in 0..<CustomCommandArgument.limit { editor.addArgument() }
        let argumentIDs = editor.arguments.map(\.id)
        check("adding an argument focuses its name", editor.focusedField == .argumentName(argumentIDs[2]))
        editor.addArgument()
        check("the editor enforces the argument cap", editor.arguments.map(\.id) == argumentIDs)
        check("Tab skips Add at the argument cap", !editor.focusOrder.contains(.addArgument))
        editor.focusedField = .removeArgument(argumentIDs[1])
        editor.removeArgument(id: argumentIDs[1])
        check(
            "removal keeps the neighboring argument identities",
            editor.arguments.map(\.id)
                == [argumentIDs[0], argumentIDs[2]])
        check(
            "removing a focused argument focuses its successor",
            editor.focusedField == .argumentName(argumentIDs[2]))
        check("removal restores Add to the focus order", editor.focusOrder.contains(.addArgument))
        editor.removeArgument(id: argumentIDs[2])
        editor.removeArgument(id: argumentIDs[0])
        check("removing the last argument focuses Add", editor.focusedField == .addArgument)
        let source = CustomCommand(
            name: "Original", command: "printf '%s' \"$1\"", isEnabled: false,
            showsInRootSearch: false,
            loadsShellEnvironment: true, requiresConfirmation: true, showsConfirmation: true,
            arguments: [CustomCommandArgument(name: "Query", isOptional: true)], showsOutput: true,
            workingDirectory: "~/Documents", iconSymbol: "hammer")
        let editing = CustomCommandEditorSession(command: source)
        check("editing carries every existing field", editing.draft() == source)
        editing.focusedField = .rootSearch
        editing.advanceFocus(backwards: false)
        check(
            "Tab includes root-search visibility before execution options",
            editing.focusedField == .shellEnvironment)
        editing.name = "Renamed"
        editing.shellCommand = "/usr/bin/true"
        check(
            "editing preserves the UUID and enabled flag",
            editing.draft().id == source.id
                && !editing.draft().isEnabled)

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

        check("a new command is enabled", store.command(id: added.id)?.isEnabled == true)
        store.setEnabled(false, id: added.id)
        check("disabling is stored", store.command(id: added.id)?.isEnabled == false)
        check("disabled commands are absent from the browser", store.matching("").isEmpty)
        check(
            "disabling keeps every other field intact",
            store.command(id: added.id)?.command == "/usr/bin/true")
        store.setEnabled(true, id: added.id)

        check("a new command shows in root search", store.command(id: added.id)?.showsInRootSearch == true)
        store.setShowsInRootSearch(false, id: added.id)
        check("the browser includes root-hidden commands", store.matching("").map(\.id) == [added.id])
        check(
            "browser search ignores case and outer whitespace",
            store.matching("  SCREENS\n").map(\.id) == [added.id])
        check("browser search never matches script content", store.matching("/usr/bin/true").isEmpty)
        check("unmatched browser search returns no rows", store.matching("No such command").isEmpty)
        check(
            "hiding from root search is stored and leaves it enabled",
            store.command(id: added.id)?.showsInRootSearch == false
                && store.command(id: added.id)?.isEnabled == true)

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

        // A command stored before arguments existed must still decode.
        let legacy = Data(
            """
            [{"id":"\(UUID().uuidString)","name":"Legacy","command":"/usr/bin/true"}]
            """.utf8)
        defaults.set(legacy, forKey: "customCommands")
        check(
            "a record written before arguments existed still loads",
            CustomCommandStore(defaults: defaults).commands.first?.name == "Legacy")
        check(
            "a record written before the enabled flag loads as enabled",
            CustomCommandStore(defaults: defaults).commands.first?.isEnabled == true)
        check(
            "a record written before the root-search flag still shows there",
            CustomCommandStore(defaults: defaults).commands.first?.showsInRootSearch == true)

        // MARK: Batch add

        var commits = 0
        store.onChange = { _ in commits += 1 }
        let batched = store.add(contentsOf: [
            CustomCommand(name: "One", command: "/usr/bin/true"),
            CustomCommand(name: "blanks", command: "/usr/bin/true"),
            CustomCommand(name: "Two", command: "/usr/bin/true"),
            CustomCommand(name: "one", command: "/usr/bin/false")
        ])
        store.onChange = nil
        check("a batch add counts only the commands it added", batched == 2)
        check("a whole batch is one commit", commits == 1)
        check(
            "a name colliding with the library or with the batch is dropped",
            store.commands.map(\.name) == ["Blanks", "One", "Two"])

        // MARK: Raycast script import

        let shellSource = """
            #!/bin/bash

            # Required parameters:
            # @raycast.schemaVersion 1
            # @raycast.title Chrome CDP
            # @raycast.mode silent

            # Optional parameters:
            # @raycast.icon 📘
            # @raycast.needsConfirmation false

            CDP_PORT=9222
            # @raycast.mode fullOutput
            """
        let shellScript = RaycastScriptImport.command(
            at: URL(fileURLWithPath: "/Users/me/scripts/chrome cdp.sh"), source: shellSource)
        check("the title becomes the command name", shellScript?.name == "Chrome CDP")
        check(
            "the shebang names the interpreter and the path is one quoted word",
            shellScript?.command == #"/bin/bash '/Users/me/scripts/chrome cdp.sh' "$@""#)
        check("silent mode opens no output window", shellScript?.showsOutput == false)
        check("needsConfirmation false stays off", shellScript?.requiresConfirmation == false)
        check(
            "a script runs in its own folder",
            shellScript?.workingDirectory == "/Users/me/scripts")

        let appleSource = """
            #!/usr/bin/osascript

            # @raycast.schemaVersion 1
            # @raycast.title Facebook
            # @raycast.mode fullOutput
            # @raycast.needsConfirmation true
            # @raycast.currentDirectoryPath ~/Sites
            # @raycast.argument1 { "type": "text", "placeholder": "Profile" }
            # @raycast.argument2 { "type": "text", "placeholder": "Tab", "optional": true }

            tell application id "com.vivaldi.Vivaldi"
            """
        let appleScript = RaycastScriptImport.command(
            at: URL(fileURLWithPath: "/tmp/facebook.applescript"), source: appleSource)
        check(
            "osascript comes from the shebang",
            appleScript?.command == #"/usr/bin/osascript '/tmp/facebook.applescript' "$@""#)
        check("an output mode opens the window", appleScript?.showsOutput == true)
        check("needsConfirmation true is carried over", appleScript?.requiresConfirmation == true)
        check(
            "a declared directory wins over the script's folder",
            appleScript?.workingDirectory == "~/Sites")
        check(
            "arguments come from their placeholders, in order",
            appleScript?.arguments == [
                CustomCommandArgument(name: "Profile"),
                CustomCommandArgument(name: "Tab", isOptional: true)
            ])

        check(
            "a file naming no interpreter is not a script command",
            RaycastScriptImport.command(
                at: URL(fileURLWithPath: "/tmp/notes.txt"), source: "# @raycast.title Notes\n")
                == nil)
        check(
            "a script declaring no title is not a script command",
            RaycastScriptImport.command(
                at: URL(fileURLWithPath: "/tmp/helper.sh"),
                source: "#!/bin/bash\n# @raycast.schemaVersion 1\necho hi\n") == nil)
        check(
            "the JavaScript template's // directives are read too",
            RaycastScriptImport.command(
                at: URL(fileURLWithPath: "/tmp/x.js"),
                source: "#!/usr/bin/env node\n// @raycast.title Node\n")?.command
                == #"/usr/bin/env node '/tmp/x.js' "$@""#)
        check(
            "a quote in the path cannot break out of the argument",
            RaycastScriptImport.command(
                at: URL(fileURLWithPath: "/tmp/it's here.sh"),
                source: "#!/bin/zsh\n# @raycast.title Quoted\n")?.command
                == #"/bin/zsh '/tmp/it'\''s here.sh' "$@""#)

        let scriptDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-scripts-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: scriptDirectory.appendingPathComponent("nested"), withIntermediateDirectories: true)
        for (name, source) in [
            ("b-second.sh", "#!/bin/bash\n# @raycast.title Second\n"),
            ("a-first.sh", "#!/bin/bash\n# @raycast.title First\n"),
            ("plain.txt", "just notes\n"),
            (".hidden.sh", "#!/bin/bash\n# @raycast.title Hidden\n")
        ] {
            try? Data(source.utf8).write(to: scriptDirectory.appendingPathComponent(name))
        }
        check(
            "a folder yields its script commands in name order and nothing else",
            RaycastScriptImport.scan(directory: scriptDirectory).map(\.name) == ["First", "Second"])

        // Linked scripts import, keeping the link's path so the command follows its target.
        let linkTarget = scriptDirectory.appendingPathComponent("nested/linked.sh")
        try? Data("#!/bin/bash\n# @raycast.title Linked\nprintf '%s' 'linked-target-ran'\n".utf8)
            .write(to: linkTarget)
        let link = scriptDirectory.appendingPathComponent("c-linked.sh")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: linkTarget)
        // Checked, or a link that was never made would pass "doesn't import" for free.
        let skippedLinksMade =
            (try? FileManager.default.createSymbolicLink(
                at: scriptDirectory.appendingPathComponent("d-dangling.sh"),
                withDestinationURL: scriptDirectory.appendingPathComponent("missing.sh"))) != nil
            && (try? FileManager.default.createSymbolicLink(
                at: scriptDirectory.appendingPathComponent("e-folder"),
                withDestinationURL: scriptDirectory.appendingPathComponent("nested"))) != nil
        check("the dangling and folder links exist", skippedLinksMade)
        let withLinks = RaycastScriptImport.scan(directory: scriptDirectory)
        check(
            "a linked script imports; a dangling or folder link doesn't",
            withLinks.map(\.name) == ["First", "Second", "Linked"])
        let linked = withLinks.first { $0.name == "Linked" }
        check("a linked script keeps its link's path", linked?.command.contains(link.path) == true)
        let linkedRun = await ShellCommandRunner.run(
            linked?.command ?? "", workingDirectory: linked?.workingDirectory)
        check("a linked script runs its target", linkedRun.standardOutput == "linked-target-ran")

        // The whole run, through `"$@"`: an imported script reads its value as data, never as syntax.
        try? Data("#!/bin/bash\n# @raycast.title Echo\nprintf '%s' \"$1\"\n".utf8).write(
            to: scriptDirectory.appendingPathComponent("echo.sh"))
        let imported = RaycastScriptImport.scan(directory: scriptDirectory).first { $0.name == "Echo" }
        let forwarded = await ShellCommandRunner.run(
            imported?.command ?? "", arguments: ["; touch /tmp/tinycast-import-should-not-exist"],
            workingDirectory: imported?.workingDirectory)
        check(
            "an imported script receives its argument as one inert word",
            forwarded.standardOutput == "; touch /tmp/tinycast-import-should-not-exist"
                && !FileManager.default.fileExists(atPath: "/tmp/tinycast-import-should-not-exist"))
        try? FileManager.default.removeItem(at: scriptDirectory)

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
            // A pty ends every line with CR LF, never part of the thing under test.
            return (
                log.replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines), result
            )
        }

        let simple = await collect(ShellCommandRunner.stream("echo captured"))
        check("a streamed run reports what it printed", simple.log.contains("captured"))
        check("a streamed run reports a clean exit", simple.result?.succeeded == true)

        // The reported bug: brew writes `==>` to stderr, which must not reorder.
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

        // MARK: Another interpreter

        // The same text means `x` to zsh; only bash itself answers `y`.
        let bashArray = await ShellCommandRunner.run("#!/bin/bash\na=(x y)\nprintf '%s' \"${a[1]}\"")
        check("a #! line picks the interpreter that runs the text", bashArray.standardOutput == "y")

        let scripted = await ShellCommandRunner.run(
            "#!/bin/sh\nprintf '%s\\n' \"$0\" \"$1\"",
            arguments: ["; touch /tmp/tinycast-script-should-not-exist"])
        let scriptedLines = scripted.standardOutput?.split(separator: "\n").map(String.init) ?? []
        check(
            "a #! script reads its value as data, never as syntax",
            scriptedLines.last == "; touch /tmp/tinycast-script-should-not-exist"
                && !FileManager.default.fileExists(atPath: "/tmp/tinycast-script-should-not-exist"))
        check(
            "a #! script's file is gone once it exits",
            scriptedLines.count == 2 && !FileManager.default.fileExists(atPath: scriptedLines[0]))

        let streamedScript = await collect(
            ShellCommandRunner.stream("#!/bin/bash\nprintf '%s\\n' \"$BASH\""))
        check(
            "a #! script streams under the pty too",
            streamedScript.log.contains("/bin/bash") && streamedScript.result?.succeeded == true)

        let missingInterpreter = await ShellCommandRunner.run("#!/nope/bash\ntrue")
        check(
            "a missing interpreter is named in the failure",
            missingInterpreter.termination == .exited(status: 127)
                && missingInterpreter.standardError?.contains("/nope/bash") == true)

        // MARK: Inline argument values

        let search = CustomCommand(
            name: "Search", command: "open \"$1$2\"",
            arguments: [
                CustomCommandArgument(name: "Query"),
                CustomCommandArgument(name: "Query", isOptional: true)
            ])
        check(
            "fields are keyed by position, so a shared name cannot collide",
            (0..<2).map(CustomCommandArgument.fieldID) == ["$1", "$2"])
        check(
            "a required value still empty holds the run",
            search.positionalValues(from: ["$2": "swift"]) == nil)
        check(
            "an optional value left empty still occupies its slot",
            search.positionalValues(from: ["$1": "google"]) == ["google", ""])
        check(
            "values arrive in $n order",
            search.positionalValues(from: ["$2": "swift", "$1": "google"]) == ["google", "swift"])
        check(
            "a command without arguments is always complete",
            CustomCommand(name: "Plain", command: "true").positionalValues(from: [:]) == [])

        let capped = CustomCommandArgument.sanitized(
            ["a", " ", "b", "c", "d"].map { CustomCommandArgument(name: $0) })
        check(
            "arguments are capped at three, counted after blanks drop",
            capped.map(\.name) == ["a", "b", "c"])

        // MARK: Shell environment

        // A throwaway ZDOTDIR proves interactive mode sources an rc file.
        let zdotdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-zdotdir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        try? Data("alias tinycast_probe=true\n".utf8).write(
            to: zdotdir.appendingPathComponent(".zshrc"))
        setenv("ZDOTDIR", zdotdir.path, 1)
        // `/etc/zshrc` sources `zshrc_$TERM_PROGRAM`, which writes to the real home.
        unsetenv("TERM_PROGRAM")

        let withEnvironment = await ShellCommandRunner.run(
            "tinycast_probe", loadingShellEnvironment: true)
        check(
            "loading the shell environment resolves an rc-file alias",
            withEnvironment.succeeded)

        // The reported symptom: an alias only in `.zshrc` is command-not-found.
        let withoutEnvironment = await ShellCommandRunner.run("tinycast_probe")
        check(
            "the default shell exits 127 on an rc-file alias",
            withoutEnvironment.termination == .exited(status: 127))

        // The interactive-shell argument rests on this: a prompt reads EOF.
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

/// A fixed suite name stops cfprefsd accumulating a plist per run.
private func isolatedDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
