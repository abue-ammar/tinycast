import Foundation
import Testing

@testable import Tinycast

extension AIProviderTests {
    @Test func aCodexRequestFrameKeepsItsNumericIDAndMethod() throws {
        let frame = try CodexAppServerProtocol.request(
            id: 7, method: "account/read", params: ["refreshToken": false])
        let object = try #require(try JSONSerialization.jsonObject(with: frame) as? [String: Any])
        #expect(object["id"] as? Int == 7)
        #expect(object["method"] as? String == "account/read")
    }

    @Test func aCodexResponseRoutesToItsRequestWithItsValues() throws {
        let frame = CodexAppServerProtocol.parse(Data(#"{"id":7,"result":{"ok":true}}"#.utf8))
        guard case .response(let id, let result) = frame else {
            Issue.record("a valid Codex response parses as one, not \(String(describing: frame))")
            return
        }
        #expect(id == 7, "it routes to the pending request")
        #expect(result["ok"]?.boolValue == true, "it keeps a boolean a boolean")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aWriteCancelledWhileQueuedNeverReachesCodex() async throws {
        let codex = try await PausedCodex()
        defer { codex.client.stop() }
        let bulk = codex.sendBulk()
        let cancelled = Task.immediate { try await codex.client.request(method: "cancelled") }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }

        let received = try await codex.resumeThroughBarrier(after: bulk)
        #expect(!received.contains("cancelled"))
        #expect(received.contains("bulk\nbarrier"), "the retired write left nothing between")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aRequestCancelledBeforeItStartsIsNeverWritten() async throws {
        let codex = try await PausedCodex()
        defer { codex.client.stop() }
        let bulk = codex.sendBulk()
        let cancelled = Task { try await codex.client.request(method: "already-cancelled") }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }

        let received = try await codex.resumeThroughBarrier(after: bulk)
        #expect(!received.contains("already-cancelled"))
        #expect(received.contains("bulk\nbarrier"))
    }

    /// Codex's input is full while it holds, so the write waits its turn when the time runs out.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aQueuedWriteTimesOutAndNeverReachesCodex() async throws {
        let codex = try await PausedCodex()
        defer { codex.client.stop() }
        let bulk = codex.sendBulk()
        let error = await #expect(throws: CodexAppServerClient.ClientError.self) {
            _ = try await codex.client.request(method: "expired", timeout: .milliseconds(50))
        }
        let timedOut = if case .timedOut? = error { true } else { false }
        #expect(timedOut, "it reports its timeout, not \(String(describing: error))")

        let received = try await codex.resumeThroughBarrier(after: bulk)
        #expect(!received.contains("expired"))
        #expect(received.contains("bulk\nbarrier"))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aWriteQueuedBehindAnInFlightFrameArrivesWholeAfterIt() async throws {
        let codex = try await PausedCodex()
        defer { codex.client.stop() }
        let bulk = codex.sendBulk()
        let barrier = Task.immediate { try await codex.client.request(method: "barrier") }
        try codex.resume()
        _ = try await bulk.value
        _ = try await barrier.value
        #expect(try codex.received().contains("bulk\nbarrier\n"))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func stopRetiresQueuedWritesAndClosesInputAfterTheInFlightFrame() async throws {
        let codex = try await PausedCodex()
        let bulk = codex.sendBulk()
        let queued = Task.immediate { try await codex.client.request(method: "stopped") }
        codex.client.stop()
        _ = await bulk.result
        _ = await queued.result
        try codex.resume()

        try await codex.waitForEndOfInput()
        let received = try codex.received()
        #expect(!received.contains("stopped"), "Stop retires writes still waiting on the queue")
        #expect(received.hasSuffix("bulk\neof\n"), "the in-flight frame arrives whole, then the input ends")
    }
}

/// A launched Codex stub that has answered `pause` and reads nothing more until it is resumed.
@MainActor
private final class PausedCodex {
    let client: CodexAppServerClient
    private let scratch: ScratchDirectory
    private let root: URL

    init() async throws {
        scratch = try ScratchDirectory("codex-app-server")
        root = scratch.url.appending(path: "peer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "received"))
        let stub = try await NodeScript("AI/codex-app-server-stub.js", in: scratch, named: "codex")
        let launch = InstalledAILaunch(
            commandPath: stub.executable.path, environment: ["TC_CODEX_STUB_ROOT": root.path])
        client = CodexAppServerClient(workspace: scratch.url.appending(path: "workspace"))
        client.launchSettings = { launch }
        try await client.start()
        _ = try await client.request(method: "pause")
    }

    /// Larger than the pipe holds, so it stays in flight until Codex reads again.
    func sendBulk() -> Task<[String: JSONValue], Error> {
        Task.immediate { [client] in
            try await client.request(
                method: "bulk", params: ["data": String(repeating: "x", count: 4_000_000)],
                timeout: .seconds(5))
        }
    }

    func resume() throws {
        try Data().write(to: root.appending(path: "resume"))
    }

    /// The log once a write sent after the in-flight frame has been answered.
    func resumeThroughBarrier(after bulk: Task<[String: JSONValue], Error>) async throws -> String {
        try resume()
        _ = try await bulk.value
        _ = try await client.request(method: "barrier")
        return try received()
    }

    func received() throws -> String {
        try String(contentsOf: root.appending(path: "received"), encoding: .utf8)
    }

    func waitForEndOfInput() async throws {
        try await Self.waitForLastLine("eof", in: root.appending(path: "received"))
    }

    /// Woken by each write to the log rather than by a timer; Stop's own backstop would kill it.
    nonisolated private static func waitForLastLine(_ line: String, in log: URL) async throws {
        let descriptor = open(log.path, O_EVTONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let (writes, continuation) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend], queue: .global())
        source.setEventHandler { continuation.yield() }
        source.setCancelHandler { close(descriptor) }
        source.activate()
        defer { source.cancel() }
        continuation.yield()
        for await _ in writes
        where (try? String(contentsOf: log, encoding: .utf8))?.hasSuffix(line + "\n") == true {
            return
        }
    }
}
