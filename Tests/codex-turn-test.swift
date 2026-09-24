import Foundation

/// A turn's ID arrives twice and either can be late, so Stop can beat both.
@main
@MainActor
struct CodexTurnTests {
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
        await stopBeforeTurnStartedStillInterrupts()
        await aTurnNamedTwiceIsInterruptedOnce()
        await tinycastsServersAreLaunchedAndTheUsersOwnAreNot()
        await anElicitationIsAnsweredByTheTrustDialog()
        await aRefusedCallIsAFailedRowAndAnHonestReply()
        await aForeignServersElicitationIsNeverAsked()
        await aListThatCannotBeReadRefusesToStart()
        await theListingRunsUnderFindersPath()
        await concurrentStartsLaunchOnce()
        await aStatusCheckJoinsATurnsPendingLaunch()
        await aChangedListRelaunchesAndTheSameOneDoesNot()
        await aWithdrawnServerStopsTheIdleHelper()
        await twoCallsAreAskedAboutByTheirOwnNames()
        await theRoundCapInterruptsTheTurn()
        await unlimitedNeverStopsOnACount()
        await twoChatsStreamSideBySide()
        await stoppingOneChatLeavesTheOther()
        await twoChatsStartingColdShareOneHandshake()
        await aRelaunchEndsTheOtherChatsThreadWithAReason()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// The launch is the boundary: ours named, the reader's disabled, their config never written.
    static func tinycastsServersAreLaunchedAndTheUsersOwnAreNot() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let asked = Box()
        let turn = server.startTurn(toolServers: server.session(allowing: true, asked: asked))
        _ = await server.awaitLog("turn-params:")
        turn.cancel()

