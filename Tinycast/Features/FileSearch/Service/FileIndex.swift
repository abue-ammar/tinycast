import Foundation
import Synchronization
import UniformTypeIdentifiers

final class FileIndex: Sendable {
    /// Past this many changes since the snapshot, a rebuild is cheaper than carrying them.
    static let rebuildThreshold = 100_000

    private struct Added: Sendable {
        let name: String
        let isDirectory: Bool
        let mtime: UInt32
        let prior: Int8
        let mask: UInt64
    }

    private struct State: Sendable {
        var snapshot: FileIndexSnapshot?
        var policy: FileSearchPolicy?
        var dead: [UInt64] = []
        var deadCount = 0
        var added: [String: Added] = [:]
        var addedChildren: [String: Set<String>] = [:]

        var changeCount: Int { deadCount + added.count }

        func isDead(_ index: Int) -> Bool { dead[index >> 6] & (1 << UInt64(index & 63)) != 0 }

        mutating func kill(_ index: Int, in snapshot: FileIndexSnapshot) {
            markDead(index)
            guard snapshot.isDirectory(index) else { return }
            for descendant in snapshot.subtree(of: index) { markDead(descendant) }
        }

        private mutating func markDead(_ index: Int) {
            let bit: UInt64 = 1 << UInt64(index & 63)
            guard dead[index >> 6] & bit == 0 else { return }
            dead[index >> 6] |= bit
            deadCount += 1
        }

        mutating func add(_ path: String, _ child: FileIndexCrawler.Child) {
            var name = child.name
            let mask = name.withUTF8(FileSearchQuery.nameMask)
            added[path] = Added(
                name: child.name, isDirectory: child.isDirectory, mtime: child.mtime,
                prior: child.prior, mask: mask)
            addedChildren[parentPath(of: path), default: []].insert(child.name)
        }

        mutating func remove(_ path: String, isDirectory: Bool) {
            if let entry = added.removeValue(forKey: path) {
                addedChildren[parentPath(of: path)]?.remove(entry.name)
            }
            guard isDirectory else { return }
            let prefix = path == "/" ? "/" : path + "/"
            for key in added.keys.filter({ $0.hasPrefix(prefix) }) {
                added.removeValue(forKey: key)
            }
            for key in addedChildren.keys.filter({ $0 == path || $0.hasPrefix(prefix) }) {
                addedChildren.removeValue(forKey: key)
            }
        }
    }

    private let state = Mutex(State())
    private let lister = Mutex(FileIndexCrawler.Lister())

    var snapshot: FileIndexSnapshot? { state.withLock { $0.snapshot } }

    var itemCount: Int {
        state.withLock { state in
            guard let snapshot = state.snapshot else { return 0 }
            return snapshot.entryCount - snapshot.rootCount - state.deadCount + state.added.count
        }
    }

    func replace(with snapshot: FileIndexSnapshot?, policy: FileSearchPolicy?) {
        let words = ((snapshot?.entryCount ?? 0) + 63) / 64
        state.withLock {
            $0 = State(snapshot: snapshot, policy: policy, dead: [UInt64](repeating: 0, count: words))
        }
    }

    func search(_ query: FileSearchQuery.Prepared, filter: FileSearchFilter) -> [FileSearchResult] {
        let state = state.withLock { $0 }
        guard let snapshot = state.snapshot, let policy = state.policy else { return [] }
        let limit = FileSearchQuery.resultLimit
        let names = NameScores(count: snapshot.nameCount)
        Self.chunked(0..<snapshot.nameCount, alignment: 64) { range in
            for id in range where snapshot.nameMask[id] & query.mask == query.mask {
                let score = FileSearchQuery.score(
                    query, name: snapshot.name(id: id), mask: snapshot.nameMask[id], prior: 0)
                if let score { names.set(id, score) }
            }
        }
        let base =
            names.isEmpty
            ? []
            : Self.collect(snapshot, limit: limit) { range, top in
                var types = TypeFilter(filter: filter)
                for index in range {
                    let id = Int(snapshot.nameID[index])
                    guard let score = names.score(id), !state.isDead(index),
                        types.accepts(name: snapshot.name(id: id), isDirectory: snapshot.isDirectory(index))
                    else { continue }
                    top.insert(score + FileSearchQuery.priorWeight * Int(snapshot.prior[index]), index)
                }
            }
        var ranked = base.map { hit in
            Ranked(
                score: hit.score, path: snapshot.path(of: hit.index),
                isDirectory: snapshot.isDirectory(hit.index))
        }
        var types = TypeFilter(filter: filter)
        for (path, entry) in state.added where entry.mask & query.mask == query.mask {
            var name = entry.name
            let score = name.withUTF8 { name -> Int? in
                guard
                    let score = FileSearchQuery.score(
                        query, name: name, mask: entry.mask, prior: entry.prior),
                    types.accepts(name: name, isDirectory: entry.isDirectory)
                else { return nil }
                return score
            }
            guard let score else { continue }
            ranked.append(Ranked(score: score, path: path, isDirectory: entry.isDirectory))
        }
        return Self.results(ranked, limit: limit, policy: policy)
    }

