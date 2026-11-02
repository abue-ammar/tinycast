import Foundation

@main
@MainActor
struct CodexClientTests {
    static var failures = 0

    static func main() async throws {
        if CommandLine.arguments.contains("mcp") {
            print("[]")
            return
        }
        if CommandLine.arguments.last == "app-server" {
            try peer()
            return
        }
        try await cancelledAndExpiredWritesAreSkipped()
        try await stoppingDropsQueuedWrites()
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func cancelledAndExpiredWritesAreSkipped() async throws {
        let (client, root) = try await pausedClient()
        defer {
            client.stop()
            try? FileManager.default.removeItem(at: root)
        }
        var filling = false
        let bulk = Task {
            filling = true
            return try await client.request(
                method: "bulk", params: ["data": String(repeating: "x", count: 4_000_000)],
                timeout: .seconds(5))
        }
        while !filling { await Task.yield() }
        var queued = false
        let cancelled = Task {
            queued = true
            return try await client.request(method: "cancelled")
        }
        while !queued { await Task.yield() }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            expect(false, "cancellation finishes the waiting request")
        } catch {
            expect(error is CancellationError, "cancellation preserves CancellationError")
        }
        do {
            _ = try await client.request(method: "expired", timeout: .milliseconds(50))
            expect(false, "a queued request can time out while stdin is blocked")
        } catch CodexAppServerClient.ClientError.timedOut {
        } catch {
            expect(false, "a queued request reports its timeout: \(error)")
        }
        let alreadyCancelled = Task { try await client.request(method: "already-cancelled") }
        alreadyCancelled.cancel()
        _ = await alreadyCancelled.result
        try Data().write(to: root.appendingPathComponent("resume"))
        _ = try await bulk.value
        _ = try await client.request(method: "barrier")
        let received = try String(contentsOf: root.appendingPathComponent("received"), encoding: .utf8)
        expect(!received.contains("cancelled"), "cancelled writes never reach the peer")
        expect(!received.contains("expired"), "expired writes never reach the peer")
        expect(received.contains("bulk\nbarrier"), "an in-flight frame finishes before the next write")
    }

    static func stoppingDropsQueuedWrites() async throws {
        let (client, root) = try await pausedClient()
        defer {
            client.stop()
            try? FileManager.default.removeItem(at: root)
        }
        var filling = false
        let bulk = Task {
            filling = true
            return try await client.request(
                method: "bulk", params: ["data": String(repeating: "x", count: 4_000_000)])
        }
        while !filling { await Task.yield() }
        var queued = false
        let queuedWrite = Task {
            queued = true
            return try await client.request(method: "stopped")
        }
        while !queued { await Task.yield() }
        client.stop()
        _ = await bulk.result
        _ = await queuedWrite.result
        try Data().write(to: root.appendingPathComponent("resume"))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("exited").path),
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("exited").path),
            "Stop closes stdin after the in-flight frame")
        let received = try String(contentsOf: root.appendingPathComponent("received"), encoding: .utf8)
        expect(!received.contains("stopped"), "Stop retires writes still waiting on the queue")
    }

    static func pausedClient() async throws -> (CodexAppServerClient, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-client-test-\(UUID().uuidString)")
        let client = CodexAppServerClient(workspace: root)
        client.launchSettings = {
            InstalledAILaunch(
                commandPath: CommandLine.arguments[0], environment: ["TINYCAST_TEST_CODEX_ROOT": root.path])
        }
        try await client.start()
        _ = try await client.request(method: "pause")
        return (client, root)
    }

    static func peer() throws {
        guard let path = ProcessInfo.processInfo.environment["TINYCAST_TEST_CODEX_ROOT"] else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = URL(fileURLWithPath: path)
        let log = root.appendingPathComponent("received")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? Data().write(to: root.appendingPathComponent("exited"))
        }
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let method = request["method"] as? String
            else { continue }
            try handle.write(contentsOf: Data("\(method)\n".utf8))
            if let id = request["id"] as? Int {
                var reply = try JSONSerialization.data(withJSONObject: ["id": id, "result": [:]])
                reply.append(0x0A)
                try FileHandle.standardOutput.write(contentsOf: reply)
            }
            if method == "pause" {
                while !FileManager.default.fileExists(atPath: root.appendingPathComponent("resume").path) {
                    Thread.sleep(forTimeInterval: 0.002)
                }
            }
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
