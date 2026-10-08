import Foundation

/// Every indexed file and folder, held as interned names. See docs/features/file-search.md#index.
struct FileNameIndex: Sendable {
    typealias Bytes = UnsafeBufferPointer<UInt8>

    enum Kind: Sendable, Equatable {
        case file
        case link
        /// A folder whose contents are indexed, or one left closed: a mount or another root.
        case folder
        case package
    }

    struct Entry: Sendable, Equatable {
        let name: UInt32
        /// Seconds since 1970.
        let modified: UInt32
        /// A descended folder's directory, or a negative code naming the kind.
        private let child: Int32

        init(name: UInt32, modified: UInt32, kind: Kind, directory: Int32? = nil) {
            self.name = name
            self.modified = modified
            if let directory {
                child = directory
            } else {
                switch kind {
                case .file: child = -1
                case .link: child = -2
                case .folder: child = -3
                case .package: child = -4
                }
            }
        }

        var directory: Int32? { child >= 0 ? child : nil }

        var kind: Kind {
            switch child {
            case -1: .file
            case -2: .link
            case -4: .package
            default: .folder
            }
        }

        var isDirectory: Bool { kind == .folder || kind == .package }
    }

    struct Root: Sendable, Equatable {
        let path: String
        let directory: Int32
    }

    private struct Directory: Sendable {
        /// `noParent` for a root, `deadParent` once the slot is free for reuse.
        var parent: Int32
        var name: UInt32
        /// fsearch's location prior: what this folder's name says about everything under it.
        var prior: Int8
        var entries: ContiguousArray<Entry>
    }

    private static let noParent: Int32 = -1
    private static let deadParent: Int32 = -2

    private(set) var roots: [Root] = []
    private var directories: [Directory] = []
    private var freeDirectories: [Int32] = []
    private(set) var entryCount = 0
    private var names = NameTable()

    var nameCount: Int { names.count }
    var directoryCount: Int { directories.count - freeDirectories.count }

    // MARK: Building

    mutating func intern(_ name: Bytes) -> UInt32 { names.intern(name) }

    mutating func intern(_ name: String) -> UInt32 {
        var name = name
        return name.withUTF8 { names.intern($0) }
    }

    func name(_ id: UInt32) -> String {
        names.withName(id) { String(decoding: $0, as: UTF8.self) }
    }

    mutating func addRoot(path: String) -> Int32 {
        let name = intern(path == "/" ? "/" : String(path.split(separator: "/").last ?? ""))
        let directory = allocate(Directory(parent: Self.noParent, name: name, prior: 0, entries: []))
        roots.append(Root(path: path, directory: directory))
        return directory
    }

    /// A folder's own record; its entry in `parent` is the caller's to write, with the id this returns.
    mutating func addDirectory(name: UInt32, parent: Int32) -> Int32 {
        let adjustment = names.withName(name) { Self.priorAdjustment($0) }
        let prior = Int8(clamping: max(-100, min(60, Int(directories[Int(parent)].prior) + adjustment)))
        return allocate(Directory(parent: parent, name: name, prior: prior, entries: []))
    }

    func entries(of directory: Int32) -> ContiguousArray<Entry> {
        directories[Int(directory)].entries
    }

    /// Any folder the new list no longer descends into leaves the index with everything under it.
    mutating func replaceEntries(of directory: Int32, with entries: ContiguousArray<Entry>) {
        let kept = Set(entries.lazy.compactMap(\.directory))
        for entry in directories[Int(directory)].entries {
            if let child = entry.directory, !kept.contains(child) { removeSubtree(child) }
        }
        entryCount += entries.count - directories[Int(directory)].entries.count
        directories[Int(directory)].entries = entries
    }

    mutating func removeSubtree(_ directory: Int32) {
        var pending = [directory]
        while let next = pending.popLast() {
            let index = Int(next)
            guard directories[index].parent != Self.deadParent else { continue }
            for entry in directories[index].entries {
                if let child = entry.directory { pending.append(child) }
            }
            entryCount -= directories[index].entries.count
            directories[index] = Directory(
                parent: Self.deadParent, name: 0, prior: 0, entries: [])
            freeDirectories.append(next)
        }
    }

