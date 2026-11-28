import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import Tinycast

@Suite(.timeLimit(.minutes(1)))
struct DictationWorkerTests {
    private let scratch: ScratchDirectory

    init() throws {
        scratch = try ScratchDirectory("dictation-worker")
    }

    // MARK: Worker

    @Test func eachModelAnswersItsOwnRequestAfterItIsReady() async throws {
        let worker = try await stubWorker()
        let models = DictationModel.allCases
        try await confirmation("ready once per request", expectedCount: models.count) { ready in
            for model in models {
                let samples = [Float](repeating: 0.125, count: 16_000)
                let text = try await worker.transcribe(samples, request: request(model, samples)) {
                    ready()
                }
                #expect(text == model.rawValue)
            }
        }
        await worker.stop()
    }

    @Test func aStoppedWorkerStopsAgainQuietly() async throws {
        let worker = try await stubWorker()
        await worker.stop()
        await worker.stop()
    }

    /// The pipe breaks under the samples, which must fail the request rather than kill Tinycast.
    @Test func aWorkerThatCrashesFailsItsTranscription() async throws {
        let worker = try await stubWorker(mode: "crash")
        let samples = [Float](repeating: 0, count: 1_000_000)
        await #expect(throws: (any Error).self) {
            _ = try await worker.transcribe(samples, request: request(.ultra, samples)) {}
        }
        await worker.stop()
    }

    @Test func cancellingAfterReadyFailsTheTranscription() async throws {
        let worker = try await stubWorker(mode: "wait")
        let samples = [Float](repeating: 0, count: 1_000_000)
        let (ready, readiness) = AsyncStream.makeStream(of: Void.self)
        let transcription = Task {
            try await worker.transcribe(samples, request: request(.ultra, samples)) {
                readiness.yield()
            }
        }
        var iterator = ready.makeAsyncIterator()
        await iterator.next()
        transcription.cancel()
        await #expect(throws: (any Error).self) { _ = try await transcription.value }
        await worker.stop()
    }

    // MARK: Model store

    @MainActor
    @Test func installedModelsAndTheirSizeComeFromTheirFiles() async throws {
        let (store, _) = try await installedStore()
        #expect(store.installedModels == Set(DictationModel.allCases))
        #expect(await store.installedSize(.redux) == Int64(DictationModel.redux.requiredFiles.count))
        await store.stop()
    }

    @MainActor
    @Test func aTranscriptionCancelledBeforeItStartsLaunchesNoWorker() async throws {
        let (store, workers) = try await installedStore()
        let cancelled = Task { try await store.transcribe([0], model: .redux) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(workers.count == 0)
        #expect(store.loadedModel == nil)
        #expect(!store.transcribing)
        await store.stop()
    }

    @MainActor
    @Test func theStoreReusesItsWorkerAndReplacesItOnASwitch() async throws {
        let (store, workers) = try await installedStore()
        for model in [DictationModel.redux, .redux, .ultra] {
            #expect(try await store.transcribe([0], model: model) == model.rawValue)
            #expect(store.loadedModel == model)
            #expect(!store.transcribing)
        }
        #expect(workers.count == 2)
        await store.stop()
    }

    @MainActor
    @Test func deletingTheLoadedModelReleasesItsWorkerAndFiles() async throws {
        let (store, _) = try await installedStore()
        _ = try await store.transcribe([0], model: .ultra)
        try await store.delete(.ultra)
        #expect(store.loadedModel == nil)
        #expect(store.removing == nil)
        #expect(!store.isInstalled(.ultra))
        let folder = scratch.url.appending(path: "models/\(DictationModel.ultra.folderName)")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        await store.stop()
    }

    // MARK: Downloader

    @Test func liveProgressCountsBytesBeforeTheFirstFileFinishes() async throws {
        let held = await HeldDownload(into: downloads)
        let progress = try #require(held.firstProgress)
        #expect(progress.received == 1024)
        #expect(progress.total == DownloadFixture.size(of: .redux))
        await held.cancel()
    }

    @Test func aSecondDownloadIntoAHeldRootIsBusy() async throws {
        let held = await HeldDownload(into: downloads)
        try #require(held.firstProgress != nil)
        let staging = try contents(of: downloads)
        await #expect(throws: DictationWire.Failure.busy) {
            try await DownloadFixture.download(.qwenSmall, into: downloads, mode: .plain)
        }
        #expect(try contents(of: downloads) == staging)
        await held.cancel()
    }

    /// `lockf` takes the same `flock` the downloader does, from a process of its own.
    @Test func anotherProcessCannotTakeAHeldRoot() async throws {
        let held = await HeldDownload(into: downloads)
        try #require(held.firstProgress != nil)
        let staging = try contents(of: downloads)
        let attempt = await InstalledAIProbe.run(
            executable: URL(filePath: "/usr/bin/lockf"),
            arguments: ["-s", "-k", "-n", "-t", "0", downloads.appending(path: ".download-lock").path, "/usr/bin/true"],
            workspace: scratch.url)
        #expect(attempt.status == EX_TEMPFAIL)
        #expect(try contents(of: downloads) == staging)
        await held.cancel()
    }

    @Test func anIndependentRootDownloadsWhileAnotherIsHeld() async throws {
        let held = await HeldDownload(into: downloads)
        try #require(held.firstProgress != nil)
        let other = scratch.url.appending(path: "other-channel", directoryHint: .isDirectory)
        try await DownloadFixture.download(.redux, into: other, mode: .plain)
        #expect(FileManager.default.fileExists(atPath: other.appending(path: DictationModel.redux.folderName).path))
        await held.cancel()
    }

    /// Only a directory named like staging is stale; a file, a symlink or another name is not.
    @Test func cancellingClearsStagingAndLeavesEverythingElse() async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: downloads, withIntermediateDirectories: true)
        let stale = downloads.appending(path: ".\(UUID())")
        try manager.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([0]).write(to: stale.appending(path: "weights.bin"))
        let stagingNamedFile = ".\(UUID())", stagingNamedLink = ".\(UUID())"
        try Data([1]).write(to: downloads.appending(path: ".keep"))
        try Data([1]).write(to: downloads.appending(path: stagingNamedFile))
        try manager.createDirectory(at: downloads.appending(path: "installed-model"), withIntermediateDirectories: false)
        try manager.createSymbolicLink(
            at: downloads.appending(path: stagingNamedLink),
            withDestinationURL: downloads.appending(path: "installed-model"))

        let held = await HeldDownload(into: downloads)
        try #require(held.firstProgress != nil)
        held.task.cancel()
        let error = await #expect(throws: (any Error).self) { try await held.task.value }
        #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        let kept = [".keep", stagingNamedFile, "installed-model", stagingNamedLink, ".download-lock"]
        #expect(try contents(of: downloads) == kept.sorted())
    }

    @Test(arguments: [DictationModel.redux, .qwenSmall])
    func progressRisesToTheCombinedSizeAndTheModelInstallsWhole(_ model: DictationModel) async throws {
        let events = Mutex<[(received: Int64, total: Int64)]>([])
        try await DownloadFixture.download(model, into: downloads, mode: .plain) { received, total in
            events.withLock { $0.append((received, total)) }
        }
        let progress = events.withLock { $0 }
        let expected = DownloadFixture.size(of: model)
        #expect(progress.first?.received == 0)
        #expect(progress.last?.received == expected)
        #expect(progress.allSatisfy { $0.total == expected && $0.received <= expected })
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.received <= $1.received })
        #expect(progress.contains { $0.received > 0 && $0.received < expected })
        #expect(try contents(of: downloads) == [".download-lock", model.folderName])
    }

    @Test func aChecksumMismatchInstallsNothing() async throws {
        let error = await #expect(throws: URLError.self) {
            try await DownloadFixture.download(.redux, into: downloads, mode: .corrupt)
        }
        #expect(error?.code == .badServerResponse)
        #expect(try contents(of: downloads) == [".download-lock"])
    }

    // MARK: Helpers

    private var downloads: URL { scratch.url.appending(path: "downloads", directoryHint: .isDirectory) }

    private func stubWorker(mode: String = "normal") async throws -> DictationWorker {
        let stub = try await NodeScript(
            "Dictation/dictation-worker-stub.js", in: scratch, named: "dictation-worker")
        return try DictationWorker(executable: stub.node, arguments: [stub.executable.path, mode])
    }

    private func request(_ model: DictationModel, _ samples: [Float]) -> DictationWire.Request {
        DictationWire.Request(
            id: UUID(), model: model, directory: URL(filePath: "/tmp/models"),
            sampleCount: samples.count, language: nil)
    }

    /// Every model's required files exist, so each reads as installed.
    @MainActor
    private func installedStore() async throws -> (DictationModelStore, WorkerCount) {
        let root = scratch.url.appending(path: "models", directoryHint: .isDirectory)
        for model in DictationModel.allCases {
            let directory = root.appending(path: model.folderName)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in model.requiredFiles { try Data([0]).write(to: directory.appending(path: name)) }
        }
        let stub = try await NodeScript("Dictation/dictation-worker-stub.js", in: scratch, named: "dictation-worker")
        let workers = WorkerCount()
        let store = DictationModelStore(idleRelease: .never, root: root) {
            workers.count += 1
            return try DictationWorker(executable: stub.node, arguments: [stub.executable.path])
        }
        return (store, workers)
    }

    private func contents(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }
}

