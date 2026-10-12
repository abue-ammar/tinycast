import Darwin
import Foundation

/// Mapped read-only: clean file-backed pages, which never count as app memory.
final class FileIndexSnapshot: @unchecked Sendable {
    static let fileName = "index.bin"

    private struct Header {
        static let size = 96
        static let magic: UInt64 = 0x3130_5844_4946_4354
        static let version: UInt32 = 2

        var magic = Header.magic
        var version = Header.version
        var rootCount: UInt32
        var entryCount: UInt64
        var folderCount: UInt64
        var blockCount: UInt64
        var nameCount: UInt64
        var namesLength: UInt64
        var eventID: UInt64
        var fingerprint: UInt64
        var builtAt: Double

        var sections: [(size: Int, count: Int)] {
            let entries = Int(entryCount)
            let words = (entries + 63) / 64
            let folders = Int(folderCount)
            let blocks = Int(blockCount)
            let names = Int(nameCount)
            return [
                (4, entries), (4, entries), (1, entries), (8, words), (4, words),
                (4, folders), (4, folders), (4, folders), (4, blocks), (4, blocks),
                (4, names), (8, names), (1, Int(namesLength))
            ]
        }

        /// Bounds every count before it is used, so a damaged file cannot overflow the layout.
        func isValid(fileSize: Int) -> Bool {
            magic == Header.magic && version == Header.version && rootCount > 0
                && UInt64(rootCount) <= entryCount && entryCount <= UInt64(UInt32.max)
                && folderCount <= entryCount && blockCount <= folderCount
                && nameCount <= entryCount && namesLength <= UInt64(fileSize)
        }
    }

    let rootCount: Int
    let entryCount: Int
    let nameCount: Int
    /// The FSEvents id from before the crawl began, so a replay from it misses nothing.
    let eventID: UInt64
    let fingerprint: UInt64
    let builtAt: Date
    let nameID: UnsafeBufferPointer<UInt32>
    let mtime: UnsafeBufferPointer<UInt32>
    let prior: UnsafeBufferPointer<Int8>
    let nameMask: UnsafeBufferPointer<UInt64>
    private let directoryBits: UnsafeBufferPointer<UInt64>
    private let directoryRank: UnsafeBufferPointer<UInt32>
    private let childStart: UnsafeBufferPointer<UInt32>
    private let childCount: UnsafeBufferPointer<UInt32>
    private let subtreeEnd: UnsafeBufferPointer<UInt32>
    private let blockStart: UnsafeBufferPointer<UInt32>
    private let blockOwner: UnsafeBufferPointer<UInt32>
    private let nameEnd: UnsafeBufferPointer<UInt32>
    private let names: UnsafeBufferPointer<UInt8>
    private let mapping: UnsafeMutableRawPointer
    private let mappedSize: Int

    init?(contentsOf url: URL) {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size >= Header.size else { return nil }
        let size = Int(info.st_size)
        guard let base = mmap(nil, size, PROT_READ, MAP_PRIVATE, descriptor, 0),
            Int(bitPattern: base) != -1
        else { return nil }
        let header = base.loadUnaligned(as: Header.self)
        let offsets = header.isValid(fileSize: size) ? Self.offsets(of: header.sections) : []
        guard offsets.last == size else {
            munmap(base, size)
            return nil
        }
        func section<T>(_ index: Int) -> UnsafeBufferPointer<T> {
            UnsafeBufferPointer(
                start: (base + offsets[index]).assumingMemoryBound(to: T.self),
                count: header.sections[index].count)
        }
        mapping = base
        mappedSize = size
        rootCount = Int(header.rootCount)
        entryCount = Int(header.entryCount)
        nameCount = Int(header.nameCount)
        eventID = header.eventID
        fingerprint = header.fingerprint
        builtAt = Date(timeIntervalSince1970: header.builtAt)
        nameID = section(0)
        mtime = section(1)
        prior = section(2)
        directoryBits = section(3)
        directoryRank = section(4)
        childStart = section(5)
        childCount = section(6)
        subtreeEnd = section(7)
        blockStart = section(8)
        blockOwner = section(9)
        nameEnd = section(10)
        nameMask = section(11)
        names = section(12)
    }

    deinit {
        munmap(mapping, mappedSize)
    }

    func name(id: Int) -> UnsafeBufferPointer<UInt8> {
        let start = id == 0 ? 0 : Int(nameEnd[id - 1])
        return UnsafeBufferPointer(rebasing: names[start..<Int(nameEnd[id])])
    }

    func name(_ index: Int) -> UnsafeBufferPointer<UInt8> { name(id: Int(nameID[index])) }

    func nameString(_ index: Int) -> String { String(decoding: name(index), as: UTF8.self) }