    /// Renames and deletions strand names; past twice the live count, drop the ones nothing uses.
    mutating func compactNamesIfNeeded() {
        guard names.count > 2 * entryCount + 10_000 else { return }
        var compacted = NameTable()
        var remap = [UInt32](repeating: .max, count: names.count)
        func moved(_ id: UInt32) -> UInt32 {
            if remap[Int(id)] == .max {
                remap[Int(id)] = names.withName(id) { compacted.intern($0) }
            }
            return remap[Int(id)]
        }
        for index in directories.indices where directories[index].parent != Self.deadParent {
            directories[index].name = moved(directories[index].name)
            directories[index].entries = ContiguousArray(directories[index].entries.map { entry in
                Entry(
                    name: moved(entry.name), modified: entry.modified, kind: entry.kind,
                    directory: entry.directory)
            })
        }
        names = compacted
    }

    private mutating func allocate(_ directory: Directory) -> Int32 {
        if let reused = freeDirectories.popLast() {
            directories[Int(reused)] = directory
            return reused
        }
        directories.append(directory)
        return Int32(directories.count - 1)
    }

    // MARK: Paths

    /// The folder at an absolute path, if the index descends into it.
    func directory(atPath path: String) -> Int32? {
        for root in roots.sorted(by: { $0.path.count > $1.path.count }) {
            if path == root.path { return root.directory }
            let prefix = root.path == "/" ? "/" : root.path + "/"
            guard path.hasPrefix(prefix) else { continue }
            var current = root.directory
            for component in path.dropFirst(prefix.count).split(separator: "/") {
                guard let child = child(named: component, in: current) else { return nil }
                current = child
            }
            return current
        }
        return nil
    }

    func path(of directory: Int32) -> String {
        var components: [String] = []
        var current = directory
        while directories[Int(current)].parent >= 0 {
            components.append(name(directories[Int(current)].name))
            current = directories[Int(current)].parent
        }
        let root = roots.first { $0.directory == current }?.path ?? "/"
        guard !components.isEmpty else { return root }
        return (root == "/" ? "" : root) + "/" + components.reversed().joined(separator: "/")
    }

    private func child(named component: Substring, in directory: Int32) -> Int32? {
        var component = String(component)
        return component.withUTF8 { wanted in
            directories[Int(directory)].entries.first { entry in
                entry.directory != nil && names.withName(entry.name) { $0.elementsEqual(wanted) }
            }?.directory
        }
    }

    // MARK: Search

