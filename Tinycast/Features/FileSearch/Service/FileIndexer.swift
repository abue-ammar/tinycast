import CoreServices
import Foundation

/// The crawl runs in `FileIndexHelper`, so its memory leaves when that process exits.
@MainActor
@Observable
final class FileIndexer {
    enum Status: Equatable {
        case off
        case needsAccess
        case building(items: Int)
        case ready(items: Int, builtAt: Date)
        case failed
    }

    private(set) var status: Status = .off
    /// An index is mapped, so searches answer even while a rebuild runs.
    private(set) var hasIndex = false
    @ObservationIgnored let index = FileIndex()
    @ObservationIgnored var onIndexChanged: (() -> Void)?
    @ObservationIgnored private var policy: FileSearchPolicy?
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var watcher: FileSystemWatcher?
    @ObservationIgnored private var buildTask: Task<Void, Never>?
    @ObservationIgnored private var countRefresh: Task<Void, Never>?
    @ObservationIgnored private let directory = AppPaths.applicationSupport()
        .appending(path: "FileIndex", directoryHint: .isDirectory)
    @ObservationIgnored private let events = DispatchQueue(
        label: "com.tinycast.file-index.events", qos: .userInitiated)

    private var indexURL: URL { directory.appending(path: FileIndexSnapshot.fileName) }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            activate()
        } else {
            deactivate()
            // An index of every filename is not something to leave behind once it is unused.
            try? FileManager.default.removeItem(at: directory)
            status = .off
        }
    }

    func apply(_ policy: FileSearchPolicy) {
        guard policy != self.policy else { return }
        let isFirst = self.policy == nil
        self.policy = policy
        guard isEnabled else { return }
        // Editing a list fires once per change, so a burst of them builds once.
        if isFirst || status == .needsAccess { activate() } else { build(after: .seconds(1)) }
    }

    /// Full Disk Access can be granted or revoked at any time, and nothing announces it.
    func refreshAccess() {
        guard isEnabled else { return }
        let granted = Permissions.hasFullDiskAccess()
        if granted, status == .needsAccess {
            activate()
        } else if !granted, status != .needsAccess {
            deactivate()
            status = .needsAccess
        }
    }

    func rebuild() {
        guard isEnabled, status != .needsAccess else { return }
        build(after: .zero)
    }

    private func activate() {
        guard isEnabled, let policy else { return }
        guard Permissions.hasFullDiskAccess() else {
            deactivate()
            status = .needsAccess
            return
        }
        guard !policy.roots.isEmpty else {
            deactivate()
            status = .ready(items: 0, builtAt: .now)
            return
        }
        if index.snapshot?.fingerprint == policy.fingerprint { return }
        if let snapshot = FileIndexSnapshot(contentsOf: indexURL),
            snapshot.fingerprint == policy.fingerprint
        {
            load(snapshot)
        } else {
            build(after: .zero)
        }
    }

    private func deactivate() {
        buildTask?.cancel()
        buildTask = nil
        countRefresh?.cancel()
        countRefresh = nil
        watcher = nil
        index.replace(with: nil, policy: nil)
        hasIndex = false
        onIndexChanged?()
    }

    private func load(_ snapshot: FileIndexSnapshot) {
        guard let policy else { return }
        index.replace(with: snapshot, policy: policy)
        hasIndex = true
        watch(snapshot)
        status = .ready(items: index.itemCount, builtAt: snapshot.builtAt)
        onIndexChanged?()
    }

    /// Replayed from the snapshot's own event id, so whatever changed since the crawl began lands.
    private func watch(_ snapshot: FileIndexSnapshot) {
        watcher = nil
        let index = index
        let roots = snapshot.roots
        let apply: @Sendable ([FileSystemWatcher.Event]) -> Void = { [weak self] batch in
            let before = index.itemCount
            let needsRebuild = Self.handle(batch, roots: roots, index: index)
            // Most batches change nothing countable, and those need no trip to the main actor.
            guard needsRebuild || index.itemCount != before else { return }
            Task { @MainActor in
                if needsRebuild { self?.requestRebuild() } else { self?.scheduleCountRefresh() }
            }
        }
        watcher = FileSystemWatcher(
            paths: roots, since: snapshot.eventID, queue: events, handler: apply)
    }

    private nonisolated static func handle(
        _ batch: [FileSystemWatcher.Event], roots: [String], index: FileIndex
    ) -> Bool {
        var folders: [String: Bool] = [:]
        for event in batch where !event.has(kFSEventStreamEventFlagHistoryDone) {
            if event.has(kFSEventStreamEventFlagRootChanged)
                || event.has(kFSEventStreamEventFlagEventIdsWrapped)
            {
                return true
            }
            var path = event.path
            if path.count > 1, path.hasSuffix("/") { path.removeLast() }
            let recursive = event.has(kFSEventStreamEventFlagMustScanSubDirs)
            if recursive, roots.contains(where: { FileSearchScope.contains(path, $0) }) {
                return true
            }
            folders[path] = (folders[path] ?? false) || recursive
        }
        var needsRebuild = false
        for (path, recursive) in folders where index.apply(folder: path, recursive: recursive) {
            needsRebuild = true
        }
        return needsRebuild
    }

    private func requestRebuild() {
        guard buildTask == nil else { return }
        build(after: .zero)
    }

    /// At most once a second, so a burst of disk activity redraws the count once.
    private func scheduleCountRefresh() {
        guard countRefresh == nil else { return }
        countRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            countRefresh = nil
            guard case .ready(let items, let builtAt) = status else { return }
            let count = index.itemCount
            if count != items { status = .ready(items: count, builtAt: builtAt) }
        }
    }

    /// A newer request cancels this one, which terminates its helper.
    private func build(after delay: Duration) {
        guard let policy else { return }
        buildTask?.cancel()
        let request = policy.request
        let fingerprint = policy.fingerprint
        let output = indexURL
        buildTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            // Checked even with no delay: a deactivate before this ran has already set the status.
            guard !Task.isCancelled else { return }
            self?.status = .building(items: 0)
            let report: @Sendable (Int) -> Void = { [weak self] count in
                Task { @MainActor in self?.progress(count) }
            }
            let succeeded = await FileIndexBuild.run(
                request: request, output: output, progress: report)
            guard let self, !Task.isCancelled else { return }
            buildTask = nil
            guard succeeded, let snapshot = FileIndexSnapshot(contentsOf: output),
                snapshot.fingerprint == fingerprint
            else {
                status = .failed
                return
            }
            load(snapshot)
        }
    }

    private func progress(_ count: Int) {
        guard buildTask != nil, case .building = status else { return }
        status = .building(items: count)
    }
}