    func isDirectory(_ index: Int) -> Bool {
        directoryBits[index >> 6] & (1 << UInt64(index & 63)) != 0
    }

    func children(of index: Int) -> Range<Int> {
        guard let folder = folder(of: index) else { return 0..<0 }
        let start = Int(childStart[folder])
        return start..<start + Int(childCount[folder])
    }

    func subtree(of index: Int) -> Range<Int> {
        guard let folder = folder(of: index) else { return 0..<0 }
        return Int(childStart[folder])..<Int(subtreeEnd[folder])
    }

    var roots: [String] { (0..<rootCount).map(nameString) }

    func path(of index: Int) -> String {
        var components: [String] = []
        var current = index
        while current >= rootCount {
            components.append(nameString(current))
            current = parent(of: current)
        }
        let root = nameString(current)
        guard !components.isEmpty else { return root }
        let tail = components.reversed().joined(separator: "/")
        return root == "/" ? "/" + tail : root + "/" + tail
    }

    func lookup(_ path: String) -> Int? {
        for root in 0..<rootCount {
            let rootPath = nameString(root)
            guard FileSearchScope.contains(rootPath, path) else { continue }
            var current = root
            for component in path.dropFirst(rootPath.count).split(separator: "/") {
                guard let child = child(named: component, in: children(of: current)) else {
                    return nil
                }
                current = child
            }
            return current
        }
        return nil
    }

    /// Folders are numbered in entry order, so a folder's number is the directories before it.
    private func folder(of index: Int) -> Int? {
        let word = index >> 6
        let bit: UInt64 = 1 << UInt64(index & 63)
        guard directoryBits[word] & bit != 0 else { return nil }
        return Int(directoryRank[word]) + (directoryBits[word] & (bit - 1)).nonzeroBitCount
    }

    /// Only block starts are stored, not a parent per entry.
    private func parent(of index: Int) -> Int {
        var low = 0
        var high = blockStart.count
        while low < high {
            let middle = (low + high) / 2
            if Int(blockStart[middle]) <= index { low = middle + 1 } else { high = middle }
        }
        return Int(blockOwner[low - 1])
    }

    private func child(named component: Substring, in range: Range<Int>) -> Int? {
        var component = component
        return component.withUTF8 { key in
            var low = range.lowerBound
            var high = range.upperBound
            while low < high {
                let middle = (low + high) / 2
                let order = FileIndexCrawler.compare(name(middle), key)
                if order == 0 { return middle }
                if order < 0 { low = middle + 1 } else { high = middle }
            }
            return nil
        }
    }

    private static func offsets(of sections: [(size: Int, count: Int)]) -> [Int] {
        var offsets = [Header.size]
        for section in sections {
            offsets.append((offsets[offsets.count - 1] + section.size * section.count + 7) & ~7)
        }
        return offsets
    }

    /// Block order: each folder's children are one sorted run, and a subtree is one range.
    static func write(
        _ crawl: [FileIndexCrawler.Listing], roots: [(path: String, prior: Int8)],
        eventID: UInt64, fingerprint: UInt64, to url: URL
    ) throws {
        var layout = Layout(capacity: roots.count + crawl.reduce(0) { $0 + $1.entries.count })
        layout.lay(crawl, roots: roots)
        try layout.write(eventID: eventID, fingerprint: fingerprint, to: url)
    }

    private struct Layout {
        var rootCount = 0
        var nameID: [UInt32] = []
        var mtime: [UInt32] = []
        var prior: [Int8] = []
        var directoryBits: [UInt64]
        var childStart: [UInt32] = []
        var childCount: [UInt32] = []
        var subtreeEnd: [UInt32] = []
        var blockStart: [UInt32] = []
        var blockOwner: [UInt32] = []
        var ids: [[UInt8]: UInt32] = [:]
        var nameEnd: [UInt32] = []
        var nameMask: [UInt64] = []
        var names: [UInt8] = []

        init(capacity: Int) {
            directoryBits = [UInt64](repeating: 0, count: (capacity + 63) / 64)
            nameID.reserveCapacity(capacity)
            mtime.reserveCapacity(capacity)
            prior.reserveCapacity(capacity)
        }

        @discardableResult
        mutating func append(
            _ name: UnsafeBufferPointer<UInt8>, isDirectory: Bool, mtime: UInt32, prior: Int8
        ) -> Int? {
            let slot = nameID.count
            nameID.append(intern(name))
            self.mtime.append(mtime)
            self.prior.append(prior)
            guard isDirectory else { return nil }
            directoryBits[slot >> 6] |= 1 << UInt64(slot & 63)
            childStart.append(0)
            childCount.append(0)
            subtreeEnd.append(0)
            return childStart.count - 1
        }

