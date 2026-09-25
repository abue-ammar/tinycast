import Foundation

@main
@MainActor
struct InstalledAITests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// A write to a pipe nobody reads raises SIGPIPE, whose default action ends this process.
    static func aChildThatNeverReadsCannotKillTheApp() async {
        let input = Data(repeating: 0x61, count: 1_048_576)
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "sigpipe-probe")
        let probe = await InstalledAIProbe.run(
            executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], workspace: workspace,
            input: input)
        expect(probe.status == 0, "a probe whose child ignores stdin still returns")
        let answer = await InstalledAIProbe.request(
            executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], workspace: workspace,
            input: input, until: { _ in true })
        expect(answer.isEmpty, "a request whose child ignores stdin still returns")
    }

    /// A fish user's PATH lives in config.fish, which the zsh fallback never reads.
    private static func aFishLoginShellFindsWhatConfigFishAdds(_ fixture: Fixture) async {
        guard
            let fish = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"]
                .map({ URL(fileURLWithPath: $0) })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            print("skip  fish login shell — fish is not installed")
            return
        }
        let config = fixture.root.appending(path: "fish-config", directoryHint: .isDirectory)
        let tools = fixture.root.appending(path: "fish-tools", directoryHint: .isDirectory)
        let cli = tools.appending(path: "tc-fish-only-cli")
        do {
            try FileManager.default.createDirectory(
                at: config.appending(path: "fish"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: cli, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
            // The shape `mise activate fish` takes: PATH set only when interactive, after a greeting.
            try """
                echo 'Welcome to fish'
                if status is-interactive
                    set -gx PATH \(tools.path) $PATH
                end
                """.write(
                to: config.appending(path: "fish/config.fish"), atomically: true, encoding: .utf8)
        } catch {
            expect(false, "the fish fixture is written: \(error)")
            return
        }
        let saved = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        setenv("XDG_CONFIG_HOME", config.path, 1)
        defer {
            if let saved { setenv("XDG_CONFIG_HOME", saved, 1) } else { unsetenv("XDG_CONFIG_HOME") }
        }
        let found = await ExecutableLocator.shellLookup("tc-fish-only-cli", shell: fish)
        expect(found == cli.path, "a fish login shell finds a CLI only config.fish puts on PATH")
        let zsh = await ExecutableLocator.shellLookup(
            "tc-fish-only-cli", shell: URL(fileURLWithPath: "/bin/zsh"))
        expect(zsh == nil, "the zsh that fish users fell back to cannot see that CLI")
    }

    /// Startup files print ahead of the lookup's answer, and logout files after it.
    private static func anRcFileThatPrintsStillAnswers(_ fixture: Fixture) async {
        let zdot = fixture.root.appending(path: "zdot-greeting", directoryHint: .isDirectory)
        let tools = fixture.root.appending(path: "zsh-tools", directoryHint: .isDirectory)
        let cli = tools.appending(path: "tc-zshrc-only-cli")
        do {
            try FileManager.default.createDirectory(at: zdot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: cli, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
            try "echo 'Good morning'\nexport PATH=\"\(tools.path):$PATH\"\n".write(
                to: zdot.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
            try "echo 'Goodbye'\n".write(
                to: zdot.appending(path: ".zlogout"), atomically: true, encoding: .utf8)
        } catch {
            expect(false, "the zsh fixture is written: \(error)")
            return
        }
        setenv("ZDOTDIR", zdot.path, 1)
        defer { setenv("ZDOTDIR", fixture.root.path, 1) }
        let zsh = await ExecutableLocator.shellLookup(
            "tc-zshrc-only-cli", shell: URL(fileURLWithPath: "/bin/zsh"))
        expect(zsh == cli.path, "a .zshrc greeting and a .zlogout farewell leave the lookup its answer")
        let nu = await ExecutableLocator.shellLookup(
            "tc-zshrc-only-cli", shell: URL(fileURLWithPath: "/opt/homebrew/bin/nu"))
        expect(nu == cli.path, "a login shell with neither syntax, like nushell, still asks zsh")
    }

    static func main() async {
        guard let fixture = Fixture() else {
            expect(false, "the installed CLI fixture starts")
            return
        }
        defer { fixture.tearDown() }
        openCodeCatalogCarriesModelVariants()
        cursorCatalogParsesListModels()
        statusJSONRecognizesLogin()
        versionKeepsPrereleaseAndBuild()
        await openCodeRunsWithoutToolsAndDeletesItsSession(fixture)
        claudeDiscoveryReadsTheCLIsOwnModelList()
        await claudeRunsWithoutToolsOrHistory(fixture)
        await grokRunsWithoutToolsAndDeletesItsSession(fixture)
        grokCatalogParsesListedModels()
        await grokDiscoveryRequiresLoginAndFiltersModels(fixture)
        await cursorRunsAskModeWithoutForce(fixture)
        await cursorDiscoveryRequiresLoginAndListsModels(fixture)
        await oversizedCompleteFrameFailsTheTurn(fixture)
        claudeMCPConfigNamesNoServers(fixture)
        await claudeRunsTinycastsServersAndAnswersTheirConsent(fixture)
        await aDeclinedCallComesBackAsAnErrorResult(fixture)
        await theRoundCapEndsTheTurnTheWayTheLoopDoes(fixture)
        await unlimitedPassesNoTurnCap(fixture)
        await concurrentCallsAreAskedOneAtATime(fixture)
        await aCrashedTurnsFilesAreRemovedAtLaunch(fixture)
        await aManagedMCPPolicyLeavesBothFlagsOff(fixture)
        await aChildThatNeverReadsCannotKillTheApp()
        await aFishLoginShellFindsWhatConfigFishAdds(fixture)
        await anRcFileThatPrintsStillAnswers(fixture)

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static func openCodeCatalogCarriesModelVariants() {
        let output = """
            provider/model
            {
              "name": "Model",
              "variants": {
                "low": {"reasoningEffort": "low"},
                "high": {"reasoningEffort": "high"}
              }
            }
            provider/plain
            {
              "name": "Plain",
              "variants": {}
            }
            """
        let models = InstalledAIModel.openCodeCatalog(output)
        expect(
            models.first?.efforts.map(\.id) == ["low", "high"],
            "OpenCode discovery keeps each model's supported reasoning variants")
        expect(models.last?.efforts.isEmpty == true, "models without variants show no effort picker")
    }

    private static func cursorCatalogParsesListModels() {
        let output = """
            Available models

            auto - Auto (current, default)
            composer-2.5 - Composer 2.5
            gpt-5.2 - GPT-5.2
            """
        let models = InstalledAIModel.cursorCatalog(output)
        expect(
            models.map(\.id) == ["auto", "composer-2.5", "gpt-5.2"],
            "Cursor discovery keeps each --list-models id")
        expect(
            models.map(\.name) == ["Auto (current, default)", "Composer 2.5", "GPT-5.2"],
            "Cursor discovery keeps each --list-models display name")
        expect(models.allSatisfy(\.efforts.isEmpty), "Cursor model ids carry effort; no separate picker")
    }

    private static func statusJSONRecognizesLogin() {
        expect(
            InstalledAIProbe.loggedIn(inStatusJSON: #"{"loggedIn":true}"#),
            "Claude auth status JSON reports login")
        expect(
            InstalledAIProbe.loggedIn(inStatusJSON: #"{"isAuthenticated":true}"#),
            "Cursor status JSON reports login")
        expect(
            !InstalledAIProbe.loggedIn(inStatusJSON: #"{"status":"logged_out"}"#),
            "unsigned-in status JSON is not treated as logged in")
    }

    private static func versionKeepsPrereleaseAndBuild() {
        let cases: [(String, String?)] = [
            ("opencode2 v0.0.0-beta-19271\n", "0.0.0-beta-19271"),
            ("2.0.14 (Claude Code)\n", "2.0.14"),
            ("codex-cli 0.46.0\n", "0.46.0"),
            ("tool 1.2.3-rc.1+build.5\n", "1.2.3-rc.1+build.5"),
            ("no version here", nil)
        ]
        for (output, expected) in cases {
            let version = InstalledAIProbe.version(in: output)
            expect(
                version == expected,
                "version(in: \(output.debugDescription)) is \(String(describing: version))")
        }
    }

    private static func openCodeRunsWithoutToolsAndDeletesItsSession(_ fixture: Fixture) async {
        let events = await fixture.events(
            kind: .openCode, model: "provider/model", effort: "high")
        expect(events.contains(.text("OpenCode reply")), "OpenCode text reaches the provider stream")
        expect(events.last == .finished, "OpenCode finishes the provider stream")
        let arguments = fixture.read("opencode-args.log")
        expect(
            arguments.contains("--pure") && arguments.contains("--format")
                && arguments.contains("provider/model") && arguments.contains("--variant")
                && arguments.contains("high"),
            "OpenCode runs pure with JSON output, the chosen model and its variant")
        let configuration = fixture.read("opencode-environment.log")
        expect(
            configuration.contains("\"permission\":\"deny\"")
                && configuration.contains("\"share\":\"disabled\""),
            "OpenCode receives deny-all permissions and disabled sharing")
        let deleted = await fixture.awaitFile("deleted.log", containing: "ses_stub")
        if !deleted { print("OpenCode invocations: \(fixture.read("opencode-args.log"))") }
        expect(deleted, "OpenCode deletes the session created for the reply")
        fixture.expectPrompt("opencode-prompt.log")
    }

    private static func grokCatalogParsesListedModels() {
        let output = """
            You are logged in with grok.com.

            Default model: grok-4.6

            Available models:
              * grok-4.6 (default)
              - grok-4.5
            """
        let models = InstalledAIModel.grokCatalog(output)
        expect(models.map(\.id) == ["grok-4.6", "grok-4.5"], "Grok discovery keeps listed model ids")
        expect(
            models.first?.efforts.map(\.id) == ["low", "medium", "high", "xhigh"],
            "Grok models expose the CLI's advertised reasoning efforts")
        let signedOut = """
            You are not authenticated.

            Default model: grok-4.6

            Available models:
              * grok-4.6 (default)
              - grok-4.5
            """
        expect(
            !InstalledAIModel.grokSignedIn(signedOut)
                && InstalledAIModel.grokCatalog(signedOut).map(\.id) == ["grok-4.6", "grok-4.5"],
            "a signed-out Grok catalog is not a login")
        expect(InstalledAIModel.grokSignedIn(output), "a logged-in Grok catalog counts as signed in")
    }

    static func claudeDiscoveryReadsTheCLIsOwnModelList() {
        let output = """
            {"type":"system","subtype":"hook_started"}
            {"type":"control_response","response":{"subtype":"success","request_id":"x","response":\
            {"models":[{"value":"default","resolvedModel":"claude-opus-5-5",\
            "description":"Opus 5.5 · Best"},{"value":"opus","resolvedModel":"claude-opus-5-5",\
            "description":"Opus 5.5 · Best","supportedEffortLevels":["low","high"]},\
            {"value":"claude-fable-5-1[1m]","resolvedModel":"claude-fable-5-1",\
            "description":"Fable 5.1 · Most capable"},{"value":"haiku","displayName":"Haiku"}]}}}
            """
        let models = InstalledAIModel.claudeCatalog(output)
        expect(
            models.map(\.id) == ["opus", "claude-fable-5-1[1m]", "haiku"],
            "Claude discovery keeps every model the CLI offers, once per resolved model")
        expect(
            models.map(\.name) == ["Claude Opus 5.5", "Claude Fable 5.1", "Claude Haiku"],
            "a Claude model is named by the version its alias points at")
        expect(
            models.first?.efforts.map(\.id) == ["low", "high"],
            "a Claude model carries only the efforts the CLI says it supports")
        let frame = InstalledAIStreamDecoder.decode(
            Data(
                #"{"type":"stream_event","event":{"delta":{"type":"thinking_delta","thinking":"Plan"}}}"#.utf8
            ),
            kind: .claude)
        expect(frame.events == [.thinking, .reasoning("Plan")], "Claude thinking reaches the fold")
        let opening = InstalledAIStreamDecoder.decode(
            Data(
                #"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"thinking"}}}"#
                    .utf8),
            kind: .claude)
        expect(
            opening.events == [.thinking, .reasoning("\n\n")],
            "a new thinking block breaks from the one before it")
        expect(
            InstalledAIModel.claudeTitle(
                #"{"type":"control_response","response":{"subtype":"success","#
                    + #""request_id":"tinycast-title","response":{"title":"Weekend hiking trip plan"}}}"#)
                == "Weekend hiking trip plan",
            "Claude's own session namer is read from its control response")
        expect(
            InstalledAIModel.claudeTitleRequest("User: hi")?.contains("generate_session_title") == true,
            "the title request asks Claude Code to name the session without persisting it")
        let result = InstalledAIStreamDecoder.decode(
            Data(
                (#"{"type":"result","total_cost_usd":0.5,"usage":{"input_tokens":10,"output_tokens":59,"#
                    + #""cache_read_input_tokens":6401,"cache_creation_input_tokens":0,"#
                    + #""output_tokens_details":{"thinking_tokens":51}},"#
                    + #""modelUsage":{"claude-haiku-4-5":{"contextWindow":200000}}}"#).utf8),
            kind: .claude)
        expect(
            result.events == [
                .usage(
                    AIUsage(
                        inputTokens: 10, outputTokens: 59, cachedInputTokens: 6_401,
                        reasoningTokens: 51, contextWindow: 200_000, costUSD: 0.5))
            ],
            "Claude's result reports cached and thinking tokens, its window and its cost")
        let mixed = InstalledAIStreamDecoder.decode(
            Data(
                (#"{"type":"result","usage":{"input_tokens":10,"output_tokens":5},"modelUsage":{"#
                    + #""claude-haiku-4-5":{"inputTokens":300,"contextWindow":200000},"#
                    + #""claude-opus-5-5[1m]":{"inputTokens":40,"cacheReadInputTokens":90000,"#
                    + #""contextWindow":1000000}}}"#).utf8),
            kind: .claude)
        guard case .usage(let usage)? = mixed.events.first else {
            expect(false, "a result naming two models still reports usage")
            return
        }
        expect(
            usage.contextWindow == 1_000_000,
            "the window is the conversation model's, not a side call's: "
                + String(describing: usage.contextWindow))
    }

    private static func grokDiscoveryRequiresLoginAndFiltersModels(_ fixture: Fixture) async {
        let manager = InstalledAIManager(supportDirectory: fixture.root)
        await manager.refresh(kind: .grok).value
        let status = manager.status(for: .grok)
        expect(
            status.phase == .signInRequired,
            "Grok discovery requires sign-in despite a successful catalog response")
        expect(
            status.models.isEmpty,
            "Grok discovery hides listed models while signed out")
    }

    private static func claudeRunsWithoutToolsOrHistory(_ fixture: Fixture) async {
        let events = await fixture.events(kind: .claude, model: "sonnet", effort: "xhigh")
        expect(events.contains(.text("Claude reply")), "Claude text reaches the provider stream")
        expect(events.last == .finished, "Claude finishes the provider stream")
        let arguments = fixture.read("claude-args.log")
        for flag in [
            "--no-session-persistence", "--disable-slash-commands", "--tools",
            "--disallowedTools", "--strict-mcp-config", "--no-chrome"
        ] {
            expect(arguments.contains(flag), "Claude runs with \(flag)")
        }
        expect(
            arguments.contains("stream-json") && arguments.contains("--thinking-display")
                && arguments.contains("summarized"),
            "Claude reads JSON input and streams its thinking summaries")
        expect(
            fixture.read("claude-prompt.log").hasPrefix(#"{""#),
            "Claude's turn arrives as one stream-json user message")
        // `--bare` reads neither OAuth nor the keychain, so it refuses the sign-in this route reuses.
        expect(!arguments.contains("--bare"), "Claude never runs with --bare")
        expect(
            arguments.contains("--effort") && arguments.contains("xhigh"),
            "Claude receives the chosen reasoning effort")
        let argv = fixture.arguments("claude-args.log")
        expect(
            argv.firstIndex(of: "--max-turns").map { argv[$0 + 1] } == "1",
            "a turn with nothing to call is held to one request")
        fixture.expectPrompt("claude-prompt.log")
    }

    private static func cursorRunsAskModeWithoutForce(_ fixture: Fixture) async {
        let events = await fixture.events(kind: .cursor, model: "composer-2.5", effort: nil)
        expect(events.contains(.text("Cursor ")), "Cursor delta text reaches the provider stream")
        expect(!events.contains(.text("Cursor reply")), "Cursor skips buffered assistant flushes")
        expect(events.last == .finished, "Cursor finishes the provider stream")
        let arguments = fixture.read("agent-args.log")
        for flag in [
            "-p", "--mode", "ask", "--trust", "--workspace", "--model", "composer-2.5",
            "--output-format", "stream-json", "--stream-partial-output"
        ] {
            expect(arguments.contains(flag), "Cursor runs with \(flag)")
        }
        expect(!arguments.contains("--force"), "Cursor never runs with --force")
        expect(!arguments.contains("--yolo"), "Cursor never runs with --yolo")
        expect(
            !arguments.contains("--approve-mcps"),
            "Cursor never auto-approves the user's MCP servers")
        expect(
            !fixture.read("agent-args.log").contains("\"mcp\""),
            "Cursor discovery and turns never edit the user's MCP configuration")
        fixture.expectPrompt("agent-prompt.log")
        let chat = fixture.cursorChats.appending(path: "ws/ses_cursor", directoryHint: .isDirectory)
        expect(
            await fixture.awaitMissing(chat),
            "Cursor deletes the local chat created for the reply")
    }

    private static func oversizedCompleteFrameFailsTheTurn(_ fixture: Fixture) async {
        setenv("TC_INSTALLED_MAX_LINE_BYTES", "64", 1)
        defer { unsetenv("TC_INSTALLED_MAX_LINE_BYTES") }
        let error = await fixture.streamError(
            kind: .claude, model: "oversized-frame", effort: nil)
        expect(
            error?.contains("oversized response") == true,
            "a complete NDJSON frame over the byte limit fails the turn")
    }

    /// A crash mid-turn leaves the turn's files, secrets included; the next launch removes them.
    private static func aCrashedTurnsFilesAreRemovedAtLaunch(_ fixture: Fixture) async {
        let support = fixture.root.appending(path: "relaunch", directoryHint: .isDirectory)
        let workspace = support.appending(
            path: "InstalledAI/Workspace", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        func file(_ name: String, age: TimeInterval) -> URL {
            let url = workspace.appending(path: name)
            FileManager.default.createFile(atPath: url.path, contents: Data("secret".utf8))
            try? FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        let config = file("tinycast-mcp-\(UUID().uuidString).json", age: 60)
        let prompt = file("tinycast-prompt-\(UUID().uuidString).txt", age: 60)
        let live = file("tinycast-mcp-\(UUID().uuidString).json", age: -60)
        let other = file("notes.txt", age: 60)
        _ = InstalledAIManager(supportDirectory: support)
        let removed = await fixture.awaitMissing(config)
        expect(
            removed && !FileManager.default.fileExists(atPath: prompt.path),
            "a configuration and a prompt left by a turn that never ended are deleted at launch")
        expect(
            FileManager.default.fileExists(atPath: live.path)
                && FileManager.default.fileExists(atPath: other.path),
            "and nothing written since, nor anything that is not a turn's own file, is touched")
    }

    private static func cursorDiscoveryRequiresLoginAndListsModels(_ fixture: Fixture) async {
        let manager = InstalledAIManager(supportDirectory: fixture.root)
        await manager.refresh(kind: .cursor).value
        let status = manager.status(for: .cursor)
        expect(status.isReady, "Cursor discovery is ready after status and --list-models")
        expect(
            status.models.map(\.id) == ["auto", "composer-2.5"],
            "Cursor discovery keeps the --list-models catalog")
    }

    private static func grokRunsWithoutToolsAndDeletesItsSession(_ fixture: Fixture) async {
        let events = await fixture.events(kind: .grok, model: "grok-4.6", effort: "high")
        expect(events.contains(.text("Grok reply")), "Grok text reaches the provider stream")
        expect(events.last == .finished, "Grok finishes the provider stream")
        let argv = fixture.arguments("grok-args.log")
        for flag in [
            "--prompt-file", "--output-format", "streaming-messages-json",
            "--include-partial-messages", "--max-turns", "--no-subagents",
            "--disable-web-search", "--no-plan", "--permission-mode", "dontAsk",
            "--tools", "--deny", "--disallowed-tools", "--sandbox", "workspace", "--verbatim"
        ] {
            expect(argv.contains(flag), "Grok runs with \(flag)")
        }
        if let index = argv.firstIndex(of: "--prompt-file"), index + 1 < argv.count {
            let name = URL(fileURLWithPath: argv[index + 1]).lastPathComponent
            expect(
                name.hasPrefix("tinycast-prompt-") && name.hasSuffix(".txt")
                    && name != "tinycast-prompt.txt",
                "Grok prompt file is unique per turn")
        }
        expect(
            argv.contains("--effort") && argv.contains("high"),
            "Grok receives the chosen reasoning effort")
        expect(
            fixture.read("grok-grok-environment.log").contains("1"),
            "Grok disables its auto-updater for the turn")
        let deleted = await fixture.awaitFile("grok-deleted.log", containing: "ses_stub")
        if !deleted { print("Grok invocations: \(fixture.read("grok-args.log"))") }
        expect(deleted, "Grok deletes the session created for the reply")
        fixture.expectPrompt("grok-prompt.log")
    }

    /// The CLI rejects a bare `{}` before the turn starts, and a stub argv would never notice.
    private static func claudeMCPConfigNamesNoServers(_ fixture: Fixture) {
        let argv = fixture.arguments("claude-args.log")
        guard let index = argv.firstIndex(of: "--mcp-config"), index + 1 < argv.count,
            let data = argv[index + 1].data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            expect(false, "Claude passes a decodable --mcp-config object")
            return
        }
        expect(
            object.count == 1 && object["mcpServers"] is [String: Any],
            "Claude's --mcp-config declares an empty mcpServers record")
    }

    /// The whole route: Tinycast's servers go in, the CLI runs the loop, consent comes back here.
    private static func claudeRunsTinycastsServersAndAnswersTheirConsent(_ fixture: Fixture) async {
        let asked = Box()
        let events = await fixture.events(
            kind: .claude, model: "sonnet", effort: nil,
            toolServers: fixture.session(allowing: true, asked: asked))
        expect(
            events.contains(.toolCall(id: "toolu_stub", origin: "Probe", title: "safe_echo")),
            "a tool_use block becomes the transcript row the BYOK loop would have written")
        expect(
            events.contains(.toolResult(id: "toolu_stub", isError: false)),
            "and its tool_result settles the same row")
        expect(events.contains(.text("Claude reply")), "the reply still streams after the call")
        expect(events.last == .finished, "and the turn finishes on the CLI's own result frame")
        expect(
            asked.calls == [AIToolServerCall(handle: "probe", tool: "safe_echo")],
            "consent was asked for the call the CLI named, addressed by Tinycast's own handle")

        let argv = fixture.lastArguments("claude-args.log")
        for flag in ["--strict-mcp-config", "--mcp-config", "--permission-prompt-tool", "stdio"] {
            expect(argv.contains(flag), "Claude runs with \(flag) when servers are armed")
        }
        expect(
            !argv.contains("--disallowedTools"),
            "and without the deny-all that would take the MCP tools with it")
        let mode = argv.firstIndex(of: "--permission-mode").map { argv[$0 + 1] }
        let settings = argv.firstIndex(of: "--settings").map { argv[$0 + 1] }
        expect(
            mode == "default" && settings == #"{"permissions":{"ask":["mcp__probe"]}}"#,
            "its mode is pinned, and the server has an ask rule no rule of the reader's outranks")
        expect(
            argv.contains("--input-format")
                && argv[(argv.firstIndex(of: "--input-format") ?? 0) + 1] == "stream-json",
            "stream-json input is what the consent channel answers on")
        expect(
            argv.firstIndex(of: "--max-turns").map { argv[$0 + 1] } == "25",
            "and the turn is capped at the setting's rounds rather than one")
        guard let index = argv.firstIndex(of: "--mcp-config"), index + 1 < argv.count else {
            expect(false, "Claude is given a configuration path")
            return
        }
        let configured = URL(fileURLWithPath: argv[index + 1])
        expect(
            configured.deletingLastPathComponent().path == fixture.workspace.path,
            "the configuration lives inside Tinycast's own workspace, never a CLI's settings")
        expect(
            configured.lastPathComponent.hasPrefix("tinycast-mcp-")
                && configured.lastPathComponent != "tinycast-mcp-.json",
            "under a name of its own, so a second turn never deletes a live turn's file")
        expect(
            await fixture.awaitMissing(configured),
            "and is deleted once the turn is over")
        expect(
            fixture.read("claude-mcp-mode.log").contains("600"),
            "while it existed it was readable by nobody else")
        let written = fixture.read("claude-mcp-config.log")
        expect(
            written.contains("\"probe\"") && written.contains("s3cret"),
            "it carried the server and the secret the CLI needs to start it")
        expect(
            !argv.contains(where: { $0.contains("s3cret") }),
            "which never appears on argv, where `ps` would show it")
        fixture.expectPrompt("claude-prompt.log")
    }

    private static func aDeclinedCallComesBackAsAnErrorResult(_ fixture: Fixture) async {
        let asked = Box()
        let events = await fixture.events(
            kind: .claude, model: "sonnet", effort: nil,
            toolServers: fixture.session(allowing: false, asked: asked))
        expect(
            events.contains(.toolResult(id: "toolu_stub", isError: true)),
            "a refused call settles as a failed row rather than a failed turn")
        expect(events.last == .finished, "and the reply still ends honestly")
        let control = fixture.read("claude-control.log")
        expect(
            control.contains("\"behavior\":\"deny\""),
            "the CLI was told no through its own control channel")
        expect(
            !control.contains("updatedPermissions"),
            "and never handed a permission update, which it would write to its own settings")
        let unknown = fixture.read("claude-unknown.log")
        expect(
            unknown.contains(#""subtype":"error""#)
                && unknown.contains(#""request_id":"req_unknown""#),
            "a control request Tinycast does not know is answered with an error, not left waiting")
    }

    /// The dialog shows one question at a time, and the second must see what the first granted.
    private static func concurrentCallsAreAskedOneAtATime(_ fixture: Fixture) async {
        let reader = GrantingReader()
        let session = AIToolServerSession(rounds: 25) {
            await fixture.session(allowing: true, asked: Box()).servers()
        } consent: { call in
            await reader.answer(call)
        }
        let events = await fixture.events(
            kind: .claude, model: "pair", effort: nil, toolServers: session)
        expect(
            reader.calls.map(\.tool) == ["first_tool", "second_tool"] && reader.mostAtOnce == 1,
            "two calls held open together are asked about one after the other, in order")
        expect(
            reader.dialogs == 1,
            "and the second is decided after the first dialog closes, so its grant is seen")
        let answers = fixture.read("claude-control.log").split(separator: "\n").suffix(2)
        expect(
            answers.count == 2 && answers.allSatisfy { $0.contains(#""behavior":"allow""#) }
                && events.last == .finished,
            "both calls are allowed on the one channel and the turn finishes")
    }

    private static func theRoundCapEndsTheTurnTheWayTheLoopDoes(_ fixture: Fixture) async {
        let error = await fixture.streamError(
            kind: .claude, model: "round-cap", effort: nil,
            toolServers: fixture.session(allowing: true, asked: Box()))
        expect(
            error?.contains("Stopped after 25 rounds of tool calls.") == true,
            "the CLI's own cap is reported in the sentence the BYOK loop uses")
    }

    /// Claude has no turn cap unless one is passed, so Unlimited is the flag's absence.
    private static func unlimitedPassesNoTurnCap(_ fixture: Fixture) async {
        let events = await fixture.events(
            kind: .claude, model: "sonnet", effort: nil,
            toolServers: fixture.session(allowing: true, asked: Box(), rounds: nil))
        let argv = fixture.lastArguments("claude-args.log")
        expect(
            argv.contains("--mcp-config") && !argv.contains("--max-turns"),
            "an armed turn on Unlimited passes no --max-turns at all")
        expect(events.last == .finished, "and ends on the CLI's own result")

        let error = await fixture.streamError(
            kind: .claude, model: "round-cap", effort: nil,
            toolServers: fixture.session(allowing: true, asked: Box(), rounds: nil))
        expect(
            error?.contains("Claude could not finish the response.") == true
                && error?.contains("Stopped after") == false,
            "a max-turns result under no cap names no number, since Tinycast set none")

        let nothingToCall = AIToolServerSession(rounds: nil) {
            []
        } consent: { _ in
            false
        }
        _ = await fixture.events(
            kind: .claude, model: "sonnet", effort: nil, toolServers: nothingToCall)
        let bare = fixture.lastArguments("claude-args.log")
        expect(
            bare.firstIndex(of: "--max-turns").map { bare[$0 + 1] } == "1"
                && bare.contains("--disallowedTools"),
            "while one on Unlimited with no server to run is still a single request")
    }

    /// An admin's policy makes the CLI reject both flags, so the route passes neither.
    private static func aManagedMCPPolicyLeavesBothFlagsOff(_ fixture: Fixture) async {
        let policy = fixture.root.appending(path: "managed-mcp.json")
        FileManager.default.createFile(atPath: policy.path, contents: Data("{}".utf8))
        setenv("TC_CLAUDE_MANAGED_MCP", policy.path, 1)
        defer { unsetenv("TC_CLAUDE_MANAGED_MCP") }
        _ = await fixture.events(
            kind: .claude, model: "sonnet", effort: nil,
            toolServers: fixture.session(allowing: true, asked: Box()))
        let argv = fixture.lastArguments("claude-args.log")
        expect(
            !argv.contains("--strict-mcp-config") && !argv.contains("--mcp-config"),
            "neither MCP flag is passed while a managed policy is installed")
        expect(
            argv.contains("--max-turns") && argv.contains("1"),
            "and the turn goes back to the single request a route with no tools makes")
        expect(
            InstalledAIKind.claude.isolationCaveat(hasManagedMCPPolicy: true)?
                .contains("managed by your organization") == true,
            "the Providers row says whose decision that is")
        expect(
            InstalledAIKind.claude.isolationCaveat(hasManagedMCPPolicy: false) == nil,
            "and says nothing when it is Tinycast's")
    }
}

/// What the runner asked about, collected across the actor hop the consent closure makes.
@MainActor
private final class Box {
    var calls: [AIToolServerCall] = []
}

/// A reader who is asked once, takes a moment over it, and grants the server for the chat.
@MainActor
private final class GrantingReader {
    var calls: [AIToolServerCall] = []
    var dialogs = 0
    var mostAtOnce = 0
    private var atOnce = 0
    private var granted = false

    func answer(_ call: AIToolServerCall) async -> Bool {
        calls.append(call)
        atOnce += 1
        mostAtOnce = max(mostAtOnce, atOnce)
        defer { atOnce -= 1 }
        guard !granted else { return true }
        dialogs += 1
        try? await Task.sleep(for: .milliseconds(150))
        granted = true
        return true
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let workspace: URL
    let cursorChats: URL
    let executables: [InstalledAIKind: URL]

    init?() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "installed-ai-\(UUID().uuidString)", directoryHint: .isDirectory)
        workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        cursorChats = root.appending(path: "cursor-chats", directoryHint: .isDirectory)
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cursorChats, withIntermediateDirectories: true)
            var values: [InstalledAIKind: URL] = [:]
            for kind in InstalledAIKind.managedCLIKinds {
                let executable = bin.appending(path: kind.command)
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: "Tests/ai-fixtures/installed-cli-stub.js"),
                    to: executable)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: executable.path)
                values[kind] = executable
            }
            executables = values
            let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
            setenv("PATH", bin.path + ":" + inheritedPath, 1)
            // The locator asks a login shell first; the user's rc files would put real CLIs ahead.
            setenv("ZDOTDIR", root.path, 1)
            // `/etc/zprofile`'s path_helper puts Homebrew's CLIs ahead of the stubs; undo that.
            try #"export TINYCAST_SAVED_PATH="$PATH""#.write(
                to: root.appending(path: ".zshenv"), atomically: true, encoding: .utf8)
            try #"[ -n "$TINYCAST_SAVED_PATH" ] && export PATH="$TINYCAST_SAVED_PATH""#.write(
                to: root.appending(path: ".zprofile"), atomically: true, encoding: .utf8)
            setenv("TC_INSTALLED_STUB_ROOT", root.path, 1)
            setenv("TC_CURSOR_CHATS_ROOT", cursorChats.path, 1)
        } catch {
            print("fixture setup failed: \(error)")
            return nil
        }
    }

    func events(
        kind: InstalledAIKind, model: String, effort: String?,
        toolServers: AIToolServerSession? = nil
    ) async -> [AIStreamEvent] {
        guard let executable = executables[kind] else { return [] }
        let provider = InstalledCLIProvider(
            kind: kind, executable: kind == .openCode ? nil : executable,
            model: model, effort: effort, workspace: workspace, toolServers: toolServers)
        do {
            var events: [AIStreamEvent] = []
            for try await event in provider.stream(request) { events.append(event) }
            return events
        } catch {
            print("\(kind.title) stream failed: \(error)")
            return []
        }
    }

    func streamError(
        kind: InstalledAIKind, model: String, effort: String?,
        toolServers: AIToolServerSession? = nil
    ) async -> String? {
        guard let executable = executables[kind] else { return nil }
        let provider = InstalledCLIProvider(
            kind: kind, executable: kind == .openCode ? nil : executable,
            model: model, effort: effort, workspace: workspace, toolServers: toolServers)
        do {
            for try await _ in provider.stream(request) {}
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// One local server, and a reader who answers every call the same way.
    func session(allowing: Bool, asked: Box, rounds: Int? = 25) -> AIToolServerSession {
        AIToolServerSession(rounds: rounds) {
            [
                AIToolServer(
                    handle: "probe", title: "Probe",
                    transport: .command(
                        path: "/bin/echo", arguments: ["probe"],
                        environment: ["API_KEY": "s3cret"]))
            ]
        } consent: { call in
            await MainActor.run { asked.calls.append(call) }
            return allowing
        }
    }

    private var request: AIRequest {
        AIRequest(
            instructions: "Follow the custom instruction.",
            messages: [
                AIMessage(role: .user, text: "First question"),
                AIMessage(role: .assistant, text: "First answer"),
                AIMessage(role: .user, text: "Final question")
            ])
    }

    func expectPrompt(_ name: String) {
        let prompt = read(name)
        InstalledAITests.expect(
            prompt.contains("Follow the custom instruction.")
                && prompt.contains("First question") && prompt.contains("First answer")
                && prompt.contains("Final question"),
            "the installed CLI receives instructions and conversation history through stdin")
    }

    func arguments(_ name: String) -> [String] {
        decodeArguments(read(name).split(separator: "\n").first)
    }

    /// The log is appended to, so the newest turn is the last line rather than the first.
    func lastArguments(_ name: String) -> [String] {
        decodeArguments(read(name).split(separator: "\n").last)
    }

    private func decodeArguments(_ line: Substring?) -> [String] {
        guard let data = line?.data(using: .utf8),
            let argv = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return argv
    }

    func awaitFile(_ name: String, containing value: String) async -> Bool {
        await awaitCondition { self.read(name).contains(value) }
    }

    func awaitMissing(_ url: URL) async -> Bool {
        await awaitCondition { !FileManager.default.fileExists(atPath: url.path) }
    }

    /// Cleanup outlives the stream on purpose, so the assertion waits instead of racing it.
    private func awaitCondition(_ isSatisfied: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if isSatisfied() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return isSatisfied()
    }

    func read(_ name: String) -> String {
        (try? String(contentsOf: root.appending(path: name), encoding: .utf8)) ?? ""
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
