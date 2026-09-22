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

    static func main() async {
        guard let fixture = Fixture() else {
            expect(false, "the installed CLI fixture starts")
            return
        }
        defer { fixture.tearDown() }
        openCodeCatalogCarriesModelVariants()
        cursorCatalogParsesListModels()
        grokCatalogParsesListedModels()
        statusJSONRecognizesLogin()
        versionKeepsPrereleaseAndBuild()
        await openCodeRunsWithoutToolsAndDeletesItsSession(fixture)
        await claudeRunsWithoutToolsOrHistory(fixture)
        await grokRunsWithoutToolsAndDeletesItsSession(fixture)
        await cursorRunsAskModeWithoutForce(fixture)
        await cursorDiscoveryRequiresLoginAndListsModels(fixture)
        await oversizedCompleteFrameFailsTheTurn(fixture)
        claudeMCPConfigNamesNoServers(fixture)
        await claudeRunsTinycastsServersAndAnswersTheirConsent(fixture)
        await aDeclinedCallComesBackAsAnErrorResult(fixture)
        await theRoundCapEndsTheTurnTheWayTheLoopDoes(fixture)
        await concurrentCallsAreAskedOneAtATime(fixture)
        await aManagedMCPPolicyLeavesBothFlagsOff(fixture)

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
        // `--bare` reads neither OAuth nor the keychain, so it refuses the sign-in this route reuses.
        expect(!arguments.contains("--bare"), "Claude never runs with --bare")
        expect(
            arguments.contains("--effort") && arguments.contains("xhigh"),
            "Claude receives the chosen reasoning effort")
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
            "its mode is pinned and the server has an ask rule the reader's own rules cannot outrank")
        expect(
            argv.contains("--input-format")
                && argv[(argv.firstIndex(of: "--input-format") ?? 0) + 1] == "stream-json",
            "stream-json input is what the consent channel answers on")
        expect(
            argv.contains("--max-turns") && argv.contains("25"),
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
    func session(allowing: Bool, asked: Box) -> AIToolServerSession {
        AIToolServerSession(rounds: 25) {
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
