// A remote server end to end over both HTTP shapes: Streamable HTTP (JSON and an SSE stream left
// open), the 2024-11-05 HTTP+SSE fallback, version negotiation, session expiry, paging and routing.

import Foundation

@main
@MainActor
struct MCPHTTPTests {
    static var failures = 0
    static var passes = 0
    static var base = ""

    static func expect(_ condition: Bool, _ message: String) {
        if condition { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async {
        guard let stub = launchStub() else {
            print("FAIL: the HTTP stub server did not start")
            exit(1)
        }
        defer { stub.terminate() }

        await aJSONServerHandshakesInOrder()
        await anSSEAnswerIsReadBeforeTheStreamCloses()
        await anOlderProtocolVersionIsHeldTo()
        await anExpiredSessionIsReopenedOnce()
        await everyToolPageIsListed()
        await aLegacyServerIsReachedOverSSE()
        await aLegacyEndpointOnAnotherOriginIsRefused()
        await aNonASCIIServerRoutesByLookup()
        await aCancelledStartDoesNotStickAtConnecting()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func connection(_ path: String, name: String = "Stub") -> MCPServerConnection {
        let server = MCPServer(
            name: name, slug: MCPSlug.make(from: name, existing: []),
            transport: .http(url: base + path, headerName: ""))
        return MCPServerConnection(server: server, secrets: MCPSecretStore.Secrets())
    }

    static func aJSONServerHandshakesInOrder() async {
        await reset()
        let connection = connection("/json/mcp")
        await connection.start()
        expect(connection.status == .ready(tools: 2), "a JSON server lists its tools: \(connection.status)")
        let stats = await stats()
        expect(stats["listBeforeInitialized"] == 0, "initialized is on the server before tools/list")
        expect(stats["versionMismatches"] == 0, "every request names the negotiated version")
        let answer = try? await connection.call("tool_1", arguments: .object(["a": .number(1)]))
        expect(answer?.0 == #"tool_1:{"a":1}"#, "a call reaches the tool by its own name")
        connection.stop()
    }

    static func anSSEAnswerIsReadBeforeTheStreamCloses() async {
        await reset()
        let connection = connection("/sse-open/mcp")
        let started = ContinuousClock.now
        await connection.start()
        expect(connection.status == .ready(tools: 2), "an SSE answer is read as it arrives")
        let answer = try? await connection.call("tool_0", arguments: .object([:]))
        expect(answer?.0 == "tool_0:{}", "and a call on a stream left open still returns")
        expect(
            ContinuousClock.now - started < .seconds(10),
            "without waiting for the server to close the stream")
        try? await Task.sleep(for: .milliseconds(200))
        expect((await stats()["pings"] ?? 0) >= 1, "a ping mid-answer is answered")
        connection.stop()
    }

    static func anOlderProtocolVersionIsHeldTo() async {
        await reset()
        let connection = connection("/old/mcp")
        await connection.start()
        expect(connection.status.isReady, "a 2024-11-05 server connects")
        _ = try? await connection.call("tool_0", arguments: .object([:]))
        expect(
            await stats()["versionMismatches"] == 0,
            "and every later request names the version it chose, not Tinycast's newest")
        connection.stop()
    }

    static func anExpiredSessionIsReopenedOnce() async {
        await reset()
        let connection = connection("/expire/mcp")
        await connection.start()
        let first = try? await connection.call("tool_0", arguments: .object([:]))
        expect(first?.0 == "tool_0:{}", "the first call answers, then the server forgets the session")
        let second = try? await connection.call("tool_1", arguments: .object([:]))
        expect(second?.0 == "tool_1:{}", "a 404 for the session re-initializes and retries the call")
        expect(await stats()["initializes"] == 2, "with exactly one fresh initialize")
        expect(connection.status.isReady, "and the connection stays ready")
        connection.stop()
    }

    static func everyToolPageIsListed() async {
        await reset()
        let connection = connection("/paged/mcp")
        await connection.start()
        expect(connection.status == .ready(tools: 5), "every page of tools/list is followed")
        expect(await stats()["listPages"] == 3, "until a page has no nextCursor")
        connection.stop()
    }

    static func aLegacyServerIsReachedOverSSE() async {
        await reset()
        let connection = connection("/legacy/sse")
        await connection.start()
        expect(connection.status == .ready(tools: 2), "a 405 falls back to HTTP+SSE: \(connection.status)")
        let answer = try? await connection.call("tool_1", arguments: .object(["x": .string("y")]))
        expect(answer?.0 == #"tool_1:{"x":"y"}"#, "and a call's answer comes back on the stream")
        try? await Task.sleep(for: .milliseconds(200))
        expect((await stats()["pings"] ?? 0) >= 1, "a ping on the legacy stream is answered")
        connection.stop()
    }

    static func aLegacyEndpointOnAnotherOriginIsRefused() async {
        await reset()
        let connection = connection("/legacy-evil/sse")
        await connection.start()
        guard case .failed(let message) = connection.status else {
            return expect(false, "an endpoint on another origin fails the connection: \(connection.status)")
        }
        expect(message.contains("another origin"), "and says why: \(message)")
    }

    static func aNonASCIIServerRoutesByLookup() async {
        await reset()
        let server = MCPServer(
            name: "文件", slug: MCPSlug.make(from: "文件", existing: []),
            transport: .http(url: base + "/json/mcp", headerName: ""))
        let manager = MCPServerManager(secrets: MCPSecretStore(keychain: .init(scope: "mcp-http-test")))
        manager.reconcile([server])
        let deadline = ContinuousClock.now + .seconds(10)
        while !manager.status(of: server.id).isReady, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let wire = manager.tools.map(\.wireName).sorted()
        expect(
            wire == ["wen-jian__tool_0", "wen-jian__tool_1"],
            "a Chinese name gets a usable handle: \(wire)")
        let route = manager.route("wen-jian__tool_1")
        expect(route?.tool.name == "tool_1" && route?.tool.serverID == server.id, "the wire name routes back")
        let answer = try? await route?.connection.call("tool_1", arguments: .object([:]))
        expect(answer?.0 == "tool_1:{}", "and the call lands")
        manager.stop()
    }

    static func aCancelledStartDoesNotStickAtConnecting() async {
        await reset()
        let connection = connection("/slow/mcp")
        let task = Task { await connection.start() }
        try? await Task.sleep(for: .milliseconds(300))
        expect(connection.status == .connecting, "a slow initialize is still connecting")
        task.cancel()
        await task.value
        expect(connection.status == .stopped, "a cancelled start goes back to stopped: \(connection.status)")
        expect(connection.isIdle, "so the next visit to chat starts it again")
    }

    // MARK: - Stub

    static func launchStub() -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "Tests/ai-fixtures/mcp-http-stub.js"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        let line = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        guard line.hasPrefix("ready "),
            let port = Int(line.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            process.terminate()
            return nil
        }
        base = "http://127.0.0.1:\(port)"
        return process
    }

    static func stats() async -> [String: Int] {
        guard let url = URL(string: base + "/stats"),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { return [:] }
        return object
    }

    static func reset() async {
        guard let url = URL(string: base + "/reset") else { return }
        _ = try? await URLSession.shared.data(from: url)
    }
}