@MainActor
private final class WorkerCount {
    var count = 0
}

/// A download that receives its first 1,024 bytes and then holds its root until cancelled.
private final class HeldDownload {
    let task: Task<Void, Error>
    /// `nil` when the download ended before any byte arrived.
    let firstProgress: (received: Int64, total: Int64)?

    init(into root: URL) async {
        let (progress, reports) = AsyncStream.makeStream(of: (received: Int64, total: Int64).self)
        task = Task {
            defer { reports.finish() }
            try await DownloadFixture.download(.redux, into: root, mode: .hold) { received, total in
                if received > 0 { reports.yield((received, total)) }
            }
        }
        var iterator = progress.makeAsyncIterator()
        firstProgress = await iterator.next()
    }

    func cancel() async {
        task.cancel()
        _ = await task.result
    }

    deinit {
        task.cancel()
    }
}

/// Serves a model tree whose every file is `content`; the request's host says how it misbehaves.
private final class DownloadFixture: URLProtocol {
    enum Mode: String {
        case plain, hold, corrupt
    }

    static let content = Data(repeating: 65, count: 4096)

    static func size(of model: DictationModel) -> Int64 {
        Int64(model.requiredFiles.count * content.count)
    }

    static func download(
        _ model: DictationModel, into root: URL, mode: Mode,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        try await DictationModelDownloader.download(
            model, destination: root.appending(path: model.folderName),
            baseURL: URL(string: "https://\(mode.rawValue).dictation.test/")!,
            protocolClasses: [DownloadFixture.self], onProgress: onProgress)
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host()?.hasSuffix(".dictation.test") == true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        let mode = url.host()?.split(separator: ".").first.flatMap { Mode(rawValue: String($0)) } ?? .plain
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path().contains("/tree/") {
            client?.urlProtocol(self, didLoad: Self.manifest)
        } else {
            if mode == .hold {
                client?.urlProtocol(self, didLoad: Self.content.prefix(1024))
                return
            }
            let data = mode == .corrupt ? Data(repeating: 66, count: Self.content.count) : Self.content
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Every file either model needs, with the checksum of `content`.
    private static let manifest: Data = {
        let checksum = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let names = DictationModel.redux.requiredFiles.union(DictationModel.qwenSmall.requiredFiles)
        let files = names.sorted().map { name in
            [
                "path": name.hasSuffix(".mlmodelc") ? name + "/weights.bin" : name,
                "type": "file", "size": content.count, "lfs": ["oid": checksum]
            ] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: files)) ?? Data()
    }()
}
