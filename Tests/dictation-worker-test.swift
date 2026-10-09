import CryptoKit
import Foundation
import Synchronization

@main
struct DictationWorkerTest {
    @MainActor private final class Readiness { var count = 0; var workers = 0 }

    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--competing-download") {
            do {
                try await DictationModelDownloader.download(
                    .redux,
                    destination: URL(fileURLWithPath: CommandLine.arguments.last!),
                    baseURL: URL(string: "https://dictation.test/")!, protocolClasses: [DownloadFixture.self])
                fatalError("Another process acquired the same download root")
            } catch DictationWire.Failure.busy { return }
        }
        if CommandLine.arguments.contains("--fixture") { try fixture(); return }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let worker = try DictationWorker(executable: executable, arguments: ["--fixture"])
        let readiness = Readiness()
        for model in DictationModel.allCases {
            let samples = [Float](repeating: 0.125, count: 16_000)
            let request = DictationWire.Request(
                id: UUID(), model: model,
                directory: URL(fileURLWithPath: "/tmp/models"), sampleCount: samples.count,
                language: nil)
            let text = try await worker.transcribe(samples, request: request) { readiness.count += 1 }
            guard text == model.rawValue else { fatalError("Model response did not match its request") }
        }
        guard readiness.count == DictationModel.allCases.count else { fatalError("Missing readiness event") }
        await worker.stop()
        await worker.stop()

        for behavior in ["crash", "wait"] {
            let worker = try DictationWorker(executable: executable, arguments: ["--fixture", behavior])
            let samples = [Float](repeating: 0, count: 1_000_000)
            let request = DictationWire.Request(
                id: UUID(), model: .ultra,
                directory: URL(fileURLWithPath: "/tmp/models"), sampleCount: samples.count,
                language: nil)
            let ready = AsyncStream<Void>.makeStream()
            let task = Task {
                try await worker.transcribe(samples, request: request) { ready.continuation.yield(()) }
            }
            if behavior == "wait" {
                var iterator = ready.stream.makeAsyncIterator()
                _ = await iterator.next()
                task.cancel()
            }
            do {
                _ = try await task.value
                fatalError("Unexpected successful transcription")
            } catch {}
            await worker.stop()
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "dictation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for model in DictationModel.allCases {
            let directory = root.appending(path: model.folderName)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in model.requiredFiles { try Data([0]).write(to: directory.appending(path: name)) }
        }
        let store = DictationModelStore(idleRelease: .never, root: root) {
            readiness.workers += 1
            return try DictationWorker(executable: executable, arguments: ["--fixture"])
        }
        guard store.installedModels.count == DictationModel.allCases.count,
            try await store.installedSize(.redux) == Int64(DictationModel.redux.requiredFiles.count)
        else {
            fatalError("Installed model metadata is incorrect")
        }
        let cancelled = Task { try await store.transcribe([0], model: .redux) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            fatalError("Cancelled transcription started")
        } catch is CancellationError {}
        guard readiness.workers == 0, store.loadedModel == nil, !store.transcribing else {
            fatalError("Cancelled transcription launched a helper")
        }
        for model in [DictationModel.redux, .redux, .ultra] {
            let text = try await store.transcribe([0], model: model)
            guard text == model.rawValue, store.loadedModel == model, !store.transcribing else {
                fatalError("Model store failed to finish a request")
            }
        }
        guard readiness.workers == 2 else { fatalError("Worker reuse or model-switch cleanup failed") }
        try await store.delete(.ultra)
        guard store.loadedModel == nil, store.removing == nil, !store.isInstalled(.ultra),
            !FileManager.default.fileExists(
                atPath: root.appending(path: DictationModel.ultra.folderName).path)
        else {
            fatalError("Model removal retained files or a loaded helper")
        }
        await store.stop()
        try await testDownload(root: root.appending(path: "downloads"))
        print("Dictation worker reuse, switching, removal, cancellation and broken pipes passed")
    }

    private static func testDownload(root: URL) async throws {
        let models: [DictationModel] = [.redux, .qwenSmall]
        let base = URL(string: "https://dictation.test/")!
        let manager = FileManager.default
        let stale = root.appending(path: ".\(UUID())")
        try manager.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([0]).write(to: stale.appending(path: "weights.bin"))
        let preserved = [
            ".keep", ".\(UUID())", "installed-model", ".\(UUID())", ".download-lock", "other-channel"
        ]
        for name in preserved.prefix(2) { try Data([1]).write(to: root.appending(path: name)) }
        try manager.createDirectory(
            at: root.appending(path: "installed-model"), withIntermediateDirectories: false)
        try manager.createSymbolicLink(
            at: root.appending(path: preserved[3]),
            withDestinationURL: root.appending(path: "installed-model"))
        let events = Mutex<[(received: Int64, total: Int64)]>([])
        let destination = root.appending(path: DictationModel.redux.folderName)
        let started = AsyncStream<Void>.makeStream()
        DownloadFixture.state.withLock {
            $0.hold = true
        }
        let cancelled = Task.detached {
            try await DictationModelDownloader.download(
                .redux, destination: destination,
                baseURL: base, protocolClasses: [DownloadFixture.self]
            ) { received, total in
                guard received > 0 else { return }
                guard received == 1024,
                    total == Int64(DictationModel.redux.requiredFiles.count * DownloadFixture.content.count)
                else { fatalError("Live progress must report bytes before the first file finishes") }
                started.continuation.yield(())
            }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        let active = try manager.contentsOfDirectory(atPath: root.path).sorted()
        do {
            try await DictationModelDownloader.download(
                .qwenSmall,
                destination: root.appending(path: DictationModel.qwenSmall.folderName),
                baseURL: base, protocolClasses: [DownloadFixture.self])
            fatalError("Concurrent download acquired the same root")
        } catch DictationWire.Failure.busy {}
        let competitor = Process()
        competitor.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        competitor.arguments = ["--competing-download", destination.path]
        let exit = try competitor.runObservingExit()
        await Task.detached { exit.wait() }.value
        guard competitor.terminationStatus == 0 else {
            fatalError("Cross-process download protection failed")
        }
        guard try manager.contentsOfDirectory(atPath: root.path).sorted() == active else {
            fatalError("Concurrent download changed active staging")
        }
        DownloadFixture.state.withLock { $0 = .init() }
        let other = root.appending(path: "other-channel/\(DictationModel.redux.folderName)")
        try await DictationModelDownloader.download(
            .redux, destination: other,
            baseURL: base, protocolClasses: [DownloadFixture.self])
        guard manager.fileExists(atPath: other.path) else {
            fatalError("An independent download root was blocked")
        }
        cancelled.cancel()
        do {
            try await cancelled.value
            fatalError("Cancelled download installed a model")
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {}
        guard try manager.contentsOfDirectory(atPath: root.path).sorted() == preserved.sorted() else {
            fatalError("Cancellation or stale staging cleanup changed the wrong files")
        }
        DownloadFixture.state.withLock { $0 = .init() }
        for model in models {
            events.withLock { $0.removeAll() }
            try await DictationModelDownloader.download(
                model, destination: root.appending(path: model.folderName),
                baseURL: base, protocolClasses: [DownloadFixture.self]
            ) { received, total in
                events.withLock { $0.append((received, total)) }
            }
            let progress = events.withLock { $0 }
            let expected = Int64(model.requiredFiles.count * DownloadFixture.content.count)
            guard progress.first?.received == 0, progress.last?.received == expected,
                progress.allSatisfy({ $0.total == expected && $0.received <= expected }),
                zip(progress, progress.dropFirst()).allSatisfy({ $0.received <= $1.received }),
                progress.contains(where: { $0.received > 0 && $0.received < expected })
            else {
                fatalError("Combined download progress is incorrect")
            }
        }
        DownloadFixture.state.withLock { $0.corrupt = true }
        do {
            try await DictationModelDownloader.download(
                .redux, destination: root.appending(path: "corrupt"),
                baseURL: base, protocolClasses: [DownloadFixture.self])
            fatalError("Invalid checksum installed a model")
        } catch let error as URLError where error.code == .badServerResponse {}
        let expectedNames = (preserved + models.map(\.folderName)).sorted()
        guard try manager.contentsOfDirectory(atPath: root.path).sorted() == expectedNames else {
            fatalError("Atomic installation retained staging files")
        }
    }

    private static func fixture() throws {
        while let request = try DictationWire.read(DictationWire.Request.self, from: .standardInput) {
            try DictationWire.write(
                DictationWire.Response(id: request.id, status: .ready), to: .standardOutput)
            if CommandLine.arguments.contains("crash") { exit(1) }
            _ = try DictationWire.readExactly(request.sampleCount * 4, from: .standardInput)
            if CommandLine.arguments.contains("wait") {
                _ = try DictationWire.readExactly(1, from: .standardInput)
                return
            }
            try DictationWire.write(
                DictationWire.Response(
                    id: request.id, status: .result,
                    text: request.model.rawValue), to: .standardOutput)
        }
    }
}

// URL loading owns each instance; shared fixture state is protected by its mutex.
private final class DownloadFixture: URLProtocol, @unchecked Sendable {
    struct State {
        var hold = false
        var corrupt = false
    }

    static let state = Mutex(State())
    static let content = Data(repeating: 65, count: 4096)

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host == "dictation.test" }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path.contains("/tree/") {
            let checksum = SHA256.hash(data: Self.content).map { String(format: "%02x", $0) }.joined()
            let files = [DictationModel.redux, .qwenSmall].reduce(into: Set<String>()) {
                $0.formUnion($1.requiredFiles)
            }.sorted().map { name in
                [
                    "path": name.hasSuffix(".mlmodelc") ? name + "/weights.bin" : name,
                    "type": "file", "size": Self.content.count, "lfs": ["oid": checksum]
                ] as [String: Any]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: files) else {
                fatalError("Invalid download fixture manifest")
            }
            client?.urlProtocol(self, didLoad: data)
        } else {
            let state = Self.state.withLock { $0 }
            let data = state.corrupt ? Data(repeating: 66, count: Self.content.count) : Self.content
            client?.urlProtocol(self, didLoad: state.hold ? data.prefix(1024) : data)
            if state.hold { return }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
