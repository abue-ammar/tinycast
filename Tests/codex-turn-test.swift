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
        await theRoundCapInterruptsTheTurn()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// The launch is the whole boundary: Tinycast's servers named, the user's disabled, and not a
    /// byte of either written to their Codex configuration.
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
        expect(
            argv.contains(#"mcp_servers.probe.command="/bin/echo""#),
            "Tinycast's own server is named on the launch line")
        expect(
            argv.contains(#"mcp_servers.probe.default_tools_approval_mode="prompt""#),
            "in the mode that asks for every tool, so one marked read-only cannot run unasked")
        expect(
            argv.contains("mcp_servers.user-one.enabled=false")
                && argv.contains("mcp_servers.user-two.enabled=false"),
            "and every server the user configured for their own Codex is disabled by name")
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
            server.environment["TC_MCP_PROBE_API_KEY"] == "s3cret",
            "the value reached the child's environment instead")
        expect(
            !server.received.contains("config/value/write")
                && !server.received.contains("config/batchWrite"),
            "and nothing was written to the user's Codex configuration")
        expect(
            server.received.contains(#""approvalPolicy":"untrusted""#),
            "the thread asks before a tool runs, rather than refusing every call")
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
}

/// What the runner asked about, collected across the hop the consent closure makes.
@MainActor
final class Box {
    var calls: [AIToolServerCall] = []
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

    /// One local server, and a reader who answers every call the same way.
    func session(allowing: Bool, asked: Box, rounds: Int = 10) -> AIToolServerSession {
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

    var received: String {
        (try? String(contentsOf: root.appending(path: "received.log"), encoding: .utf8)) ?? ""
    }

    var argv: [String] {
        decode(root.appending(path: "argv.log"))
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