        let argv = server.argv
        let key = "mcp_servers.tinycast-probe"
        expect(
            argv.contains(#"\#(key).command="/bin/sh""#)
                && argv.contains {
                    $0.hasPrefix("\(key).args=") && $0.hasSuffix(#""/bin/echo","probe"]"#)
                },
            "Tinycast's server is on the launch line under its own name, behind the renaming shell")
        expect(
            argv.contains(#"\#(key).default_tools_approval_mode="prompt""#),
            "in the mode that asks for every tool, so one marked read-only cannot run unasked")
        expect(
            argv.contains("mcp_servers.user-one.enabled=false")
                && argv.contains("mcp_servers.user-two.enabled=false"),
            "and every server the user configured for their own Codex is disabled by name")
        expect(
            argv.contains("mcp_servers.probe.enabled=false")
                && !argv.contains { $0.hasPrefix("mcp_servers.probe.") && !$0.hasSuffix("=false") },
            "including the reader's own `probe`, which Tinycast's `probe` never merges into")
        expect(
            server.listArgv.contains("mcp") && server.listArgv.contains("--json"),
            "which were read by a short-lived `mcp list`, so none of them ever started")
        expect(
            server.listArgv.contains("features.plugins=false"),
            "under the same flags the app-server runs with, or the list would name a plugin's")
        expect(
            !argv.contains(where: { $0.contains("s3cret") }),
            "no secret is on argv, where `ps` would show it")
        expect(
            server.environment["TC_MCP_0_0"] == "s3cret",
            "the value reached the child's environment instead")
        expect(
            !server.received.contains("config/value/write")
                && !server.received.contains("config/batchWrite"),
            "and nothing was written to the user's Codex configuration")
        expect(
            server.received.contains(#""approvalPolicy":"untrusted""#),
            "the thread asks before a tool runs, rather than refusing every call")
    }

    /// A reader's server Tinycast cannot switch off would start inside the chat, so none do.
    static func aListThatCannotBeReadRefusesToStart() async {
        let cases = [
            ("list-fails", "could not read which MCP servers"),
            ("list-garbage", "could not read which MCP servers"),
            ("list-dotted", "\u{201C}has.dot\u{201D} cannot be kept out")
        ]
        for (mode, reason) in cases {
            guard let server = StubServer(mode: mode) else {
                expect(false, "the stub app-server installs")
                return
            }
            var message = ""
            do {
                try await server.client.start()
            } catch {
                message = error.localizedDescription
            }
            expect(
                message.contains(reason) && server.argv.isEmpty && !server.client.isRunning,
                "\(mode): Codex does not start, and says why, rather than run the reader's servers")
            server.tearDown()
        }
    }

    /// A Finder-launched app's PATH has no `node`, and an npm or Homebrew `codex` is `env node`.
    static func theListingRunsUnderFindersPath() async {
        let rule = ExecutableLocator.environment(
            running: URL(fileURLWithPath: "/opt/tools/bin/codex"),
            adding: ["PATH": "/elsewhere", "NO_COLOR": "0", "TOKEN": "t"],
            inherited: ["PATH": "/usr/bin:/bin", "HOME": "/Users/reader"])
        expect(
            rule["PATH"] == "/opt/tools/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "a CLI's own folder leads its PATH, then Homebrew's, then the PATH the app inherited")
        expect(
            rule["NO_COLOR"] == "1" && rule["TOKEN"] == "t" && rule["HOME"] == "/Users/reader",
            "added variables arrive, but never override the PATH or NO_COLOR")

        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }
        let bin = server.root.appending(path: "bin", directoryHint: .isDirectory)
        let codex = bin.appending(path: "codex")
        let work = server.root.appending(path: "work", directoryHint: .isDirectory)
        let node = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "node") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        // Beside the CLI, as npm and nvm keep it, so finding it needs no Homebrew on this machine.
        guard let node,
            (try? FileManager.default.createSymbolicLink(
                at: bin.appending(path: "node"), withDestinationURL: node)) != nil
        else {
            expect(false, "node is linked beside the stub")
            return
        }
        var finder = ProcessInfo.processInfo.environment
        finder["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"

        let names = await CodexAppServerClient.foreignServerNames(
            executable: codex, workspace: work,
            codexHome: server.root.appending(path: "home", directoryHint: .isDirectory),
            inherited: finder)
        expect(
            names?.contains("probe") == true,
            "the reader's servers are read under Finder's PATH, so Codex can start")

        let shellPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", finder["PATH"] ?? "", 1)
        let probe = await InstalledAIProbe.run(
            executable: codex, arguments: ["mcp", "list", "--json"], workspace: work)
        setenv("PATH", shellPath, 1)
        expect(probe.status == 0, "a status probe of an `env node` CLI runs under Finder's PATH too")
    }

    /// A status check racing a turn, or two quick sends, must share one app-server.
    static func concurrentStartsLaunchOnce() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        setenv("TC_STUB_LIST_DELAY", "300", 1)
        defer {
            unsetenv("TC_STUB_LIST_DELAY")
            server.tearDown()
        }
        let client = server.client
        async let first: Void = client.start()
        async let second: Void = client.start()
        let firstStarted = (try? await first) != nil
        let secondStarted = (try? await second) != nil
        expect(
            firstStarted && secondStarted && server.launches == 1 && client.isRunning,
            "two starts at once launch one app-server, and both callers get the running one")

        let stopped = Task { try await client.start(toolServers: server.servers(key: "one")) }
        _ = await server.awaitCondition { server.launches == 1 && server.listed == 2 }
        client.stop()
        let outcome = await stopped.result
        expect(
            (try? outcome.get()) == nil && server.launches == 1 && !client.isRunning,
            "and a Stop that lands while a launch reads the list keeps it from starting afterwards")
    }

    /// A check has no list of its own, so it must never relaunch a turn's app-server without one.
    static func aStatusCheckJoinsATurnsPendingLaunch() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        setenv("TC_STUB_LIST_DELAY", "300", 1)
        defer {
            unsetenv("TC_STUB_LIST_DELAY")
            manager.stop()
            server.tearDown()
        }
        let stream = manager.turns.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]), model: "gpt-5-codex",
            effort: nil, toolServers: server.session(allowing: true, asked: Box()))
        let turn = Task {
            var finished = false
            do {
                for try await event in stream where event == .finished { finished = true }
            } catch {}
            return finished
        }
        _ = await server.awaitCondition { server.listed == 1 }
        await manager.refresh().value
        let finished = await turn.value
        expect(
            finished && server.launches == 1
                && server.argv.contains { $0.hasPrefix("mcp_servers.tinycast-probe.") },
            "a status check during a turn's launch joins it, and the turn keeps its servers")
    }

    /// The list is fixed at exec, so only a different one is worth a second launch.
    static func aChangedListRelaunchesAndTheSameOneDoesNot() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }
        let asked = Box()
        _ = await server.collect(toolServers: server.session(allowing: true, asked: asked))
        _ = await server.collect(toolServers: server.session(allowing: true, asked: asked))
        expect(server.launches == 1, "the same server list twice runs in the one app-server")
        _ = await server.collect(
            toolServers: server.session(
                allowing: true, asked: asked, servers: server.servers(key: "rotated")))
        expect(
            server.launches == 2 && server.environment["TC_MCP_0_0"] == "rotated",
            "a changed list, a refreshed secret included, relaunches it with the new values")
    }

    /// Off means off: a server withdrawn from chat must not live on in an idle helper.
    static func aWithdrawnServerStopsTheIdleHelper() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        defer {
            manager.stop()
            server.tearDown()
        }
        let stream = manager.turns.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]), model: "gpt-5-codex",
            effort: nil, toolServers: server.session(allowing: true, asked: Box()))
        var finished = false
        do {
            for try await event in stream where event == .finished { finished = true }
        } catch {}
        manager.dropWithdrawnServers(keeping: ["probe", "other"])
        let closedEarly = await server.awaitCondition(timeout: .milliseconds(300)) {
            server.received.contains("stdin-closed")
        }
        expect(
            finished && !closedEarly,
            "a helper whose servers are all still offered keeps running between turns")
        manager.dropWithdrawnServers(keeping: ["other"])
        expect(
            await server.awaitLog("stdin-closed"),
            "and one launched with a server no longer offered stops without waiting to idle")
    }

    /// Two calls at once: each asked about by its own name, one at a time, after the grant.
    static func twoCallsAreAskedAboutByTheirOwnNames() async {
        guard let server = StubServer(mode: "mcp-pair") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }
        let reader = GrantingReader()
        let servers = server.servers()
        let session = AIToolServerSession(rounds: 10) {
            servers
        } consent: { call in
            await reader.answer(call)
        }
        let events = await server.collect(toolServers: session)
        expect(
            reader.calls.map(\.tool).sorted() == ["first_tool", "second_tool"],
            "each question names its own call, not whichever of the server's started last")
        expect(
            reader.mostAtOnce == 1 && reader.dialogs == 1,
            "and the second waits for the first dialog, then sees the grant it made")
        expect(
            server.received.components(separatedBy: #"{"action":"accept"}"#).count == 3
                && events.last == .finished,
            "so both are accepted and the turn finishes")
    }

    /// `.ask` on a CLI route is the same dialog it is on an API one.
    static func anElicitationIsAnsweredByTheTrustDialog() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let asked = Box()
        let events = await server.collect(
            toolServers: server.session(allowing: true, asked: asked))
        expect(
            asked.calls == [AIToolServerCall(handle: "probe", tool: "safe_echo")],
            "the elicitation became a question about the call Codex named")
        expect(
            server.received.contains(#"elicitation:{"action":"accept"}"#),
            "an allowed call is accepted, and nothing about persisting it is sent back")
        expect(
            events.contains(.toolCall(id: "call-1", origin: "Probe", title: "safe_echo")),
            "the call renders as the row the BYOK loop would have written")
        expect(
            events.contains(.toolResult(id: "call-1", isError: false)),
            "and its completion settles that row")
    }

    /// Consent is for Tinycast's servers; a question about any other is declined, never asked.
    static func aForeignServersElicitationIsNeverAsked() async {
        guard let server = StubServer(mode: "mcp-foreign") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let asked = Box()
        let events = await server.collect(
            toolServers: server.session(allowing: true, asked: asked))
        expect(
            asked.calls.isEmpty && server.received.contains(#"elicitation:{"action":"decline"}"#),
            "a call on the reader's own `probe` is declined without asking about Tinycast's")
        expect(
            events.contains(.toolCall(id: "call-1", origin: "probe", title: "safe_echo")),
            "and its row keeps Codex's name, never the title of Tinycast's same-handle server")
    }

    static func aRefusedCallIsAFailedRowAndAnHonestReply() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let events = await server.collect(
            toolServers: server.session(allowing: false, asked: Box()))
        expect(
            server.received.contains(#"elicitation:{"action":"decline"}"#),
            "Escape declines that one call")
        expect(
            events.contains(.toolResult(id: "call-1", isError: true)),
            "which settles as a failed row rather than a failed turn")
        expect(events.last == .finished, "and the reply still ends")
    }

    /// Codex names no round of its own, so the cap counts calls and interrupts past it.
    static func theRoundCapInterruptsTheTurn() async {
        guard let server = StubServer(mode: "mcp-rounds") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let error = await server.streamError(
            toolServers: server.session(allowing: true, asked: Box(), rounds: 2))
        expect(
            error?.contains("Stopped after 2 rounds of tool calls.") == true,
            "the turn fails with the sentence the loop uses")
        expect(
            await server.awaitLog("interrupt:thread-1:turn-1"),
            "and the turn Codex is still running is interrupted rather than left to finish")
    }

    /// Unlimited hands Codex no count at all, so only the model's own answer ends the turn.
    static func unlimitedNeverStopsOnACount() async {
        guard let server = StubServer(mode: "mcp-many") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let events = await server.collect(
            toolServers: server.session(allowing: true, asked: Box(), rounds: nil))
        let calls = events.count {
            if case .toolCall = $0 { return true }
            return false
        }
        expect(calls == 120, "all 120 calls run, past the largest step Settings offers")
        expect(
            events.contains(.text("done")) && events.last == .finished && server.interrupts == 0,
            "and the turn finishes on the model's answer, never interrupted")

        guard let capped = StubServer(mode: "mcp-many") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { capped.tearDown() }
        let error = await capped.streamError(
            toolServers: capped.session(allowing: true, asked: Box(), rounds: 100))
        expect(
            error?.contains("Stopped after 100 rounds of tool calls.") == true,
            "while the largest step stops that same turn, naming its own number")
    }

    /// Stop arrives before anything names the turn, and `turn/start` never answers.
    static func stopBeforeTurnStartedStillInterrupts() async {
        guard let server = StubServer(mode: "hold-turn") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let turn = server.startTurn(effort: "high")
        guard await server.awaitMark("turn-start-received") else {
            expect(false, "the stub app-server is asked to start a turn")
            return
        }
        expect(
            server.received.contains(#""effort":"high""#),
            "reasoning effort belongs to the turn and does not mutate Codex settings")
        expect(
            !server.received.contains("config/value/write"),
            "a Tinycast turn never writes the user's Codex configuration")

        turn.cancel()
        let dropped = await server.awaitCondition { !server.runner.isActive }
        expect(dropped, "Stop drops a turn that nothing has named yet")

        // Only now does the server name the turn — after the runner has already let the thread go.
        server.mark("stop-landed")
        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "a Stop that beat turn/started still interrupts the turn that starts")
    }

    /// Both names arrive for the same Stopped turn. Interrupting per name would send two.
    static func aTurnNamedTwiceIsInterruptedOnce() async {
        guard let server = StubServer(mode: "hold-both") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let turn = server.startTurn()
        guard await server.awaitMark("turn-start-received") else {
            expect(false, "the stub app-server is asked to start a turn")
            return
        }

        turn.cancel()
        _ = await server.awaitCondition { !server.runner.isActive }
        server.mark("stop-landed")

        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "a Stopped turn is interrupted as soon as its ID arrives")
        // Give a second interrupt every chance to show up before ruling it out.
        _ = await server.awaitCondition(timeout: .milliseconds(400)) { server.interrupts > 1 }
        expect(server.interrupts == 1, "the turn's second name spends no second interrupt")
    }

    /// A second chat's turn used to end the first with "A newer request replaced this response."
    static func twoChatsStreamSideBySide() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        guard await server.awaitTurns(1) else {
            expect(false, "the first chat starts its turn")
            return
        }
        let second = server.collectTurn()
        guard await server.awaitTurns(2) else {
            expect(false, "the second chat starts its turn while the first is live")
            return
        }
        server.mark("release")

        let firstReply = await first.value
        let secondReply = await second.value
        expect(firstReply.error == nil, "the first chat is not replaced by the second")
        expect(firstReply.text == "from thread-1", "the first chat reads only its own thread")
        expect(
            firstReply.reasoning == "**Planning** done.\n\n**Checking**",
            "each summary part opens a paragraph, a split part does not: "
                + firstReply.reasoning.debugDescription)
        expect(secondReply.error == nil, "the second chat finishes too")
        expect(secondReply.text == "from thread-2", "the second chat reads only its own thread")
        expect(!server.runner.isActive, "both finished turns are released")
    }

    /// A reply and its title leave together, before the handshake the stub, like Codex, requires.
    static func twoChatsStartingColdShareOneHandshake() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        let second = server.collectTurn()
        guard await server.awaitTurns(2) else {
            expect(false, "both cold turns reach the server: \(server.received)")
            return
        }
        server.mark("release")
        let replies = [await first.value, await second.value]
        expect(
            replies.allSatisfy { $0.error == nil },
            "neither cold turn is sent before the handshake: \(replies.map { String(describing: $0.error) })")
        expect(
            server.received.split(separator: "\n").count { $0 == "initialize" } == 1,
            "one process, one handshake")
    }

    /// The server list is fixed at launch: a chat armed with another one takes the process away.
    static func aRelaunchEndsTheOtherChatsThreadWithAReason() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        guard await server.awaitTurns(1) else {
            expect(false, "the first chat starts its turn")
            return
        }
        let armed = server.startTurn(toolServers: server.session(allowing: true, asked: Box()))
        let reply = await first.value
        expect(
            String(describing: reply.error).contains("restarted"),
            "the stranded chat is told why its reply ended: \(String(describing: reply.error))")
        armed.cancel()
        _ = await armed.value
    }

    static func stoppingOneChatLeavesTheOther() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        guard await server.awaitTurns(1) else {
            expect(false, "the first chat starts its turn")
            return
        }
        let second = server.collectTurn()
        guard await server.awaitTurns(2) else {
            expect(false, "the second chat starts its turn while the first is live")
            return
        }
        first.cancel()
        _ = await first.value
        server.mark("release")

        let secondReply = await second.value
        expect(secondReply.error == nil, "Stop on one chat leaves the other streaming")
        expect(secondReply.text == "from thread-2", "the surviving chat keeps its own reply")
        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "the stopped chat's turn is interrupted")
        expect(!server.received.contains("interrupt:thread-2"), "the other chat's turn is not interrupted")
    }
}

