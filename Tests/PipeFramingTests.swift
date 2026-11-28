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
            await runPeer(inheritedPipes: inheritedPipeCount())
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

        let first = try ProcessLink<Message, Message>.spawn(.settings)
        let second = try ProcessLink<Message, Message>.spawn(.settings)
        var counted: Message?
        second.onReceive = { counted = $0 }
        second.start()
        second.send(Message(text: "inherited"))
        let answered = await waitUntil { counted != nil }
        check("a second child inherits no pipe of the first", answered && counted?.text == "0")
        first.send(Message(text: "quit"))
        second.send(Message(text: "quit"))

        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let errors = Pipe()
        let erring = try ProcessLink<Message, Message>.spawn(
            executable, arguments: [ProcessRole.settings.argument], standardError: errors)
        erring.start()
        erring.send(Message(text: "stderr"))
        erring.send(Message(text: "quit"))
        let written = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        check("a child's stderr reaches the pipe it was given", written == "diagnostic\n")

        let bounded = try ProcessLink<Message, Message>.spawn(
            executable, arguments: [ProcessRole.settings.argument], maximumFrameBytes: 256)
        var boundedFailure: Error?
        bounded.onClose = { boundedFailure = $0 }
        bounded.start()
        bounded.send(Message(text: String(repeating: "x", count: 512)))
        let overLimit = await waitUntil { !bounded.isOpen }
        check("a link's own maximum bounds what it sends", overLimit && boundedFailure != nil)

        let stuck = try ProcessLink<Message, Message>.spawn(.settings)
        stuck.start()
        guard let stuckPeer = stuck.childProcessIdentifier, kill(stuckPeer, SIGSTOP) == 0 else {
            throw POSIXError(.ESRCH)
        }
        stuck.terminate()
        let killed = await waitUntil { !stuck.isOpen }
        check("terminate ends a child that stopped answering", killed)

        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: executable.path)
        do {
            _ = try ProcessLink<Message, Message>.spawn(.settings)
            check("a replaced executable is never spawned", false)
        } catch {
            check("a replaced executable is never spawned", error is LaunchedExecutable.Replaced)
        }

        print("\(checks - failures)/\(checks) framing checks passed")
        if failures > 0 { exit(1) }
    }

    /// Read before the link opens its own: any pipe above stdio now came from another child.
    private static func inheritedPipeCount() -> Int {
        (3..<256).count { descriptor in
            var status = stat()
            return fstat(Int32(descriptor), &status) == 0 && status.st_mode & S_IFMT == S_IFIFO
        }
    }

    @MainActor
    private static func runPeer(inheritedPipes: Int) async {
        guard let link = ProcessLink<Message, Message>.standardIO() else { exit(1) }
        await withCheckedContinuation { (completion: CheckedContinuation<Void, Never>) in
            link.onReceive = { [weak link] message in
                switch message.text {
                case "quit": exit(0)
                case "inherited": link?.send(Message(text: "\(inheritedPipes)"))
                case "stderr": FileHandle.standardError.write(Data("diagnostic\n".utf8))
                default: link?.send(message)
                }
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