        private mutating func intern(_ name: UnsafeBufferPointer<UInt8>) -> UInt32 {
            let key = Array(name)
            if let id = ids[key] { return id }
            let id = UInt32(nameEnd.count)
            ids[key] = id
            names.append(contentsOf: name)
            nameEnd.append(UInt32(names.count))
            nameMask.append(FileSearchQuery.nameMask(name))
            return id
        }

        mutating func lay(_ crawl: [FileIndexCrawler.Listing], roots: [(path: String, prior: Int8)]) {
            var listings = crawl
            rootCount = roots.count
            for root in roots {
                var path = root.path
                _ = path.withUTF8 { append($0, isDirectory: true, mtime: 0, prior: root.prior) }
            }
            struct Frame {
                let folder: Int
                let start: Int
                let listing: Int
                let order: [Int]
                var cursor = 0
                var nextFolder: Int
            }
            var stack: [Frame] = []
            func openBlock(_ listingIndex: Int, folder: Int, owner: Int) {
                let listing = listings[listingIndex]
                let start = nameID.count
                let firstFolder = childStart.count
                let order = listing.names.withUnsafeBufferPointer { bytes in
                    func name(_ entry: FileIndexCrawler.Entry) -> UnsafeBufferPointer<UInt8> {
                        let start = Int(entry.nameStart)
                        return UnsafeBufferPointer(rebasing: bytes[start..<start + Int(entry.nameLength)])
                    }
                    let order = listing.entries.indices.sorted {
                        FileIndexCrawler.compare(name(listing.entries[$0]), name(listing.entries[$1])) < 0
                    }
                    for entry in order.lazy.map({ listing.entries[$0] }) {
                        append(
                            name(entry), isDirectory: entry.isDirectory, mtime: entry.mtime,
                            prior: entry.prior)
                    }
                    return order
                }
                childStart[folder] = UInt32(start)
                childCount[folder] = UInt32(order.count)
                if !order.isEmpty {
                    blockStart.append(UInt32(start))
                    blockOwner.append(UInt32(owner))
                }
                stack.append(
                    Frame(
                        folder: folder, start: start, listing: listingIndex, order: order,
                        nextFolder: firstFolder))
            }

            for root in roots.indices {
                openBlock(root, folder: root, owner: root)
                while let top = stack.indices.last {
                    let frame = stack[top]
                    guard frame.cursor < frame.order.count else {
                        subtreeEnd[frame.folder] = UInt32(nameID.count)
                        listings[frame.listing] = FileIndexCrawler.Listing()
                        stack.removeLast()
                        continue
                    }
                    stack[top].cursor += 1
                    let entry = listings[frame.listing].entries[frame.order[frame.cursor]]
                    guard entry.isDirectory else { continue }
                    stack[top].nextFolder += 1
                    if entry.child != FileIndexCrawler.none {
                        openBlock(
                            Int(entry.child), folder: frame.nextFolder,
                            owner: frame.start + frame.cursor)
                    }
                }
            }
        }

        func write(eventID: UInt64, fingerprint: UInt64, to url: URL) throws {
            var rank: UInt32 = 0
            let directoryRank = directoryBits.map { word in
                defer { rank += UInt32(word.nonzeroBitCount) }
                return rank
            }
            let partial = url.appendingPathExtension("partial")
            guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: partial)
            var written = 0
            func put(_ bytes: UnsafeRawBufferPointer) throws {
                try handle.write(contentsOf: bytes)
                written += bytes.count
                let padding = (8 - written % 8) % 8
                if padding > 0 { try handle.write(contentsOf: Data(count: padding)) }
                written += padding
            }
            var header = Header(
                rootCount: UInt32(rootCount), entryCount: UInt64(nameID.count),
                folderCount: UInt64(childStart.count),
                blockCount: UInt64(blockStart.count), nameCount: UInt64(nameEnd.count),
                namesLength: UInt64(names.count), eventID: eventID, fingerprint: fingerprint,
                builtAt: Date().timeIntervalSince1970)
            try withUnsafeBytes(of: &header) { try put($0) }
            try handle.write(contentsOf: Data(count: Header.size - written))
            written = Header.size
            try nameID.withUnsafeBytes(put)
            try mtime.withUnsafeBytes(put)
            try prior.withUnsafeBytes(put)
            try directoryBits.withUnsafeBytes(put)
            try directoryRank.withUnsafeBytes(put)
            try childStart.withUnsafeBytes(put)
            try childCount.withUnsafeBytes(put)
            try subtreeEnd.withUnsafeBytes(put)
            try blockStart.withUnsafeBytes(put)
            try blockOwner.withUnsafeBytes(put)
            try nameEnd.withUnsafeBytes(put)
            try nameMask.withUnsafeBytes(put)
            try names.withUnsafeBytes(put)
            try handle.close()
            guard rename(partial.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
    }
}