/// What the runner asked about, collected across the hop the consent closure makes.
@MainActor
final class Box {
    var calls: [AIToolServerCall] = []
}

/// A reader who is asked once, takes a moment over it, and grants the server for the chat.
@MainActor
final class GrantingReader {
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

/// A real client against the stub server in `Tests/ai-fixtures/codex-stub.js`.
@MainActor
final class StubServer {
    let root: URL
    let client: CodexAppServerClient
    let runner: CodexTurnRunner

    init?(mode: String) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-turn-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executable = root.appending(path: "bin/codex")
        do {
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "Tests/ai-fixtures/codex-stub.js"), to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        } catch {
            print("the stub app-server could not be installed: \(error)")
            return nil
        }

        // The locator walks PATH, so the stub only sits in front of any real `codex`.
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "\(executable.deletingLastPathComponent().path):\(inherited)", 1)
        // The locator asks a login shell first; the user's rc files would put a real `codex` ahead.
        setenv("ZDOTDIR", root.path, 1)
        // `/etc/zprofile`'s path_helper puts a Homebrew `codex` ahead of the stub; undo that.
        try? #"export TINYCAST_SAVED_PATH="$PATH""#.write(
            to: root.appending(path: ".zshenv"), atomically: true, encoding: .utf8)
        try? #"[ -n "$TINYCAST_SAVED_PATH" ] && export PATH="$TINYCAST_SAVED_PATH""#.write(
            to: root.appending(path: ".zprofile"), atomically: true, encoding: .utf8)
        setenv("TC_STUB_ROOT", root.path, 1)
        setenv("TC_STUB_MODE", mode, 1)

        let client = CodexAppServerClient(
            codexHome: root.appending(path: "home", directoryHint: .isDirectory),
            workspace: root.appending(path: "work", directoryHint: .isDirectory))
        let runner = CodexTurnRunner(client: client)
        runner.connect = { servers in
            try await client.start(toolServers: servers)
            return []
        }
        client.onNotification = { method, params in
            runner.handle(method: method, params: params)
        }

        self.root = root
        self.client = client
        self.runner = runner
    }

    /// What the app does: a task iterating the provider stream, where Stop is its cancellation.
    func startTurn(
        effort: String? = nil, toolServers: AIToolServerSession? = nil
    ) -> Task<Void, Never> {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: effort, toolServers: toolServers)
        return Task {
            do {
                for try await _ in stream {}
            } catch {}
        }
    }

    func collect(toolServers: AIToolServerSession?) async -> [AIStreamEvent] {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: nil, toolServers: toolServers)
        var events: [AIStreamEvent] = []
        do {
            for try await event in stream { events.append(event) }
        } catch {}
        return events
    }

    func streamError(toolServers: AIToolServerSession?) async -> String? {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: nil, toolServers: toolServers)
        do {
            for try await _ in stream {}
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// One local server, whose secret tells two launches' lists apart.
    func servers(key: String = "s3cret") -> [AIToolServer] {
        [
            AIToolServer(
                handle: "probe", title: "Probe",
                transport: .command(
                    path: "/bin/echo", arguments: ["probe"], environment: ["API_KEY": key]))
        ]
    }

    /// A reader who answers every call the same way.
    func session(
        allowing: Bool, asked: Box, rounds: Int? = 10, servers: [AIToolServer]? = nil
    ) -> AIToolServerSession {
        let servers = servers ?? self.servers()
        return AIToolServerSession(rounds: rounds) {
            servers
        } consent: { call in
            await MainActor.run { asked.calls.append(call) }
            return allowing
        }
    }

    /// Collects one turn's text the way the transcript does, keeping whatever ended it.
    func collectTurn() -> Task<(text: String, reasoning: String, error: Error?), Never> {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: nil)
        return Task {
            var text = ""
            var reasoning = ""
            do {
                for try await event in stream {
                    if case .text(let delta) = event { text += delta }
                    if case .reasoning(let delta) = event { reasoning += delta }
                }
            } catch {
                return (text, reasoning, error)
            }
            return (text, reasoning, nil)
        }
    }

    func awaitTurns(_ count: Int) async -> Bool {
        await awaitCondition {
            self.received.split(separator: "\n").count { $0.hasPrefix("turn-params:") } >= count
        }
    }

    var received: String {
        (try? String(contentsOf: root.appending(path: "received.log"), encoding: .utf8)) ?? ""
    }

    var argv: [String] {
        decode(root.appending(path: "argv.log"))
    }

    /// App-servers started, one `argv.log` line each; a listing is not one of them.
    var launches: Int {
        text(root.appending(path: "argv.log")).split(separator: "\n").count
    }

    /// Listings started, one `list-argv.log` line each.
    var listed: Int {
        text(root.appending(path: "list-argv.log")).split(separator: "\n").count
    }

    var listArgv: [String] {
        decode(root.appending(path: "list-argv.log"))
    }

    var environment: [String: String] {
        guard let line = text(root.appending(path: "env.log")).split(separator: "\n").last,
            let data = line.data(using: .utf8),
            let values = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return values
    }

    private func decode(_ url: URL) -> [String] {
        guard let line = text(url).split(separator: "\n").last,
            let data = line.data(using: .utf8),
            let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return values
    }

    private func text(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    var interrupts: Int {
        received.split(separator: "\n").count { $0.hasPrefix("interrupt:") }
    }

    func mark(_ name: String) {
        FileManager.default.createFile(atPath: root.appending(path: name).path, contents: nil)
    }

    func awaitMark(_ name: String) async -> Bool {
        await awaitCondition {
            FileManager.default.fileExists(atPath: self.root.appending(path: name).path)
        }
    }

    func awaitLog(_ line: String) async -> Bool {
        await awaitCondition { self.received.contains(line) }
    }

    /// Polls rather than sleeping, so a pass costs what it needs and a failure still ends.
    func awaitCondition(
        timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func tearDown() {
        client.stop()
        try? FileManager.default.removeItem(at: root)
    }
}