    /// Ranked best first; ties fall to the name, then the path, so a list never reshuffles.
    func search(
        _ query: FileNameQuery, filter: FileSearchFilter, now: UInt32, limit: Int,
        homeDirectory: URL
    ) -> [FileSearchResult] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var scope: Int32?
        if let path = query.scope {
            guard let directory = directory(atPath: path) else { return [] }
            scope = directory
        }
        let hits = scoreNames(query, filter: filter)
        let candidates = scoreEntries(
            query, hits: hits, scope: scope, filter: filter, now: now, limit: limit)
        return results(candidates, homeDirectory: homeDirectory)
    }

    private struct NameHit {
        var score: Int16 = 0
        var bits: UInt8 = 0
        var flags: UInt8 = 0
        /// The first four tokens' own scores, which a folder hands down to what it holds.
        var best = SIMD4<Int16>(repeating: 0)

        static let present: UInt8 = 1
        static let matches: UInt8 = 2
        static let negated: UInt8 = 4
        static let acceptedAsFile: UInt8 = 8
        static let acceptedAsPackage: UInt8 = 16
    }

    /// Each distinct name scored once: a few hundred thousand names stand for every entry.
    private func scoreNames(_ query: FileNameQuery, filter: FileSearchFilter) -> [NameHit] {
        let positive = query.positive
        let negative = query.negative
        let texts = TokenTexts(positive + negative)
        var hits = [NameHit](repeating: NameHit(), count: names.count)
        var typeMemo: [[UInt8]: (file: Bool, package: Bool)] = [:]
        texts.withBuffers { buffers in
            names.withKeys { key, mask, id in
                if !positive.isEmpty && !positive.contains(where: { $0.fits(mask) })
                    && !negative.contains(where: { $0.fits(mask) })
                {
                    return
                }
                var hit = NameHit(flags: NameHit.present)
                var total = 0
                for (index, token) in positive.enumerated() where token.fits(mask) {
                    guard
                        let score = FileNameMatch.score(
                            key, nameMask: mask, token: token, text: buffers[index])
                    else { continue }
                    hit.bits |= 1 << UInt8(index)
                    total += score
                    if index < 4 { hit.best[index] = Int16(clamping: max(score, 0)) }
                }
                hit.score = Int16(clamping: total)
                for (offset, token) in negative.enumerated() where token.fits(mask) {
                    if FileNameMatch.matches(key, token: token, text: buffers[positive.count + offset]) {
                        hit.flags |= NameHit.negated
                        break
                    }
                }
                let isMatch =
                    (positive.isEmpty || hit.bits != 0) && hit.flags & NameHit.negated == 0
                    && Self.hasExtension(key, in: query.extensions)
                if isMatch {
                    hit.flags |= NameHit.matches
                    if filter != .all {
                        let pathExtension = Self.pathExtension(key)
                        let accepted = typeMemo[pathExtension] ?? {
                            let text = String(decoding: pathExtension, as: UTF8.self)
                            let pair = (
                                filter.accepts(pathExtension: text, isPackage: false),
                                filter.accepts(pathExtension: text, isPackage: true))
                            typeMemo[pathExtension] = pair
                            return pair
                        }()
                        if accepted.file { hit.flags |= NameHit.acceptedAsFile }
                        if accepted.package { hit.flags |= NameHit.acceptedAsPackage }
                    }
                }
                hits[Int(id)] = hit
            }
        }
        return hits
    }

    private struct Candidate {
        let score: Int32
        let directory: Int32
        let entry: Int32

        func ranks(above other: Candidate) -> Bool {
            if score != other.score { return score > other.score }
            if directory != other.directory { return directory < other.directory }
            return entry < other.entry
        }
    }

    /// What the folders above an entry contribute: tokens matched on the way down, or a veto.
    private struct FolderMemo {
        var bits: UInt8 = 0
        var isNegated = false
        var best = SIMD4<Int16>(repeating: 0)
    }

    private func scoreEntries(
        _ query: FileNameQuery, hits: [NameHit], scope: Int32?, filter: FileSearchFilter,
        now: UInt32, limit: Int
    ) -> [Candidate] {
        let positiveCount = query.positive.count
        let needsFolders = positiveCount > 1 || !query.negative.isEmpty
        let allBits: UInt8 = positiveCount == 0 ? 0 : UInt8(truncatingIfNeeded: (1 << positiveCount) - 1)
        var folders = FolderMemos(count: directories.count)
        var inScope = [UInt8](repeating: 0, count: scope == nil ? 0 : directories.count)
        var top = TopCandidates(limit: limit)

        for index in directories.indices where directories[index].parent != Self.deadParent {
            let directory = Int32(index)
            if let scope, !isInside(directory, scope, memo: &inScope) { continue }
            let memo = needsFolders ? folders.memo(of: directory, in: self, hits: hits) : FolderMemo()
            if memo.isNegated { continue }
            let prior = Int32(directories[index].prior)
            for (position, entry) in directories[index].entries.enumerated() {
                let hit = hits[Int(entry.name)]
                guard hit.flags & NameHit.matches != 0,
                    Self.passes(entry, hit: hit, query: query, filter: filter)
                else { continue }
                var score = Int32(hit.score)
                if needsFolders {
                    guard (hit.bits | memo.bits) & allBits == allBits else { continue }
                    for token in 0..<positiveCount where hit.bits & (1 << UInt8(token)) == 0 {
                        score += token < 4 ? Int32(memo.best[token]) * 3 / 4 : 6
                    }
                }
                score += prior + Self.recencyBonus(entry.modified, now: now)
                top.offer(Candidate(score: score, directory: directory, entry: Int32(position)))
            }
        }
        return top.finished()
    }

    private static func passes(
        _ entry: Entry, hit: NameHit, query: FileNameQuery, filter: FileSearchFilter
    ) -> Bool {
        let kind = entry.kind
        switch query.kind {
        case .folder? where kind != .folder: return false
        case .file? where kind == .folder: return false
        default: break
        }
        if let modified = query.modified, !modified.contains(entry.modified) { return false }
        switch filter {
        case .all: return true
        case .folders: return kind == .folder
        default:
            switch kind {
            case .folder: return false
            case .package: return hit.flags & NameHit.acceptedAsPackage != 0
            case .file, .link: return hit.flags & NameHit.acceptedAsFile != 0
            }
        }
    }

    private func isInside(_ directory: Int32, _ scope: Int32, memo: inout [UInt8]) -> Bool {
        var chain: [Int32] = []
        var current = directory
        var answer = false
        while true {
            let known = memo[Int(current)]
            if known != 0 {
                answer = known == 1
                break
            }
            if current == scope {
                answer = true
                break
            }
            chain.append(current)
            let parent = directories[Int(current)].parent
            if parent < 0 { break }
            current = parent
        }
        for link in chain { memo[Int(link)] = answer ? 1 : 2 }
        return answer
    }

    private struct FolderMemos {
        private var memos: [FolderMemo]
        private var known: [Bool]

        init(count: Int) {
            memos = [FolderMemo](repeating: FolderMemo(), count: count)
            known = [Bool](repeating: false, count: count)
        }

        mutating func memo(of directory: Int32, in index: FileNameIndex, hits: [NameHit]) -> FolderMemo {
            var chain: [Int32] = []
            var current = directory
            var inherited = FolderMemo()
            while current >= 0 {
                if known[Int(current)] {
                    inherited = memos[Int(current)]
                    break
                }
                chain.append(current)
                current = index.directories[Int(current)].parent
            }
            for link in chain.reversed() {
                let hit = hits[Int(index.directories[Int(link)].name)]
                var memo = inherited
                if hit.flags & NameHit.negated != 0 { memo.isNegated = true }
                memo.bits |= hit.bits
                memo.best = pointwiseMax(memo.best, hit.best)
                memos[Int(link)] = memo
                known[Int(link)] = true
                inherited = memo
            }
            return inherited
        }
    }

    /// Survivors gather past the floor and are cut back now and then: cheaper than a heap.
    private struct TopCandidates {
        let limit: Int
        private var buffer: [Candidate] = []
        private var floor: Candidate?

        init(limit: Int) {
            self.limit = limit
            buffer.reserveCapacity(max(limit * 4, 256))
        }

        mutating func offer(_ candidate: Candidate) {
            if let floor, !candidate.ranks(above: floor) { return }
            buffer.append(candidate)
            if buffer.count >= max(limit * 4, 256) { cut() }
        }

        mutating func finished() -> [Candidate] {
            cut()
            return buffer
        }

        private mutating func cut() {
            buffer.sort { $0.ranks(above: $1) }
            guard buffer.count > limit else { return }
            buffer.removeLast(buffer.count - limit)
            floor = buffer.last
        }
    }

    private func results(_ candidates: [Candidate], homeDirectory: URL) -> [FileSearchResult] {
        var folderPaths: [Int32: String] = [:]
        var ranked: [(result: FileSearchResult, score: Int32)] = []
        for candidate in candidates {
            let entry = directories[Int(candidate.directory)].entries[Int(candidate.entry)]
            let folder: String
            if let known = folderPaths[candidate.directory] {
                folder = known
            } else {
                folder = path(of: candidate.directory)
                folderPaths[candidate.directory] = folder
            }
            let fullPath = (folder == "/" ? "" : folder) + "/" + name(entry.name)
            let result = FileSearchResult(
                url: URL(fileURLWithPath: fullPath, isDirectory: entry.isDirectory),
                isDirectory: entry.isDirectory, homeDirectory: homeDirectory)
            ranked.append((result, candidate.score))
        }
        return ranked.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            let names = left.result.name.localizedCaseInsensitiveCompare(right.result.name)
            if names != .orderedSame { return names == .orderedAscending }
            return left.result.id.localizedCaseInsensitiveCompare(right.result.id)
                == .orderedAscending
        }.map(\.result)
    }

    // MARK: Ranking facts

    private static func recencyBonus(_ modified: UInt32, now: UInt32) -> Int32 {
        switch now &- modified {
        case 0...86_400: 10
        case 86_401...604_800: 7
        case 604_801...2_592_000: 4
        case 2_592_001...31_536_000: 1
        default: 0
        }
    }

    private static let bundleSuffixes = [
        ".framework", ".bundle", ".plugin", ".appex", ".kext", ".xpc", ".lproj", ".xcassets",
        ".photoslibrary", ".musiclibrary", ".tvlibrary", ".imovielibrary", ".dsym", ".xcarchive",
        ".sdk", ".platform"
    ]

    /// How much a folder's name moves everything under it, from fsearch's table.
    private static func priorAdjustment(_ name: Bytes) -> Int {
        let text = String(decoding: name, as: UTF8.self)
        let lowered = text.lowercased()
        if text == "Applications" { return 30 }
        if lowered.hasSuffix(".app") { return -25 }
        if bundleSuffixes.contains(where: { lowered.count > $0.count && lowered.hasSuffix($0) }) {
            return -20
        }
        if text.hasPrefix(".") { return -25 }
        switch text {
        case "Library": return -20
        case "Caches", "caches", "cache", "Cache", "Logs", "DerivedData", "CoreSimulator": return -20
        case "node_modules", "__pycache__", "site-packages", "Pods", "venv", "bower_components":
            return -30
        case "target", "build", "dist", "out", "vendor", "deps", "tmp", "temp": return -12
        case "folders", "Containers", "Group Containers": return -10
        case "Application Support": return -5
        default: return 0
        }
    }

    private static func pathExtension(_ name: Bytes) -> [UInt8] {
        guard let dot = name.lastIndex(of: 0x2E), dot > 0, dot < name.count - 1 else { return [] }
        return name[(dot + 1)...].map(FileNameMatch.fold)
    }

    private static func hasExtension(_ name: Bytes, in extensions: [[UInt8]]) -> Bool {
        guard !extensions.isEmpty else { return true }
        let found = pathExtension(name)
        return !found.isEmpty && extensions.contains(found)
    }
}

