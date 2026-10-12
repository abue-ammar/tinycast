import Darwin
import Foundation

/// Mapped read-only: clean file-backed pages, which never count as app memory.
final class FileIndexSnapshot: @unchecked Sendable {
    static let fileName = "index.bin"

    enum Flag {
        static let directory: UInt8 = 1
        static let root: UInt8 = 2
    }

    private struct Header {
        static let size = 64
        static let magic: UInt64 = 0x3130_5844_4946_4354
        static let version: UInt32 = 1

        var magic = Header.magic
        var version = Header.version
        var rootCount: UInt32
        var entryCount: UInt64
        var namesLength: UInt64
        var eventID: UInt64
        var fingerprint: UInt64
        var builtAt: Double
    }

    let rootCount: Int
    let entryCount: Int
    /// The FSEvents id from before the crawl began, so a replay from it misses nothing.
    let eventID: UInt64
    let fingerprint: UInt64
    let builtAt: Date
    let parent: UnsafeBufferPointer<UInt32>
    let mtime: UnsafeBufferPointer<UInt32>
    let mask: UnsafeBufferPointer<UInt64>
    let flags: UnsafeBufferPointer<UInt8>
    let prior: UnsafeBufferPointer<Int8>
    private let nameEnd: UnsafeBufferPointer<UInt32>
    private let childStart: UnsafeBufferPointer<UInt32>
    private let childCount: UnsafeBufferPointer<UInt32>
    private let subtreeEnd: UnsafeBufferPointer<UInt32>
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
        let layout = Self.layout(
            entries: Int(header.entryCount), namesLength: Int(header.namesLength))
        guard header.magic == Header.magic, header.version == Header.version,
            layout.size == size, header.rootCount > 0
        else {
            munmap(base, size)
            return nil
        }
        func section<T>(_ index: Int, _ count: Int) -> UnsafeBufferPointer<T> {
            UnsafeBufferPointer(
                start: (base + layout.offsets[index]).assumingMemoryBound(to: T.self), count: count)
        }
        let count = Int(header.entryCount)
        mapping = base
        mappedSize = size
        rootCount = Int(header.rootCount)
        entryCount = count
        eventID = header.eventID
        fingerprint = header.fingerprint
        builtAt = Date(timeIntervalSince1970: header.builtAt)
        nameEnd = section(0, count)
        parent = section(1, count)
        childStart = section(2, count)
        childCount = section(3, count)
        subtreeEnd = section(4, count)
        mtime = section(5, count)
        mask = section(6, count)
        flags = section(7, count)
        prior = section(8, count)
        names = section(9, Int(header.namesLength))
    }

    deinit {
        munmap(mapping, mappedSize)
    }

    func name(_ index: Int) -> UnsafeBufferPointer<UInt8> {
        let start = index == 0 ? 0 : Int(nameEnd[index - 1])
        return UnsafeBufferPointer(rebasing: names[start..<Int(nameEnd[index])])
    }

    func nameString(_ index: Int) -> String {
        String(decoding: name(index), as: UTF8.self)
    }

    func isDirectory(_ index: Int) -> Bool { flags[index] & Flag.directory != 0 }

    func children(of index: Int) -> Range<Int> {
        let start = Int(childStart[index])
        return start..<start + Int(childCount[index])
    }

    func subtree(of index: Int) -> Range<Int> {
        Int(childStart[index])..<max(Int(childStart[index]), Int(subtreeEnd[index]))
    }

    var roots: [String] { (0..<rootCount).map(nameString) }

    func path(of index: Int) -> String {
        var components: [String] = []
        var current = index
        while flags[current] & Flag.root == 0 {
            components.append(nameString(current))
            current = Int(parent[current])
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
                guard isDirectory(current),
                    let child = child(named: component, in: children(of: current))
                else { return nil }
                current = child
            }
            return current
        }
        return nil
    }

    private func child(named component: Substring, in range: Range<Int>) -> Int? {
        var component = component
        return component.withUTF8 { key in
            var low = range.lowerBound
            var high = range.upperBound
            while low < high {
                let middle = (low + high) / 2
                let order = Self.compare(name(middle), key)
                if order == 0 { return middle }
                if order < 0 { low = middle + 1 } else { high = middle }
            }
            return nil
        }
    }

    private static func compare(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>) -> Int {
        let shared = min(a.count, b.count)
        if shared > 0 {
            let order = memcmp(a.baseAddress!, b.baseAddress!, shared)
            if order != 0 { return Int(order) }
        }
        return a.count - b.count
    }

    private static func layout(entries: Int, namesLength: Int) -> (offsets: [Int], size: Int) {
        let sizes = [4, 4, 4, 4, 4, 4, 8, 1, 1].map { $0 * entries } + [namesLength]
        var offset = Header.size
        var offsets: [Int] = []
        for size in sizes {
            offsets.append(offset)
            offset = (offset + size + 7) & ~7
        }
        return (offsets, offset)
    }

    /// Block order: each folder's children are one sorted run, and a subtree is one range.
    static func write(
        _ crawl: [FileIndexCrawler.Listing], roots: [(path: String, prior: Int8)],
        eventID: UInt64, fingerprint: UInt64, to url: URL
    ) throws {
        var listings = crawl
        let count = roots.count + listings.reduce(0) { $0 + $1.entries.count }
        var nameEnd: [UInt32] = []
        var names: [UInt8] = []
        nameEnd.reserveCapacity(count)
        names.reserveCapacity(listings.reduce(0) { $0 + $1.names.count } + 4096)
        var parent = [UInt32](repeating: .max, count: count)
        var childStart = [UInt32](repeating: 0, count: count)
        var childCount = [UInt32](repeating: 0, count: count)
        var subtreeEnd = [UInt32](repeating: 0, count: count)
        var mtime = [UInt32](repeating: 0, count: count)
        var mask = [UInt64](repeating: 0, count: count)
        var flags = [UInt8](repeating: 0, count: count)
        var prior = [Int8](repeating: 0, count: count)

        for (index, root) in roots.enumerated() {
            names.append(contentsOf: root.path.utf8)
            nameEnd.append(UInt32(names.count))
            flags[index] = Flag.directory | Flag.root
            prior[index] = root.prior
        }

        struct Frame {
            let parent: Int
            let start: Int
            let listing: Int
            let order: [Int]
            var cursor = 0
        }
        var stack: [Frame] = []
        func emitBlock(_ listingIndex: Int, under owner: Int) {
            let listing = listings[listingIndex]
            let start = nameEnd.count
            let order = listing.names.withUnsafeBufferPointer { bytes in
                func name(_ entry: Int) -> UnsafeBufferPointer<UInt8> {
                    let entry = listing.entries[entry]
                    let start = Int(entry.nameStart)
                    return UnsafeBufferPointer(rebasing: bytes[start..<start + Int(entry.nameLength)])
                }
                let order = listing.entries.indices.sorted { compare(name($0), name($1)) < 0 }
                for (offset, entryIndex) in order.enumerated() {
                    let entry = listing.entries[entryIndex]
                    let slot = start + offset
                    let entryName = name(entryIndex)
                    names.append(contentsOf: entryName)
                    nameEnd.append(UInt32(names.count))
                    parent[slot] = UInt32(owner)
                    mtime[slot] = entry.mtime
                    mask[slot] = FileSearchQuery.nameMask(entryName)
                    flags[slot] = entry.isDirectory ? Flag.directory : 0
                    prior[slot] = entry.prior
                }
                return order
            }
            childStart[owner] = UInt32(start)
            childCount[owner] = UInt32(order.count)
            stack.append(Frame(parent: owner, start: start, listing: listingIndex, order: order))
        }

        for root in roots.indices {
            emitBlock(root, under: root)
            while let top = stack.indices.last {
                let frame = stack[top]
                guard frame.cursor < frame.order.count else {
                    subtreeEnd[frame.parent] = UInt32(nameEnd.count)
                    listings[frame.listing] = FileIndexCrawler.Listing()
                    stack.removeLast()
                    continue
                }
                stack[top].cursor += 1
                let entry = listings[frame.listing].entries[frame.order[frame.cursor]]
                if entry.child != FileIndexCrawler.none {
                    emitBlock(Int(entry.child), under: frame.start + frame.cursor)
                }
            }
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
            rootCount: UInt32(roots.count), entryCount: UInt64(count),
            namesLength: UInt64(names.count), eventID: eventID, fingerprint: fingerprint,
            builtAt: Date().timeIntervalSince1970)
        try withUnsafeBytes(of: &header) { try put($0) }
        try handle.write(contentsOf: Data(count: Header.size - written))
        written = Header.size
        try nameEnd.withUnsafeBytes(put)
        try parent.withUnsafeBytes(put)
        try childStart.withUnsafeBytes(put)
        try childCount.withUnsafeBytes(put)
        try subtreeEnd.withUnsafeBytes(put)
        try mtime.withUnsafeBytes(put)
        try mask.withUnsafeBytes(put)
        try flags.withUnsafeBytes(put)
        try prior.withUnsafeBytes(put)
        try names.withUnsafeBytes(put)
        try handle.close()
        guard rename(partial.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