    func recent(filter: FileSearchFilter) -> [FileSearchResult] {
        let state = state.withLock { $0 }
        guard let snapshot = state.snapshot, let policy = state.policy else { return [] }
        let limit = FileSearchQuery.recentLimit
        let base = Self.collect(snapshot, limit: limit) { range, top in
            var types = TypeFilter(filter: filter)
            for index in range where snapshot.prior[index] == 2 && !snapshot.isDirectory(index) {
                guard !state.isDead(index),
                    types.accepts(name: snapshot.name(index), isDirectory: false)
                else { continue }
                top.insert(Int(snapshot.mtime[index]), index)
            }
        }
        var ranked = base.map { hit in
            Ranked(score: hit.score, path: snapshot.path(of: hit.index), isDirectory: false)
        }
        var types = TypeFilter(filter: filter)
        for (path, entry) in state.added where entry.prior == 2 && !entry.isDirectory {
            var name = entry.name
            guard name.withUTF8({ types.accepts(name: $0, isDirectory: false) }) else { continue }
            ranked.append(Ranked(score: Int(entry.mtime), path: path, isDirectory: false))
        }
        return Self.results(ranked, limit: limit, policy: policy)
    }

    private struct Ranked {
        let score: Int
        let path: String
        let isDirectory: Bool
    }