/// Token texts laid end to end, so a search borrows one buffer rather than one per token.
private struct TokenTexts {
    private let bytes: [UInt8]
    private let ranges: [Range<Int>]

    init(_ tokens: [FileNameMatch.Token]) {
        var bytes: [UInt8] = []
        var ranges: [Range<Int>] = []
        for token in tokens {
            ranges.append(bytes.count..<(bytes.count + token.text.count))
            bytes += token.text
        }
        self.bytes = bytes
        self.ranges = ranges
    }

    func withBuffers<T>(_ body: ([FileNameMatch.Bytes]) -> T) -> T {
        bytes.withUnsafeBufferPointer { all in
            body(ranges.map { FileNameMatch.Bytes(rebasing: all[$0]) })
        }
    }
}

/// Distinct names, interned through an open-addressed table of ids so no name is a heap object.
private struct NameTable: Sendable {
    private var bytes: [UInt8] = []
    /// Each record is the name, then its folded key when that differs; `count + 1` long.
    private var starts: [UInt32] = [0]
    private var keyStarts: [UInt32] = []
    private var masks: [UInt64] = []
    /// `id + 1`, zero for an empty slot; kept at most half full.
    private var slots = [UInt32](repeating: 0, count: 1 << 12)

    var count: Int { masks.count }

