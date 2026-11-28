import Foundation

/// The real `ExtensionSession` against the packed `hello`, and against this harness as a stand-in.
@main
@MainActor
enum ExtensionSessionTests {
    private static let peerVariable = "TINYCAST_SESSION_PEER"
    private static var failures = 0
    private static var checks = 0

    private static func check(_ name: String, _ passed: Bool) {
        checks += 1
        if !passed {
            failures += 1
            print("FAIL \(name)")
        }
    }

    static func main() async throws {
        if let mode = ProcessInfo.processInfo.environment[peerVariable] {
            await runStandIn(mode)
            return
        }
        try checkSignatures()
        await checkSpawnFailure()
        await checkStaleRender()
        await checkRequestAfterStop()
        await checkStubbornProcess()
        let hello = helloExecutable()
        if FileManager.default.isExecutableFile(atPath: hello.path) {
            await checkViewRun(hello)
            await checkNoViewRun(hello)
            await checkIdleStop(hello)
        } else {
            print("skipped the hello cases: no \(hello.path); pack hello or set TINYCAST_HELLO_BUNDLE")
        }
        print("\(checks - failures)/\(checks) session checks passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    private static func checkSignatures() throws {
        let bundle = helloExecutable().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let unconfigured = ExtensionSignatureService(teamID: nil)
        check("no team ID runs nothing", failure(of: { try unconfigured.verify(bundle, id: "hello") }) == .noTeamID)
        let configured = ExtensionSignatureService(teamID: "ABCDE12345")
        check(
            "an id that could leave the requirement is refused",
            failure(of: { try configured.verify(bundle, id: "hello\" or true") }) == .invalidID)
        guard FileManager.default.fileExists(atPath: bundle.path) else { return }
        guard case .invalidSignature = failure(of: { try configured.verify(bundle, id: "hello") }) else {
            return check("an ad-hoc signature is refused", false)
        }
        check("an ad-hoc signature is refused", true)
    }

    private static func checkSpawnFailure() async {
        var gone = 0
        let session = makeSession(URL(filePath: "/nonexistent/extension"), command: "greet")
        session.onGone = { gone += 1 }
        check("a spawn that fails throws", (try? session.launch()) == nil)
        check("a spawn that fails ends the session once", session.state == .gone && gone == 1)
    }

    private static func checkStaleRender() async {
        var calls: [ExtensionWire.HostCall] = []
        let session = makeStandIn("stale", record: { calls.append($0) })
        let synced = await waitUntil { !calls.isEmpty }
        check(
            "a render older than the last one is dropped",
            synced && session.revision == 2 && session.ui == detail("two"))
        session.stop(.closed)
        check("the stand-in exits on stop", await waitUntil { session.state == .gone })
    }

    private static func checkRequestAfterStop() async {
        var calls: [ExtensionWire.HostCall] = []
        let session = makeStandIn("late", record: { calls.append($0) })
        _ = await waitUntil { session.revision == 1 }
        let stopped = ContinuousClock.now
        session.stop(.closed)
        let exited = await waitUntil { session.state == .gone }
        check(
            "a request after stop is answered, and the process exits on its own",
            exited && calls == [.copy(text: "after stop")] && ContinuousClock.now - stopped < .seconds(4))
    }

    private static func checkStubbornProcess() async {
        let session = makeStandIn("stubborn", stopTimeout: .milliseconds(300))
        _ = await waitUntil { session.revision == 1 }
        session.stop(.closed)
        check("a process that ignores stop is killed", await waitUntil { session.state == .gone })
    }

    private static func checkViewRun(_ hello: URL) async {
        let session = makeSession(hello, command: "greet")
        try? session.launch()
        let first = await waitUntil { session.revision == 1 }
        check("start renders the view", first && text(of: session.ui).contains("Waves: 0"))
        session.send(.action("wave"))
        let second = await waitUntil { session.revision == 2 }
        check("an event renders again", second && text(of: session.ui).contains("Waves: 1"))
        session.stop(.closed)
        check("stop ends the view's process", await waitUntil { session.state == .gone })
    }

    private static func checkNoViewRun(_ hello: URL) async {
        var calls: [ExtensionWire.HostCall] = []
        var huds: [String?] = []
        let session = makeSession(hello, command: "copy-greeting", record: { calls.append($0) })
        session.onFinish = { huds.append($0) }
        try? session.launch()
        let exited = await waitUntil { session.state == .gone }
        check("a no-view run makes its request", calls == [.copy(text: "Hello from Tinycast!")])
        check("finish arrives once with its HUD", huds == ["Copied"])
        check("finish is followed by stop, so the process exits", exited)
    }

    private static func checkIdleStop(_ hello: URL) async {
        let session = makeSession(hello, command: "greet", idleDelay: .milliseconds(200))
        session.isShown = true
        try? session.launch()
        _ = await waitUntil { session.revision == 1 }
        try? await Task.sleep(for: .milliseconds(600))
        check("a shown session never idles", session.state == .running)
        session.isShown = false
        check("an unshown session stops after the idle delay", await waitUntil { session.state == .gone })
    }

    // MARK: - Helpers

    private static func helloExecutable() -> URL {
        let bundle =
            ProcessInfo.processInfo.environment["TINYCAST_HELLO_BUNDLE"]
            ?? "../tinycast-extensions/extensions/hello/.build/hello.tcext"
        return URL(filePath: bundle).appending(path: "Contents/MacOS/hello").standardizedFileURL
    }

    private static func makeSession(
        _ executable: URL, command: String, idleDelay: Duration = .seconds(30),
        stopTimeout: Duration = .seconds(5), record: @escaping (ExtensionWire.HostCall) -> Void = { _ in }
    ) -> ExtensionSession {
        let start = ExtensionWire.Start(
            api: .current, command: command, reason: .user, preferences: [:],
            dataFolder: FileManager.default.temporaryDirectory.appending(path: "session-\(UUID().uuidString)"),
            locale: "en-US", appearance: .dark)
        return ExtensionSession(
            extensionID: "hello", executable: executable, start: start, idleDelay: idleDelay,
            stopTimeout: stopTimeout,
            perform: { call in
                record(call)
                return .success(nil)
            })
    }

    /// This harness again, playing an extension that misbehaves in the named way.
    private static func makeStandIn(
        _ mode: String, stopTimeout: Duration = .seconds(5),
        record: @escaping (ExtensionWire.HostCall) -> Void = { _ in }
    ) -> ExtensionSession {
        let session = makeSession(
            Bundle.main.executableURL!, command: mode, stopTimeout: stopTimeout, record: record)
        setenv(peerVariable, mode, 1)
        defer { unsetenv(peerVariable) }
        try? session.launch()
        return session
    }

    private static func failure(of verify: () throws -> Void) -> ExtensionSignatureService.Failure? {
        do {
            try verify()
            return nil
        } catch {
            return error as? ExtensionSignatureService.Failure
        }
    }

    private static func detail(_ markdown: String) -> ExtensionUI {
        .detail(ExtensionUI.Detail(markdown: markdown))
    }

    private static func text(of ui: ExtensionUI?) -> String {
        guard let ui, let data = try? JSONEncoder().encode(ui) else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private static func waitUntil(_ ready: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !ready(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return ready()
    }

    // MARK: - Stand-in

    private static func runStandIn(_ mode: String) async {
        guard
            let link = ProcessLink<ExtensionWire.ToMainApp, ExtensionWire.ToExtension>.standardIO(
                maximumFrameBytes: ExtensionWire.maximumFrameBytes)
        else { exit(1) }
        await withCheckedContinuation { (completion: CheckedContinuation<Void, Never>) in
            link.onReceive = { [weak link] message in
                guard let link else { return }
                switch (mode, message) {
                case ("stale", .start):
                    link.send(.render(ExtensionWire.Render(revision: 2, ui: detail("two"))))
                    link.send(.render(ExtensionWire.Render(revision: 1, ui: detail("one"))))
                    link.send(.request(ExtensionWire.Request(id: 1, call: .readClipboard)))
                case (_, .start):
                    link.send(.render(ExtensionWire.Render(revision: 1, ui: detail("one"))))
                case ("late", .stop):
                    link.send(.request(ExtensionWire.Request(id: 7, call: .copy(text: "after stop"))))
                case ("late", .reply(let reply)) where reply.id == 7:
                    exit(0)
                case ("stale", .stop):
                    exit(0)
                default:
                    break
                }
            }
            link.onClose = { _ in completion.resume() }
            link.start()
        }
    }
}
