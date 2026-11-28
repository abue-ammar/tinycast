import Foundation
import Observation
import Testing

@testable import Tinycast

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MCPStdioTests {
    @Test func aHandshakeEndsInTheToolsItListedNamespacedByHandle() async throws {
        let stub = try await StubServer()
        let connection = stub.connection
        defer { stub.connection.stop() }
        await connection.start()
        #expect(connection.status == .ready(tools: 2))
        #expect(connection.tools.map(\.wireName) == ["stub__read_file", "stub__write_file"])
    }

    @Test func argumentsReachTheServerAndItsTextComesBackAsContent() async throws {
        let stub = try await StubServer()
        let connection = stub.connection
        defer { stub.connection.stop() }
        await connection.start()
        let (text, isError) = try await connection.call(
            "read_file", arguments: .object(["path": .string("/tmp/x")]))
        #expect(text == #"{"path":"/tmp/x"}"#)
        #expect(!isError)
    }

    /// `isError` is the tool saying no, which the model can read and work around.
    @Test func aToolsOwnRefusalIsContentTheModelCanRead() async throws {
        let stub = try await StubServer()
        let connection = stub.connection
        defer { stub.connection.stop() }
        await connection.start()
        let (text, isError) = try await connection.call("write_file", arguments: .object([:]))
        #expect(isError)
        #expect(text == "read only")
    }

    @Test func aServerThatRefusesToStartShowsWhatItPrinted() async throws {
        let stub = try await StubServer(mode: "die-on-initialize")
        let connection = stub.connection
        defer { stub.connection.stop() }
        await connection.start()
        let message = try #require(refusal(in: connection.status))
        #expect(message.contains("refused to start"))
        #expect(connection.tools.isEmpty)
        #expect(connection.isIdle, "startable again, so the next visit to chat retries")
    }

    /// A pending call has to be failed by the exit, or the turn waits on a process that is gone.
    @Test func aServerThatDiesMidCallFailsThatCall() async throws {
        let stub = try await StubServer(mode: "die-on-call")
        let connection = stub.connection
        defer { stub.connection.stop() }
        await connection.start()
        #expect(connection.status.isReady)
        await #expect(throws: (any Error).self) {
            _ = try await connection.call("read_file", arguments: .object([:]))
        }
        #expect(!connection.status.isReady)
    }

    @Test func anUnsolicitedServerRequestIsDeclinedWithoutDerailingTheHandshake() async throws {
        let stub = try await StubServer(mode: "unsolicited-request")
        let connection = stub.connection
        defer { stub.connection.stop() }
        await connection.start()
        #expect(connection.status.isReady)
    }

    @Test func theManagerStartsWhatSettingsHoldsAndStoppingWithdrawsIt() async throws {
        let stub = try await StubServer()
        let keychain = KeychainSecretStore(scope: "MCPStdioTests-\(UUID().uuidString)")
        let manager = MCPServerManager(secrets: MCPSecretStore(keychain: keychain))
        manager.reconcile([stub.server])
        let id = stub.server.id
        for await ready in Observations({ @MainActor in manager.status(of: id).isReady }) where ready {
            break
        }
        #expect(manager.tools.count == 2)

        manager.stop()
        #expect(manager.tools.isEmpty)
        #expect(manager.status(of: stub.server.id) == .stopped)
    }

    private func refusal(in status: MCPServerStatus) -> String? {
        if case .failed(let message) = status { message } else { nil }
    }
}

/// The stub server, installed in a scratch directory of its own and launched by absolute path.
@MainActor
private final class StubServer {
    let server: MCPServer
    /// Its environment carries the mode, so parallel tests never share one.
    let connection: MCPServerConnection
    private let scratch: ScratchDirectory

    init(mode: String = "normal") async throws {
        scratch = try ScratchDirectory("mcp-stdio")
        let stub = try await NodeScript("MCP/mcp-stub.js", in: scratch, named: "tinycast-mcp-stub")
        server = MCPServer(
            name: "Stub", slug: "stub",
            transport: .stdio(command: stub.executable.path, arguments: [], environmentKeys: []))
        connection = MCPServerConnection(
            server: server, secrets: MCPSecretStore.Secrets(environment: ["TC_MCP_MODE": mode]))
    }
}