    mutating func intern(_ name: FileNameIndex.Bytes) -> UInt32 {
        if (count + 1) * 2 > slots.count { grow() }
        var slot = Int(Self.hash(name) & UInt64(slots.count - 1))
        while slots[slot] != 0 {
            let id = slots[slot] - 1
            if withName(id, { $0.elementsEqual(name) }) { return id }
            slot = (slot + 1) & (slots.count - 1)
        }
        let id = UInt32(count)
        append(name)
        slots[slot] = id + 1
        return id
    }

    func withName<T>(_ id: UInt32, _ body: (FileNameIndex.Bytes) -> T) -> T {
        let start = Int(starts[Int(id)])
        let end = Int(keyStarts[Int(id)])
        return bytes.withUnsafeBufferPointer { body(FileNameIndex.Bytes(rebasing: $0[start..<end])) }
    }

    /// Every name's match key and mask, in id order: the one loop a search spends its time in.
    func withKeys(_ body: (FileNameIndex.Bytes, UInt64, UInt32) -> Void) {
        bytes.withUnsafeBufferPointer { all in
            starts.withUnsafeBufferPointer { starts in
                keyStarts.withUnsafeBufferPointer { keyStarts in
                    masks.withUnsafeBufferPointer { masks in
                        for id in 0..<masks.count {
                            let start = Int(starts[id])
                            let keyStart = Int(keyStarts[id])
                            let end = Int(starts[id + 1])
                            let key = keyStart < end ? keyStart..<end : start..<keyStart
                            body(FileNameIndex.Bytes(rebasing: all[key]), masks[id], UInt32(id))
                        }
                    }
                }
            }
        }
    }

    /// A non-ASCII name also stores the launcher's fold of it, so `resume` finds `Résumé`.
    private mutating func append(_ name: FileNameIndex.Bytes) {
        bytes.append(contentsOf: name)
        keyStarts.append(UInt32(bytes.count))
        var key: [UInt8]?
        if name.contains(where: { $0 >= 0x80 }) {
            let folded = Array(FuzzyMatch.normalized(String(decoding: name, as: UTF8.self)).utf8)
            if !folded.elementsEqual(name) {
                key = folded
                bytes.append(contentsOf: folded)
            }
        }
        starts.append(UInt32(bytes.count))
        masks.append(
            key.map { $0.withUnsafeBufferPointer(FileNameMatch.nameMask) }
                ?? FileNameMatch.nameMask(name))
    }

    private mutating func grow() {
        slots = [UInt32](repeating: 0, count: slots.count * 2)
        for id in 0..<UInt32(count) {
            var slot = Int(withName(id, Self.hash) & UInt64(slots.count - 1))
            while slots[slot] != 0 { slot = (slot + 1) & (slots.count - 1) }
            slots[slot] = id + 1
        }
    }

    /// FNV-1a: interning wants something far cheaper than `Hasher`'s SipHash per name.
    private static func hash(_ name: FileNameIndex.Bytes) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}
