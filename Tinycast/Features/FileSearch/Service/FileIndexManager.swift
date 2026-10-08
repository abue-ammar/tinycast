import Foundation
import os

/// Owns the in-memory filename index: built on the first typed query, then kept live by FSEvents.
@MainActor
@Observable
final class FileIndexManager {
    private(set) var isIndexing = false
    @ObservationIgnored private var index: FileNameIndex?
    @ObservationIgnored private var policy: FileSearchPolicy?
    @ObservationIgnored private var buildTask: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    /// Bumped on every rebuild and stop, so a walk started under older rules never lands.
    @ObservationIgnored private var generation = 0

    private static let logger = Logger(subsystem: "com.tinycast", category: "FileIndex")

    func search(
        _ rawQuery: String, filter: FileSearchFilter, policy: FileSearchPolicy
    ) async -> [FileSearchResult] {
        guard let index = await ready(for: policy) else { return [] }
        let homeDirectory = policy.homeDirectory
        return await Task.detached(priority: .userInitiated) {
            Signposts.interval("FileIndexManager.search") {
                let now = Date()
                let query = FileNameQuery(rawQuery, homeDirectory: homeDirectory, now: now)
                return index.search(
                    query, filter: filter, now: UInt32(clamping: Int(now.timeIntervalSince1970)),
                    limit: FileNameQuery.resultLimit, homeDirectory: homeDirectory)
            }
        }.value
    }

    /// Drops the index and its watcher; the next search walks the disk again.
    func stop() {
        generation &+= 1
        buildTask?.cancel()
        watchTask?.cancel()
        buildTask = nil
        watchTask = nil
        index = nil
        policy = nil
        isIndexing = false
    }

    private func ready(for policy: FileSearchPolicy) async -> FileNameIndex? {
        if policy != self.policy {
            stop()
            self.policy = policy
            rebuild()
        }
        while index == nil, let buildTask {
            await buildTask.value
            guard self.policy == policy else { return nil }
        }
        return index
    }

    /// The current index keeps answering while a replacement walks, so a rebuild never blanks results.
    private func rebuild() {
        guard let policy else { return }
        generation &+= 1
        let generation = generation
        let plan = FileIndexScanner.plan(for: policy)
        isIndexing = index == nil
        buildTask = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            let built = await Task.detached(priority: .userInitiated) {
                FileIndexScanner.build(plan)
            }.value
            guard let self, self.generation == generation else { return }
            Self.logger.info(
                "Indexed \(built.entryCount) entries in \(clock.now - start, privacy: .public)")
            index = built
            isIndexing = false
            buildTask = nil
        }
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            // Watching starts before the walk, so a change made while it runs is applied after it.
            for await batch in FileEventMonitor.batches(for: plan.roots) {
                guard let self, self.generation == generation else { return }
                if let buildTask { await buildTask.value }
                guard self.generation == generation else { return }
                await apply(batch, plan: plan, generation: generation)
            }
        }
    }

    private func apply(_ batch: FileEventMonitor.Batch, plan: FileIndexScanner.Plan, generation: Int) async {
        guard case .changes(let changes) = batch, let current = index else {
            rebuild()
            return
        }
        let (updated, outcome) = await Task.detached(priority: .utility) {
            var copy = current
            let outcome = FileIndexScanner.refresh(&copy, changes: changes, plan: plan)
            return (copy, outcome)
        }.value
        guard self.generation == generation else { return }
        if outcome == .needsRebuild {
            rebuild()
        } else {
            index = updated
        }
    }
}
