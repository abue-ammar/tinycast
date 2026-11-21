import Foundation

/// The frames both helpers and Settings' own process speak: bounded both ways, nil at a clean end.
@main
enum PipeFramingTests {
    struct Message: Codable, Equatable, Sendable {
        let text: String
    }

    @MainActor
    static func main() async throws {
        LaunchedExecutable.pin()
        if ProcessRole.current == .settings {
            await runPeer()
            return
        }
        var failures = 0
        var checks = 0
        func check(_ name: String, _ passed: Bool) {
            checks += 1
            if !passed {
                failures += 1
                print("FAIL \(name)")
            }
        }

        let pipe = Pipe()
        try PipeFraming.write(Message(text: "hello"), to: pipe.fileHandleForWriting, maximum: 64)
        check(
            "a frame round-trips",
            try PipeFraming.read(Message.self, from: pipe.fileHandleForReading, maximum: 64)
                == Message(text: "hello"))

        let long = Message(text: String(repeating: "x", count: 100))
        check(
            "a write over its bound is refused",
            (try? PipeFraming.write(long, to: pipe.fileHandleForWriting, maximum: 64)) == nil)

        let oversized = Pipe()
        try PipeFraming.write(long, to: oversized.fileHandleForWriting, maximum: 256)
        check(
            "a frame over the reader's bound is corrupt",
            (try? PipeFraming.read(Message.self, from: oversized.fileHandleForReading, maximum: 64)) == nil)

        let closed = Pipe()
        try closed.fileHandleForWriting.close()
        check(
            "a clean end of stream reads nil",
            try PipeFraming.read(Message.self, from: closed.fileHandleForReading, maximum: 64) == nil)

        let link = try ProcessLink<Message, Message>.spawn(.settings)
        var replies: [Message] = []
        var closes = 0
        link.onReceive = { replies.append($0) }
        link.onClose = { _ in closes += 1 }
        link.start()
        let messages = [Message(text: String(repeating: "x", count: 512 << 10)), Message(text: "second")]
        for message in messages { link.send(message) }
        let delivered = await waitUntil { replies.count == messages.count }
        check("the process link delivers large frames in order", delivered && replies == messages)
        link.send(Message(text: "quit"))
        let disconnected = await waitUntil { !link.isOpen }
        check("the process link closes once at EOF", disconnected && closes == 1)

        let oversizedLink = try ProcessLink<Message, Message>.spawn(.settings)
        var failure: Error?
        oversizedLink.onClose = { failure = $0 }
        oversizedLink.start()
        guard let peer = oversizedLink.childProcessIdentifier, kill(peer, SIGSTOP) == 0 else {
            throw POSIXError(.ESRCH)
        }
        defer { kill(peer, SIGCONT) }
        oversizedLink.send(messages[0])
        oversizedLink.send(Message(text: String(repeating: "x", count: 32 << 20)))
        let refused = await waitUntil { !oversizedLink.isOpen }
        check("a stalled peer does not hide an oversized message error", refused && failure != nil)

        guard let executable = Bundle.main.executablePath else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: executable)
        do {
            _ = try ProcessLink<Message, Message>.spawn(.settings)
            check("a replaced executable is never spawned", false)
        } catch {
            check("a replaced executable is never spawned", error is LaunchedExecutable.Replaced)
        }

        print("\(checks - failures)/\(checks) framing checks passed")
        if failures > 0 { exit(1) }
    }

    @MainActor
    private static func runPeer() async {
        guard let link = ProcessLink<Message, Message>.standardIO() else { exit(1) }
        await withCheckedContinuation { (completion: CheckedContinuation<Void, Never>) in
            link.onReceive = { [weak link] message in
                if message.text == "quit" { exit(0) }
                link?.send(message)
            }
            link.onClose = { _ in completion.resume() }
            link.start()
        }
    }

    @MainActor
    private static func waitUntil(_ ready: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !ready(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return ready()
    }
}
