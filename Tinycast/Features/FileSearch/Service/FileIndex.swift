import Foundation
import Synchronization
import UniformTypeIdentifiers

/// A search copies the state under the lock and scans without it.
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

        /// A folder takes its whole subtree with it, which block order makes one range.
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
        let base = Self.collect(snapshot, limit: limit) { range, top in
            var types = TypeFilter(filter: filter)
            for index in range where snapshot.mask[index] & query.mask == query.mask {
                guard !state.isDead(index) else { continue }
                let name = snapshot.name(index)
                guard
                    let score = FileSearchQuery.score(
                        query, name: name, mask: snapshot.mask[index], prior: snapshot.prior[index]),
                    types.accepts(name: name, isDirectory: snapshot.isDirectory(index))
                else { continue }
                top.insert(score, index)
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
                url: URL(fileURLWithPath: hit.path, isDirectory: hit.isDirectory),
                isDirectory: hit.isDirectory, homeDirectory: policy.homeDirectory)
        }
    }

    /// Only the overall best come back, so no more paths are built than can be shown.
    private static func collect(
        _ snapshot: FileIndexSnapshot, limit: Int,
        _ scan: @escaping @Sendable (Range<Int>, inout TopHits) -> Void
    ) -> [TopHits.Hit] {
        let range = snapshot.rootCount..<snapshot.entryCount
        let chunks = max(1, min(ProcessInfo.processInfo.activeProcessorCount, range.count / 32_768))
        let gathered = Gathered()
        DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
            let lower = range.lowerBound + range.count * chunk / chunks
            let upper = range.lowerBound + range.count * (chunk + 1) / chunks
            var top = TopHits(limit: limit)
            scan(lower..<upper, &top)
            gathered.append(top.best)
        }
        let hits = gathered.hits.sorted { left, right in
            left.score != right.score ? left.score > right.score : left.index < right.index
        }
        return Array(hits.prefix(limit))
    }

    /// Idempotent, so a replayed or duplicate event is harmless; true asks for a rebuild.
    @discardableResult
    func apply(folder path: String, recursive: Bool = false) -> Bool {
        let current = state.withLock { $0 }
        guard let snapshot = current.snapshot, let policy = current.policy else { return false }
        let overlay = current.added[path]
        let baseIndex =
            overlay == nil
            ? snapshot.lookup(path).flatMap { index in
                snapshot.isDirectory(index) && !current.isDead(index) ? index : nil
            } : nil
        guard
            let prior = overlay?.isDirectory == true ? overlay?.prior : baseIndex.map({ snapshot.prior[$0] })
        else { return false }

        var known: [String: (base: Int?, isDirectory: Bool, mtime: UInt32)] = [:]
        if let baseIndex {
            for index in snapshot.children(of: baseIndex) where !current.isDead(index) {
                known[snapshot.nameString(index)] = (
                    index, snapshot.isDirectory(index), snapshot.mtime[index]
                )
            }
        }
        for name in current.addedChildren[path] ?? [] {
            guard let entry = current.added[FileIndexCrawler.path(path, name)] else { continue }
            known[name] = (nil, entry.isDirectory, entry.mtime)
        }

        var kills: [Int] = []
        var removals: [(path: String, isDirectory: Bool)] = []
        var additions: [(String, FileIndexCrawler.Child)] = []
        func drop(_ name: String) {
            guard let entry = known[name] else { return }
            if let index = entry.base { kills.append(index) }
            removals.append((FileIndexCrawler.path(path, name), entry.isDirectory))
        }
        func add(_ child: FileIndexCrawler.Child) {
            let childPath = FileIndexCrawler.path(path, child.name)
            additions.append((childPath, child))
            if child.isDirectory {
                additions += FileIndexCrawler.walk(childPath, prior: child.prior, policy: policy)
            }
        }

        if recursive {
            known.keys.forEach(drop)
            guard let children = FileIndexCrawler.children(of: path, prior: prior, policy: policy)
            else { return false }
            children.forEach(add)
        } else {
            guard let children = FileIndexCrawler.children(of: path, prior: prior, policy: policy)
            else { return false }
            var seen = Set<String>()
            for child in children {
                seen.insert(child.name)
                guard let entry = known[child.name] else {
                    add(child)
                    continue
                }
                if entry.isDirectory != child.isDirectory {
                    drop(child.name)
                    add(child)
                } else if !child.isDirectory, entry.mtime != child.mtime {
                    // A base row is immutable, so a new date replaces it from the overlay.
                    if let index = entry.base { kills.append(index) }
                    additions.append((FileIndexCrawler.path(path, child.name), child))
                }
            }
            for name in known.keys where !seen.contains(name) { drop(name) }
        }

        guard !kills.isEmpty || !removals.isEmpty || !additions.isEmpty else { return false }
        return state.withLock { state in
            // A rebuild landed meanwhile; it replays this event from its own start.
            guard state.snapshot === snapshot else { return false }
            for index in kills { state.kill(index, in: snapshot) }
            for removal in removals { state.remove(removal.path, isDirectory: removal.isDirectory) }
            for (childPath, child) in additions { state.add(childPath, child) }
            return state.changeCount > Self.rebuildThreshold
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

private final class Gathered: Sendable {
    private let storage = Mutex<[TopHits.Hit]>([])

    func append(_ hits: [TopHits.Hit]) { storage.withLock { $0 += hits } }

    var hits: [TopHits.Hit] { storage.withLock { $0 } }
}

/// The extension is resolved once per search, not once per row.
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
