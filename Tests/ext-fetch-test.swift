import Foundation

@MainActor
enum ExtensionFetchTests {
    private struct ServerState: Decodable {
        let port: Int
        let opened: Int
        let closed: Int
        let holding: Int
        let slow: Int
    }

    private static func expect(_ condition: Bool, _ message: String) {
        ExtensionTests.check(message, condition)
    }

    private static func readState(_ file: URL) -> ServerState? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ServerState.self, from: data)
    }

    private static func waitForState(_ file: URL, matching predicate: (ServerState) -> Bool) async -> Bool {
        for _ in 0..<150 {
            if let state = readState(file), predicate(state) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private static func request(
        _ fetcher: ExtensionFetcher, url: String, token: String = ""
    ) async throws -> String {
        let result = try await fetcher.request(
            .object([
                "url": .string(url), "headers": .object(["Authorization": .string(token)])
            ]))
        guard let encoded = result["bodyBase64"] as? String, let data = Data(base64Encoded: encoded),
            let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    private static func transientRequest(_ url: String) async throws {
        let fetcher = ExtensionFetcher()
        _ = try await request(fetcher, url: url)
    }

    private static func sharedRequests(_ url: String, stateFile: URL) async throws {
        let fetcher = ExtensionFetcher()
        let cancelled = Task { try await request(fetcher, url: url + "/hold", token: "fixture-a") }
        let started = await waitForState(stateFile) { $0.holding == 1 }
        expect(started, "request reaches the server before cancellation")
        let survivor = Task { try await request(fetcher, url: url + "/slow", token: "fixture-b") }
        let concurrent = await waitForState(stateFile) { $0.slow == 1 }
        expect(concurrent, "requests overlap on the shared transport")
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            expect(false, "cancelled fetch returns cancellation")
        } catch {
            expect(
                (error as? URLError)?.code == .cancelled || error is CancellationError,
                "cancelled fetch returns cancellation")
        }
        let text = try await survivor.value
        expect(
            text.contains("fixture-b") && !text.contains("fixture-a"),
            "cancelling one request preserves another request and its headers")
        let next = try await request(fetcher, url: url + "/echo")
        expect(
            next == #"{"authorization":"","cookie":""}"#,
            "reused transport carries neither previous authorization nor response cookies")
    }

    static func runChecks() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tinycast-fetch-\(UUID())")
        let stateFile = directory.appendingPathComponent("state.json")
        let server = Process()
        defer {
            if server.isRunning { server.terminate(); server.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("ext-fixtures/http-server.js")
            server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            server.arguments = ["node", fixture.path, stateFile.path]
            server.standardOutput = FileHandle.nullDevice
            try server.run()
            let ready = await waitForState(stateFile) { $0.port != 0 }
            guard ready, let state = readState(stateFile) else {
                expect(false, "HTTP fixture starts")
                return
            }
            let url = "http://127.0.0.1:\(state.port)"
            for _ in 0..<20 { try await transientRequest(url) }
            let released = await waitForState(stateFile) { $0.opened >= 20 && $0.closed == $0.opened }
            expect(released, "discarding transient fetchers closes all HTTP connections")
            try await sharedRequests(url, stateFile: stateFile)
            let sharedReleased = await waitForState(stateFile) { $0.closed == $0.opened }
            expect(sharedReleased, "shared transport closes its connections when its owner releases it")
            try await socketChecks(in: directory)
        } catch {
            expect(false, "HTTP fixture: \(error)")
        }
    }

    private static func socketChecks(in directory: URL) async throws {
        let socketPath = "/tmp/tinycast-\(UUID().uuidString).sock"
        let stateFile = directory.appendingPathComponent("unix-state.json")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("ext-fixtures/unix-server.js")
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["node", fixture.path, stateFile.path, socketPath]
        server.standardOutput = FileHandle.nullDevice
        let exit = try server.runObservingExit()
        defer {
            if server.isRunning { server.terminate() }
            exit.wait()
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        guard await waitForState(stateFile, matching: { $0.port != 0 }) else {
            expect(false, "Unix HTTP fixture starts")
            return
        }
        let fetcher = ExtensionFetcher()
        func fetch(_ path: String, method: String = "GET", body: Data? = nil) async throws -> [String: Any] {
            try await fetcher.request(.object([
                "url": .string("http://unresolvable.invalid" + path),
                "socketPath": .string(socketPath), "method": .string(method),
                "headers": .object(["Authorization": .string("socket-token")]),
                "bodyBase64": body.map { .string($0.base64EncodedString()) } ?? .null
            ]))
        }
        func decodedBody(_ result: [String: Any]) -> Data {
            Data(base64Encoded: result["bodyBase64"] as? String ?? "") ?? Data()
        }
        let payload = Data(repeating: 255, count: 100_000)
        let posted = try await fetch("/containers/create?name=fixture", method: "POST", body: payload)
        let echo = try JSONSerialization.jsonObject(with: decodedBody(posted)) as? [String: String]
        expect(posted["status"] as? Int == 201, "Unix HTTP preserves the response status")
        expect(echo?["path"] == "/containers/create?name=fixture" && echo?["method"] == "POST",
            "Unix HTTP preserves the API path, query and method")
        expect(echo?["body"] == String(repeating: "ff", count: payload.count),
            "Unix HTTP sends a large binary request body without blocking")
        expect(echo?["authorization"] == "socket-token" && echo?["cookie"] == "",
            "Unix HTTP carries request headers without retaining response cookies")
        let headers = posted["headers"] as? [String: String]
        expect(headers?["x-socket-probe"] == "unix" && headers?["set-cookie"]?.contains("b=2") == true,
            "Unix HTTP preserves response headers including repeated cookies")
        let binary = try await fetch("/binary")
        expect(decodedBody(binary) == Data([0, 255, 1, 10]), "Unix HTTP decodes compressed binary responses")
        let missing = try await fetch("/missing")
        expect(missing["status"] as? Int == 404 && !decodedBody(missing).isEmpty,
            "Unix HTTP returns error status and body to the extension")
        let empty = try await fetch("/empty")
        expect(empty["status"] as? Int == 204 && decodedBody(empty).isEmpty,
            "Unix HTTP handles an empty response")
        let head = try await fetch("/containers/json", method: "HEAD")
        expect(head["status"] as? Int == 201 && decodedBody(head).isEmpty, "Unix HTTP handles HEAD")
        try await socketConcurrencyCheck(fetcher, socketPath: socketPath)
        let cancelled = Task { _ = try await fetch("/hold") }
        expect(await waitForState(stateFile) { $0.holding == 1 }, "Unix request starts before cancellation")
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            expect(false, "Unix request observes cancellation")
        } catch {
            expect(error is CancellationError, "Unix request observes cancellation")
        }
        let survivor = try await fetch("/images/json")
        expect(survivor["status"] as? Int == 201, "Unix transport remains usable after cancellation")
        try await socketRuntimeCheck(directory: directory, socketPath: socketPath)
        expect(await waitForState(stateFile) { $0.opened == $0.closed },
            "Unix requests close their connections, including the cancelled request")
        do {
            _ = try await fetcher.request(.object([
                "url": .string("http://localhost/containers/json"),
                "socketPath": .string(socketPath + ".missing")
            ]))
            expect(false, "Missing Unix socket fails without falling back to TCP")
        } catch {
            if case .socketUnavailable(let path) = error as? ExtensionFetcher.FetchError {
                expect(path == socketPath + ".missing",
                    "Missing Unix socket fails without falling back to TCP")
                expect(error.localizedDescription.contains("Start its app or check the socket path"),
                    "Missing Unix socket reports an actionable error instead of an NSURL error code")
            } else {
                expect(false, "Missing Unix socket reports its connection failure")
            }
        }
    }

    private static func socketConcurrencyCheck(_ fetcher: ExtensionFetcher, socketPath: String) async throws {
        let spec = RenderValue.object([
            "url": .string("http://localhost/slow"), "socketPath": .string(socketPath)
        ])
        let requests = (0..<(ProcessInfo.processInfo.activeProcessorCount * 2)).map { _ in
            Task { _ = try await fetcher.request(spec) }
        }
        defer { for request in requests { request.cancel() } }
        let responsive = await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                let clock = ContinuousClock()
                let enqueued = clock.now
                Task.detached {
                    continuation.resume(returning: enqueued.duration(to: clock.now) < .seconds(1))
                }
            }
        }
        expect(responsive, "Slow Unix requests leave unrelated Swift tasks responsive")
        for request in requests { try await request.value }
    }

    private static func socketRuntimeCheck(directory: URL, socketPath: String) async throws {
        let (runtime, host, recorder) = ExtensionTests.makeRuntime()
        defer { runtime.shutdown() }
        try await runtime.boot(config: .current(supportDirectory: directory))
        let code = """
            exports.default = async () => {
              const assert = require("assert"), http = require("http");
              const api = require("@raycast/api");
              const body = await new Promise((resolve, reject) => {
                const req = http.request({ socketPath: api.getPreferenceValues().socketPath,
                  path: "/containers/json?all=1" }, (res) => {
                  assert.equal(res.statusCode, 201);
                  assert.equal(res.headers["set-cookie"].length, 2);
                  const chunks = [];
                  res.on("data", (chunk) => chunks.push(chunk));
                  res.on("end", () => resolve(Buffer.concat(chunks).toString()));
                });
                req.on("error", reject); req.end();
              });
              assert.equal(JSON.parse(body).path, "/containers/json?all=1");
              await api.showHUD("Docker socket passed");
            };
            """
        await runtime.start(session: "socket", code: code, file: directory.appendingPathComponent("socket.js"),
            mode: .noView, context: ExtensionTests.launchContext(mode: .noView,
                preferences: ["socketPath": .string(socketPath)]))
        for _ in 0..<100 {
            if recorder.finished || !recorder.failures.isEmpty { break }
            await ExtensionTests.settle(20)
        }
        expect(host.huds == ["Docker socket passed"],
            "JavaScriptCore http.request reaches the real Unix socket and reads its response")
        await runtime.stop(session: "socket")
    }
}
