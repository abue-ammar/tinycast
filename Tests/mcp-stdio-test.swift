// A local server end to end: handshake, listing, calling, and every way one can go away.

import Foundation

@main
@MainActor
struct MCPStdioTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async {
        await aServerConnectsListsAndAnswers()
        await aToolsOwnFailureIsContentNotAnError()
        await aServerThatRefusesToStartSaysWhy()
        await aServerThatDiesMidCallFailsThatCall()
        await anUnsolicitedServerRequestIsDeclined()
        await stoppingLeavesNothingRunning()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func aServerConnectsListsAndAnswers() async {
        guard let stub = StubMCPServer() else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        expect(connection.status == .ready(tools: 2), "a handshake ends in the tools it listed")
        expect(
            connection.tools.map(\.wireName) == ["stub__read_file", "stub__write_file"],
            "and every tool arrives namespaced by the handle that routes it")

        let answer = try? await connection.call(
            "read_file", arguments: .object(["path": .string("/tmp/x")]))
        expect(
            answer?.0 == #"{"path":"/tmp/x"}"# && answer?.1 == false,
            "arguments reach the server intact and its text comes back as content")
        connection.stop()
    }

    /// `isError` is the tool saying no, which the model can read and work around.
    static func aToolsOwnFailureIsContentNotAnError() async {
        guard let stub = StubMCPServer() else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        let answer = try? await connection.call("write_file", arguments: .object([:]))
        expect(answer?.1 == true, "a refusing tool is marked as one")
        expect(answer?.0 == "read only", "and its reason survives to the model")
        connection.stop()
    }

    static func aServerThatRefusesToStartSaysWhy() async {
        guard let stub = StubMCPServer(mode: "die-on-initialize") else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        guard case .failed(let message) = connection.status else {
            expect(false, "a server that exits during the handshake ends up failed")
            return
        }
        expect(
            message.contains("refused to start"),
            "and the row shows what the server itself printed, not a generic sentence")
        expect(connection.tools.isEmpty, "a failed server offers nothing")
        expect(
            connection.isIdle,
            "and is startable again, so the next visit to chat retries rather than staying broken")
    }

    /// A pending call has to be failed by the exit, or the turn waits on a process that is gone.
    static func aServerThatDiesMidCallFailsThatCall() async {
        guard let stub = StubMCPServer(mode: "die-on-call") else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        expect(connection.status.isReady, "the server starts before it is asked to die")
        do {
            _ = try await connection.call("read_file", arguments: .object([:]))
            expect(false, "a call to a server that exits throws rather than hanging")
        } catch {
            expect(true, "a call to a server that exits throws rather than hanging")
        }
        expect(!connection.status.isReady, "and the connection stops claiming to be ready")
    }

    static func anUnsolicitedServerRequestIsDeclined() async {
        guard let stub = StubMCPServer(mode: "unsolicited-request") else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        expect(
            connection.status.isReady,
            "a server asking Tinycast for something is declined without derailing the handshake")
        connection.stop()
    }

    static func stoppingLeavesNothingRunning() async {
        guard let stub = StubMCPServer() else { return }
        defer { stub.tearDown() }

        let manager = MCPServerManager(secrets: MCPSecretStore(keychain: .init(scope: "mcp-test")))
        manager.reconcile([stub.server])
        let ready = await stub.awaitCondition { manager.status(of: stub.server.id).isReady }
        expect(ready, "the manager starts what Settings holds")
        expect(manager.tools.count == 2, "and publishes what it found")

        manager.stop()
        expect(manager.tools.isEmpty, "stopping withdraws every tool")
        expect(manager.status(of: stub.server.id) == .stopped, "and forgets the connection")
    }
}

@MainActor
final class StubMCPServer {
    let root: URL
    let server: MCPServer

    init?(mode: String = "normal") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mcp-stdio-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executable = root.appending(path: "bin/tinycast-mcp-stub")
        do {
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "Tests/ai-fixtures/mcp-stub.js"), to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        } catch {
            print("FAIL: the stub MCP server could not be installed: \(error)")
            return nil
        }
        // The locator walks PATH, so the stub is found the way a real server would be.
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "\(executable.deletingLastPathComponent().path):\(inherited)", 1)
        setenv("TC_MCP_MODE", mode, 1)

        self.root = root
        server = MCPServer(
            name: "Stub", slug: "stub",
            transport: .stdio(
                command: "tinycast-mcp-stub", arguments: [], environmentKeys: []))
    }

    func connection() -> MCPServerConnection {
        MCPServerConnection(server: server, secrets: MCPSecretStore.Secrets())
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
        try? FileManager.default.removeItem(at: root)
    }
}