    private static func results(
        _ ranked: [Ranked], limit: Int, policy: FileSearchPolicy
    ) -> [FileSearchResult] {
        ranked.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            if left.path.count != right.path.count { return left.path.count < right.path.count }
            return left.path < right.path
        }
        .prefix(limit)
        .map { hit in
            FileSearchResult(
                url: URL(filePath: hit.path, directoryHint: hit.isDirectory ? .isDirectory : .notDirectory),
                isDirectory: hit.isDirectory, homeDirectory: policy.homeDirectory)
        }
    }

    /// Only the overall best come back, so no more paths are built than can be shown.
    private static func collect(
        _ snapshot: FileIndexSnapshot, limit: Int,
        _ scan: @Sendable (Range<Int>, inout TopHits) -> Void
    ) -> [TopHits.Hit] {
        let gathered = Gathered()
        chunked(snapshot.rootCount..<snapshot.entryCount) { range in
            var top = TopHits(limit: limit)
            scan(range, &top)
            gathered.append(top.best)
        }
        let hits = gathered.hits.sorted { left, right in
            left.score != right.score ? left.score > right.score : left.index < right.index
        }
        return Array(hits.prefix(limit))
    }

    /// Splits `range` across the cores; `alignment` keeps chunks off each other's bitset words.
    private static func chunked(
        _ range: Range<Int>, alignment: Int = 1, _ body: @Sendable (Range<Int>) -> Void
    ) {
        let chunks = max(1, min(ProcessInfo.processInfo.activeProcessorCount, range.count / 32_768))
        let size = ((range.count + chunks - 1) / chunks + alignment - 1) / alignment * alignment
        DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
            let lower = range.lowerBound + chunk * size
            let upper = min(range.upperBound, lower + size)
            if lower < upper { body(lower..<upper) }
        }
    }

    /// Idempotent, so a replayed or duplicate event is harmless; true asks for a rebuild.
    @discardableResult
    func apply(folder path: String, recursive: Bool = false) -> Bool {
        let current = state.withLock { $0 }
        guard let snapshot = current.snapshot, let policy = current.policy else { return false }
        let overlay = current.added[path]
        let base =
            overlay == nil
            ? snapshot.lookup(path).flatMap { index in
                snapshot.isDirectory(index) && !current.isDead(index) ? index : nil
            } : nil
        guard
            let prior = overlay?.isDirectory == true ? overlay?.prior : base.map({ snapshot.prior[$0] })
        else { return false }

        var diff = FolderDiff(folder: path, state: current, snapshot: snapshot, policy: policy)
        let listed = lister.withLock { lister in
            recursive
                ? diff.rescan(base: base, prior: prior, using: lister)
                : diff.compare(base: base, prior: prior, using: lister)
        }
        guard listed, !diff.isEmpty else { return false }
        return state.withLock { state in
            // A rebuild landed meanwhile; it replays this event from its own start.
            guard state.snapshot === snapshot else { return false }
            for index in diff.kills { state.kill(index, in: snapshot) }
            for removal in diff.removals { state.remove(removal.path, isDirectory: removal.isDirectory) }
            for (childPath, child) in diff.additions { state.add(childPath, child) }
            return state.changeCount > Self.rebuildThreshold
        }
    }

    /// One folder's changes. A row that did not change costs a `memcmp` and allocates nothing.
    private struct FolderDiff {
        let folder: String
        let state: State
        let snapshot: FileIndexSnapshot
        let policy: FileSearchPolicy
        private(set) var kills: [Int] = []
        private(set) var removals: [(path: String, isDirectory: Bool)] = []
        private(set) var additions: [(String, FileIndexCrawler.Child)] = []
        /// Walked once the listing is released, since walking reuses the same lister.
        private var newFolders: [(path: String, prior: Int8)] = []

        init(folder: String, state: State, snapshot: FileIndexSnapshot, policy: FileSearchPolicy) {
            self.folder = folder
            self.state = state
            self.snapshot = snapshot
            self.policy = policy
        }

        var isEmpty: Bool { kills.isEmpty && removals.isEmpty && additions.isEmpty }

        /// Both sides are sorted by name bytes, so one merge pass finds every difference.
        mutating func compare(base: Int?, prior: Int8, using lister: FileIndexCrawler.Lister) -> Bool {
            let overlayNames = state.addedChildren[folder] ?? []
            let listed: Void? = lister.list(folder, prior: prior, policy: policy) { entries, order, name in
                let rows = base.map(snapshot.children(of:)) ?? 0..<0
                var row = rows.lowerBound
                var overlaySeen = 0
                for position in order {
                    let entry = entries[position]
                    let entryName = name(entry)
                    while row < rows.upperBound, FileIndexCrawler.compare(snapshot.name(row), entryName) < 0 {
                        killIfAlive(row)
                        row += 1
                    }
                    if row < rows.upperBound, FileIndexCrawler.compare(snapshot.name(row), entryName) == 0 {
                        let matched = row
                        row += 1
                        if !state.isDead(matched) {
                            if hasChanged(matched, to: entry) {
                                kill(matched)
                                add(entry, named: String(decoding: entryName, as: UTF8.self))
                            }
                            continue
                        }
                    }
                    let text = String(decoding: entryName, as: UTF8.self)
                    guard overlayNames.contains(text) else {
                        add(entry, named: text)
                        continue
                    }
                    overlaySeen += 1
                    update(text, to: entry)
                }
                while row < rows.upperBound {
                    killIfAlive(row)
                    row += 1
                }
                guard overlaySeen < overlayNames.count else { return }
                let onDisk = Set(order.map { String(decoding: name(entries[$0]), as: UTF8.self) })
                for gone in overlayNames where !onDisk.contains(gone) { removeAdded(gone) }
            }
            guard listed != nil else { return false }
            walkNewFolders(using: lister)
            return true
        }

        /// For an event that lost its detail: everything beneath the folder is listed afresh.
        mutating func rescan(base: Int?, prior: Int8, using lister: FileIndexCrawler.Lister) -> Bool {
            if let base {
                for row in snapshot.children(of: base) { killIfAlive(row) }
            }
            for name in state.addedChildren[folder] ?? [] { removeAdded(name) }
            let listed: Void? = lister.list(folder, prior: prior, policy: policy) { entries, _, name in
                for entry in entries { add(entry, named: String(decoding: name(entry), as: UTF8.self)) }
            }
            guard listed != nil else { return false }
            walkNewFolders(using: lister)
            return true
        }

        /// Only Recent reads a date, and it lists home files alone, so other churn is ignored.
        private func hasChanged(_ row: Int, to entry: FileIndexCrawler.Entry) -> Bool {
            if snapshot.isDirectory(row) != entry.isDirectory { return true }
            return !entry.isDirectory && snapshot.prior[row] == 2 && snapshot.mtime[row] != entry.mtime
        }

        private mutating func update(_ name: String, to entry: FileIndexCrawler.Entry) {
            let path = FileIndexCrawler.path(folder, name)
            guard let added = state.added[path] else {
                add(entry, named: name)
                return
            }
            if added.isDirectory != entry.isDirectory {
                removals.append((path, added.isDirectory))
                add(entry, named: name)
            } else if !entry.isDirectory, added.prior == 2, added.mtime != entry.mtime {
                add(entry, named: name)
            }
        }

        private mutating func killIfAlive(_ row: Int) {
            if !state.isDead(row) { kill(row) }
        }

        /// A vanished folder also takes whatever the overlay added beneath it.
        private mutating func kill(_ row: Int) {
            kills.append(row)
            guard snapshot.isDirectory(row) else { return }
            removals.append((FileIndexCrawler.path(folder, snapshot.nameString(row)), true))
        }

        private mutating func removeAdded(_ name: String) {
            let path = FileIndexCrawler.path(folder, name)
            removals.append((path, state.added[path]?.isDirectory ?? false))
        }

        private mutating func add(_ entry: FileIndexCrawler.Entry, named name: String) {
            let child = FileIndexCrawler.Child(entry, name: name, parent: folder, policy: policy)
            let path = FileIndexCrawler.path(folder, name)
            additions.append((path, child))
            if child.isDirectory { newFolders.append((path, child.prior)) }
        }

        private mutating func walkNewFolders(using lister: FileIndexCrawler.Lister) {
            for (path, prior) in newFolders {
                additions += lister.walk(path, prior: prior, policy: policy)
            }
            newFolders = []
        }
    }
}

