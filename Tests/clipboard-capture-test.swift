// The capture helper reads a private pasteboard. Nothing here writes `NSPasteboard.general`.
import AppKit
import Darwin

@main
@MainActor
struct ClipboardCaptureTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        if CommandLine.arguments.dropFirst().first == "--owner" {
            let seconds = Double(CommandLine.arguments.dropFirst().dropFirst().first ?? "") ?? 5
            DelayedOwner.serve(seconds: seconds)
            return
        }
        guard let helper = ProcessInfo.processInfo.environment["TINYCAST_CAPTURE_HELPER"] else {
            fail("TINYCAST_CAPTURE_HELPER is unset")
            print("0/1 passed")
            exit(1)
        }
        let helperURL = URL(fileURLWithPath: helper)
        var done = false
        Task {
            await run(helper: helperURL)
            done = true
        }
        while !done {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func run(helper: URL) async {
        await textLandsInTheStore(helper: helper)
        await aFinderCopyStaysAFile(helper: helper)
        await ownWritesAndSecretsAreSkipped(helper: helper)
        await anExcludedAppSkipsTheBlockingRead(helper: helper)
        await aDelayedOwnerDoesNotStallTheMainThread(helper: helper)
        await stoppingCancelsAHungRead(helper: helper)
        await theHelperRespawnsAfterATimeout(helper: helper)
        await resigningDropsAnInFlightRead(helper: helper)
        await drainDoesNotReadAnUnchangedPasteboard(helper: helper)
        await anImageComesBackAsPNG(helper: helper)
        await anOversizedImageIsDropped(helper: helper)
        await drainAfterATimeoutDoesNotWaitAgain(helper: helper)
        await anImageSurvivesThePasteboardSync(helper: helper)
        await anIdleHelperIsReapedOnCancel(helper: helper)
    }

    static func textLandsInTheStore(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let board = NSPasteboard.withUniqueName()
            board.declareTypes([.string], owner: nil)
            board.setString("captured over the helper", forType: .string)
            await manager.capture(pasteboard: board, sourceBundleID: "com.example.editor")
            expect(
                store.items.first?.text == "captured over the helper"
                    && store.items.first?.sourceBundleID == "com.example.editor",
                "text and its source app are stored")
            expect(store.items.first?.kind == .text, "it is text")
        }
    }

    static func aFinderCopyStaysAFile(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            try await withDurableFile(named: "Screen Recording.mov", bytes: Data("movie".utf8)) { file in
                let board = NSPasteboard.withUniqueName()
                board.declareTypes([.fileURL, .string], owner: nil)
                board.setData(file.dataRepresentation, forType: .fileURL)
                board.setString("Screen Recording.mov", forType: .string)
                await manager.capture(pasteboard: board, sourceBundleID: nil)
                expect(
                    store.items.first?.kind == .file && store.items.first?.text == file.path,
                    "a Finder copy is the path, not the display name")
            }
        }
    }

    static func ownWritesAndSecretsAreSkipped(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let own = NSPasteboard.withUniqueName()
            own.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            own.setString("tinycast wrote this", forType: .string)
            own.setData(Data(), forType: ClipboardManager.internalType)
            await manager.capture(pasteboard: own, sourceBundleID: nil)
            expect(store.items.isEmpty, "an internal marker is not recorded")

            let secret = NSPasteboard.withUniqueName()
            let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            secret.declareTypes([.string, concealed], owner: nil)
            secret.setString("p@ssword", forType: .string)
            secret.setData(Data(), forType: concealed)
            await manager.capture(pasteboard: secret, sourceBundleID: nil)
            expect(store.items.isEmpty, "a concealed copy is not recorded")

            let huge = NSPasteboard.withUniqueName()
            huge.declareTypes([.string], owner: nil)
            let over = String(repeating: "a", count: ClipboardManager.maxTextLength + 1)
            huge.setString(over, forType: .string)
            await manager.capture(pasteboard: huge, sourceBundleID: nil)
            expect(store.items.isEmpty, "text past the cap is not recorded")
        }
    }

    static func anExcludedAppSkipsTheBlockingRead(helper: URL) async {
        await withManager(helper: helper) { manager, store, settings in
            let owner = try launchOwner(seconds: 5)
            defer { owner.process.terminate() }
            settings.clipboardDisabledApps = ["com.excluded.app"]
            manager.captureTimeout = .seconds(5)
            let started = ContinuousClock.now
            await manager.capture(pasteboard: owner.board, sourceBundleID: "com.excluded.app")
            let elapsed = started.duration(to: .now)
            expect(store.items.isEmpty, "an excluded app is not recorded")
            expect(elapsed < .milliseconds(300), "exclusion returns without the owner (\(elapsed))")
        }
    }

    static func aDelayedOwnerDoesNotStallTheMainThread(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let owner = try launchOwner(seconds: 5)
            defer { owner.process.terminate() }
            manager.captureTimeout = .milliseconds(400)
            let ticks = Tick()
            let timer = Timer(timeInterval: 0.05, repeats: true) { _ in ticks.bump() }
            RunLoop.main.add(timer, forMode: .common)
            let started = ContinuousClock.now
            let done = Flag()
            Task {
                await manager.capture(pasteboard: owner.board, sourceBundleID: "com.slow.owner")
                done.set()
            }
            while !done.get(), started.duration(to: .now) < .seconds(2) {
                try await Task.sleep(for: .milliseconds(20))
            }
            timer.invalidate()
            let elapsed = started.duration(to: .now)
            expect(done.get(), "the hung read returned")
            expect(ticks.read() >= 5, "main thread kept heartbeating (\(ticks.read()) ticks)")
            expect(elapsed < .seconds(1.2), "timeout won over the owner (\(elapsed))")
            expect(store.items.isEmpty, "a timed-out read is not stored")
        }
    }

    static func stoppingCancelsAHungRead(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let owner = try launchOwner(seconds: 5)
            defer { owner.process.terminate() }
            manager.captureTimeout = .seconds(5)
            Task { await manager.capture(pasteboard: owner.board, sourceBundleID: nil) }
            try await Task.sleep(for: .milliseconds(200))
            let started = ContinuousClock.now
            manager.stop()
            await manager.drainPendingCapture()
            expect(
                started.duration(to: .now) < .milliseconds(500),
                "stop unblocks the drain (\(started.duration(to: .now)))")
            expect(store.items.isEmpty, "a cancelled read is not stored")
            try await Task.sleep(for: .milliseconds(400))
            expect(store.items.isEmpty, "a late owner result is not published after stop")
        }
    }

    static func theHelperRespawnsAfterATimeout(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let owner = try launchOwner(seconds: 5)
            defer { owner.process.terminate() }
            manager.captureTimeout = .milliseconds(300)
            await manager.capture(pasteboard: owner.board, sourceBundleID: nil)
            let board = NSPasteboard.withUniqueName()
            board.declareTypes([.string], owner: nil)
            board.setString("after the hang", forType: .string)
            await manager.capture(pasteboard: board, sourceBundleID: nil)
            expect(store.items.first?.text == "after the hang", "a new helper reads the next copy")
        }
    }

    static func resigningDropsAnInFlightRead(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let owner = try launchOwner(seconds: 5)
            defer { owner.process.terminate() }
            manager.captureTimeout = .seconds(5)
            Task { await manager.capture(pasteboard: owner.board, sourceBundleID: nil) }
            try await Task.sleep(for: .milliseconds(200))
            let center = NSWorkspace.shared.notificationCenter
            center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            try await Task.sleep(for: .milliseconds(150))
            await manager.drainPendingCapture()
            expect(store.items.isEmpty, "session resign drops the in-flight read")
            try await Task.sleep(for: .milliseconds(400))
            expect(store.items.isEmpty, "a late owner result is not published after resign")
            center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            try await Task.sleep(for: .milliseconds(50))
            let board = NSPasteboard.withUniqueName()
            board.declareTypes([.string], owner: nil)
            board.setString("back in session", forType: .string)
            await manager.capture(pasteboard: board, sourceBundleID: nil)
            expect(store.items.first?.text == "back in session", "capture works again once active")
        }
    }

    static func drainDoesNotReadAnUnchangedPasteboard(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let count = NSPasteboard.general.changeCount
            manager.synchronizeAfterTinycastPasteboardMutation(changeCount: count)
            await manager.drainPendingCapture()
            expect(store.items.isEmpty, "drain with a matching changeCount reads nothing")
        }
    }

    static func anImageComesBackAsPNG(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let board = NSPasteboard.withUniqueName()
            board.declareTypes([.tiff], owner: nil)
            board.setData(try tiffBytes(), forType: .tiff)
            await manager.capture(pasteboard: board, sourceBundleID: nil)
            let started = ContinuousClock.now
            while store.items.isEmpty, started.duration(to: .now) < .seconds(2) {
                try await Task.sleep(for: .milliseconds(50))
            }
            expect(store.items.first?.kind == .image, "a TIFF capture becomes an image row")
        }
    }

    static func anOversizedImageIsDropped(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let board = NSPasteboard.withUniqueName()
            board.declareTypes([.png], owner: nil)
            board.setData(Data(repeating: 0, count: ClipboardCapture.maxImageBytes + 1), forType: .png)
            await manager.capture(pasteboard: board, sourceBundleID: nil)
            expect(store.items.isEmpty, "an image over the byte cap is not stored")
            let follow = NSPasteboard.withUniqueName()
            follow.declareTypes([.string], owner: nil)
            follow.setString("after the oversized image", forType: .string)
            await manager.capture(pasteboard: follow, sourceBundleID: nil)
            expect(
                store.items.first?.text == "after the oversized image",
                "the helper is still readable after dropping an oversized image")
        }
    }

    static func drainAfterATimeoutDoesNotWaitAgain(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let owner = try launchOwner(seconds: 5)
            defer { owner.process.terminate() }
            manager.captureTimeout = .milliseconds(350)
            manager.useWatchedPasteboard(owner.board)
            let first = ContinuousClock.now
            await manager.drainPendingCapture()
            let firstWait = first.duration(to: .now)
            let second = ContinuousClock.now
            await manager.drainPendingCapture()
            let secondWait = second.duration(to: .now)
            expect(
                firstWait > .milliseconds(250) && firstWait < .seconds(1),
                "the in-flight read waits out one timeout (\(firstWait))")
            expect(
                secondWait < .milliseconds(120),
                "the next drain does not time out again (\(secondWait))")
            expect(store.items.isEmpty, "the timed-out copy is not retried")
        }
    }

    static func anImageSurvivesThePasteboardSync(helper: URL) async {
        await withManager(helper: helper) { manager, store, _ in
            let board = NSPasteboard.withUniqueName()
            board.declareTypes([.tiff], owner: nil)
            board.setData(try tiffBytes(), forType: .tiff)
            manager.useWatchedPasteboard(board)
            await manager.drainPendingCapture()
            board.clearContents()
            board.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            board.setString("injected text", forType: .string)
            board.setData(Data(), forType: ClipboardManager.internalType)
            manager.synchronizeAfterTinycastPasteboardMutation(
                changeCount: board.changeCount)
            let started = ContinuousClock.now
            while store.items.isEmpty, started.duration(to: .now) < .seconds(2) {
                try await Task.sleep(for: .milliseconds(50))
            }
            expect(
                store.items.first?.kind == .image,
                "the image is stored after drain and the following sync")
        }
    }

    static func anIdleHelperIsReapedOnCancel(helper: URL) async {
        let board = NSPasteboard.withUniqueName()
        board.declareTypes([.string], owner: nil)
        board.setString("idle child", forType: .string)
        let client = ClipboardCaptureClient(executable: helper)
        _ = await client.read(board: board.name.rawValue, timeout: .seconds(1))
        let pid = client.processID
        expect(pid > 0, "the idle capture helper is running")
        client.cancel()
        let started = ContinuousClock.now
        while client.processID != 0, started.duration(to: .now) < .seconds(5) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        expect(client.processID == 0, "cancel reaps an idle capture helper")
    }

    static func withManager(
        helper: URL,
        _ body: (ClipboardManager, ClipboardStore, AppSettings) async throws -> Void
    ) async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-capture-\(UUID().uuidString)", isDirectory: true)
        let store = ClipboardStore(directory: directory)
        let settings = AppSettings()
        let manager = ClipboardManager(store: store, settings: settings)
        manager.useCaptureHelper(at: helper)
        manager.start()
        defer {
            manager.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        do { try await body(manager, store, settings) } catch {
            fail("\(error)")
        }
    }

    static func withDurableFile(
        named name: String, bytes: Data, _ body: (URL) async throws -> Void
    ) async throws {
        let directory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(
                "Library/Application Support/TinycastCaptureTest-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(name)
        try bytes.write(to: file)
        try await body(file)
    }

    static func tiffBytes() throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
            let tiff = rep.representation(using: .tiff, properties: [:])
        else { throw TestError.image }
        return tiff
    }

    fileprivate static func launchOwner(seconds: TimeInterval) throws -> OwnerProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--owner", String(seconds)]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let name = try readLine(from: output.fileHandleForReading)
        return OwnerProcess(process: process, board: NSPasteboard(name: NSPasteboard.Name(name)))
    }

    static func readLine(from handle: FileHandle) throws -> String {
        let descriptor = handle.fileDescriptor
        var data = Data()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            var state = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            if Darwin.poll(&state, 1, 50) <= 0 { continue }
            var byte: UInt8 = 0
            if Darwin.read(descriptor, &byte, 1) <= 0 { break }
            if byte == 10 {
                guard let line = String(data: data, encoding: .utf8), !line.isEmpty else {
                    throw TestError.owner
                }
                return line
            }
            data.append(byte)
        }
        throw TestError.owner
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            fail(message)
        }
    }

    static func fail(_ message: String) {
        failures += 1
        print("FAIL: \(message)")
    }
}

private struct OwnerProcess {
    let process: Process
    let board: NSPasteboard
}

/// Timer and test agree only through the lock; both run on the main run loop.
private final class Tick: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    func read() -> Int { lock.withLock { count } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    func get() -> Bool { lock.withLock { value } }
}

private enum TestError: Error { case image, owner }

private final class DelayedOwner: NSObject, NSPasteboardItemDataProvider {
    // One owner process, one thread: the provider has to outlive `serve`.
    nonisolated(unsafe) static var retained: DelayedOwner?
    let seconds: TimeInterval

    init(seconds: TimeInterval) { self.seconds = seconds }

    static func serve(seconds: TimeInterval) {
        let owner = DelayedOwner(seconds: seconds)
        retained = owner
        let item = NSPasteboardItem()
        item.setDataProvider(owner, forTypes: [.string])
        let board = NSPasteboard.withUniqueName()
        board.writeObjects([item])
        print(board.name.rawValue)
        fflush(stdout)
        RunLoop.main.run()
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        Thread.sleep(forTimeInterval: seconds)
        item.setString("from-slow-owner", forType: type)
    }
}

@MainActor
final class AppSettings {
    var clipboardDisabledApps: [String] = []
}