/// One `FileIndexHelper` run: its progress lines are read off a blocking queue, never the pool.
private enum FileIndexBuild {
    private static let queue = DispatchQueue(
        label: "com.tinycast.file-index.build", qos: .utility, attributes: .concurrent)

    static func run(
        request: FileSearchPolicy.Request, output: URL,
        progress: @escaping @Sendable (Int) -> Void
    ) async -> Bool {
        guard !Task.isCancelled, let payload = try? JSONEncoder().encode(request) else {
            return false
        }
        try? FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/FileIndexHelper")
        process.arguments = [output.path, String(decoding: payload, as: UTF8.self)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        guard let exit = try? process.runObservingExit() else { return false }
        // Cancellation can land between the check above and the launch, which nothing else catches.
        if Task.isCancelled { terminate(process) }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    readProgress(from: pipe.fileHandleForReading, into: progress)
                    exit.wait()
                    continuation.resume(returning: process.terminationStatus == 0)
                }
            }
        } onCancel: {
            terminate(process)
        }
    }

    private static func readProgress(
        from reader: FileHandle, into progress: @Sendable (Int) -> Void
    ) {
        defer { try? reader.close() }
        var line: [UInt8] = []
        while let chunk = try? reader.read(upToCount: 4096), !chunk.isEmpty {
            var latest: Int?
            for byte in chunk {
                guard byte == 0x0A else {
                    line.append(byte)
                    continue
                }
                latest = Int(String(decoding: line, as: UTF8.self)) ?? latest
                line.removeAll(keepingCapacity: true)
            }
            if let latest { progress(latest) }
        }
    }

    /// `terminate()` traps on a process that never launched, so the state has to be asked first.
    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }
}