private func parentPath(of path: String) -> String {
    guard let slash = path.lastIndex(of: "/") else { return path }
    return slash == path.startIndex ? "/" : String(path[..<slash])
}

private struct TopHits {
    struct Hit: Sendable {
        let score: Int
        let index: Int
    }

    let limit: Int
    private var hits: [Hit] = []
    private var floor = Int.min

    init(limit: Int) { self.limit = limit }

    mutating func insert(_ score: Int, _ index: Int) {
        guard score > floor else { return }
        hits.append(Hit(score: score, index: index))
        guard hits.count >= limit * 4 else { return }
        hits.sort { $0.score > $1.score }
        hits.removeSubrange(limit...)
        floor = hits[limit - 1].score
    }

    var best: [Hit] { Array(hits.sorted { $0.score > $1.score }.prefix(limit)) }
}

/// Unchecked: each chunk writes only its own 64-aligned range of names.
private final class NameScores: @unchecked Sendable {
    private let matched: UnsafeMutableBufferPointer<UInt64>
    private let scores: UnsafeMutableBufferPointer<Int32>

    init(count: Int) {
        matched = .allocate(capacity: (count + 63) / 64)
        matched.initialize(repeating: 0)
        scores = .allocate(capacity: max(count, 1))
    }

    deinit {
        matched.deallocate()
        scores.deallocate()
    }

    var isEmpty: Bool { !matched.contains { $0 != 0 } }

    func set(_ id: Int, _ score: Int) {
        scores[id] = Int32(clamping: score)
        matched[id >> 6] |= 1 << UInt64(id & 63)
    }

    func score(_ id: Int) -> Int? {
        matched[id >> 6] & (1 << UInt64(id & 63)) != 0 ? Int(scores[id]) : nil
    }
}

private final class Gathered: Sendable {
    private let storage = Mutex<[TopHits.Hit]>([])

    func append(_ hits: [TopHits.Hit]) { storage.withLock { $0 += hits } }

    var hits: [TopHits.Hit] { storage.withLock { $0 } }
}

private struct TypeFilter {
    let filter: FileSearchFilter
    private var cache: [String: Bool] = [:]

    init(filter: FileSearchFilter) { self.filter = filter }

    mutating func accepts(name: UnsafeBufferPointer<UInt8>, isDirectory: Bool) -> Bool {
        guard filter != .all else { return true }
        if filter == .folders && !isDirectory { return false }
        var pathExtension = ""
        if let dot = name.lastIndex(of: 0x2E), dot > 0 {
            pathExtension = String(decoding: name[(dot + 1)...], as: UTF8.self).lowercased()
        }
        let key = isDirectory ? "/" + pathExtension : pathExtension
        if let known = cache[key] { return known }
        let type = FileSearchFilter.contentType(extension: pathExtension, isDirectory: isDirectory)
        let accepted = filter.accepts(contentType: type, isDirectory: isDirectory)
        cache[key] = accepted
        return accepted
    }
}
