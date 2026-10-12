import Darwin
import Foundation

/// One `getattrlistbulk` call lists hundreds of entries with their mtime, so nothing is stat'd.
nonisolated enum FileIndexCrawler {
    static let none = UInt32.max

    struct Entry: Sendable {
        var nameStart: UInt32
        var nameLength: UInt16
        var isDirectory: Bool
        var prior: Int8
        var mtime: UInt32
        var child: UInt32
    }

    struct Listing: Sendable {
        var names: [UInt8] = []
        var entries: [Entry] = []

        func name(of entry: Entry) -> String {
            let start = Int(entry.nameStart)
            return String(decoding: names[start..<start + Int(entry.nameLength)], as: UTF8.self)
        }
    }

    struct Child: Sendable, Equatable {
        let name: String
        let isDirectory: Bool
        let mtime: UInt32
        let prior: Int8

        /// A folder's prior comes from its path; a file's was set by its listing.
        init(_ entry: Entry, name: String, parent: String, policy: FileSearchPolicy) {
            self.name = name
            isDirectory = entry.isDirectory
            mtime = entry.mtime
            prior = entry.isDirectory ? policy.prior(of: FileIndexCrawler.path(parent, name)) : entry.prior
        }
    }

    private static let bufferSize = 256 * 1024

    /// Real paths, since that is how FSEvents reports them.
    static func roots(of policy: FileSearchPolicy) -> [(path: String, prior: Int8)] {
        policy.roots.compactMap { root in
            guard let resolved = realpath(root, nil) else { return nil }
            defer { free(resolved) }
            let path = String(cString: resolved)
            return (path, policy.prior(of: path))
        }
    }

    static func path(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }

    static func compare(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>) -> Int {
        let shared = min(a.count, b.count)
        if shared > 0 {
            let order = memcmp(a.baseAddress!, b.baseAddress!, shared)
            if order != 0 { return Int(order) }
        }
        return a.count - b.count
    }

    /// Kept across live updates, so relisting a folder that did not change allocates nothing.
    final class Lister {
        private let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64 * 1024, alignment: 8)
        private var listing = Listing()
        private var order: [Int] = []

        deinit {
            buffer.deallocate()
        }

        /// Hands `body` the entries sorted by name bytes, or returns nil when the folder won't open.
        func list<T>(
            _ path: String, prior: Int8, policy: FileSearchPolicy,
            _ body: (_ entries: [Entry], _ order: [Int], _ name: (Entry) -> UnsafeBufferPointer<UInt8>) -> T
        ) -> T? {
            listing.names.removeAll(keepingCapacity: true)
            listing.entries.removeAll(keepingCapacity: true)
            let listed = FileIndexCrawler.withoutMaterializing {
                FileIndexCrawler.list(path, prior: prior, policy: policy, buffer: buffer, into: &listing)
            }
            guard listed else { return nil }
            // A huge folder's storage is not kept for the small ones that follow.
            defer {
                if listing.entries.capacity > 4_096 {
                    listing = Listing()
                    order = []
                }
            }
            return listing.names.withUnsafeBufferPointer { bytes in
                func name(_ entry: Entry) -> UnsafeBufferPointer<UInt8> {
                    let start = Int(entry.nameStart)
                    return UnsafeBufferPointer(rebasing: bytes[start..<start + Int(entry.nameLength)])
                }
                order.removeAll(keepingCapacity: true)
                order.append(contentsOf: listing.entries.indices)
                order.sort {
                    FileIndexCrawler.compare(name(listing.entries[$0]), name(listing.entries[$1])) < 0
                }
                return body(listing.entries, order, name)
            }
        }

        func walk(_ root: String, prior: Int8, policy: FileSearchPolicy) -> [(String, Child)] {
            var found: [(String, Child)] = []
            var pending = [(root, prior)]
            while let (folder, prior) = pending.popLast() {
                list(folder, prior: prior, policy: policy) { entries, _, name in
                    for entry in entries {
                        let child = Child(
                            entry, name: String(decoding: name(entry), as: UTF8.self), parent: folder,
                            policy: policy)
                        let childPath = FileIndexCrawler.path(folder, child.name)
                        found.append((childPath, child))
                        if child.isDirectory { pending.append((childPath, child.prior)) }
                    }
                }
            }
            return found
        }
    }

    private static func withBuffer<T>(_ body: (UnsafeMutableRawBufferPointer) -> T) -> T {
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        return withoutMaterializing { body(buffer) }
    }

    /// Per thread, and restored after: a crawl must never download what it lists.
    private static func withoutMaterializing<T>(_ body: () -> T) -> T {
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let previous = getiopolicy_np(type, IOPOL_SCOPE_THREAD)
        setiopolicy_np(type, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer { if previous >= 0 { setiopolicy_np(type, IOPOL_SCOPE_THREAD, previous) } }
        return body()
    }

    private static let request: attrlist = {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr =
            attrgroup_t(truncatingIfNeeded: ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_NAME)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_ERROR)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_OBJTYPE)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_MODTIME)
        request.dirattr = attrgroup_t(truncatingIfNeeded: ATTR_DIR_MOUNTSTATUS)
        return request
    }()

    private static func list(
        _ path: String, prior: Int8, policy: FileSearchPolicy,
        buffer: UnsafeMutableRawBufferPointer, into listing: inout Listing
    ) -> Bool {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var request = request
        while true {
            let count = getattrlistbulk(descriptor, &request, buffer.baseAddress!, buffer.count, 0)
            guard count > 0 else { break }
            var record = UnsafeRawPointer(buffer.baseAddress!)
            for _ in 0..<count {
                append(record, folder: path, prior: prior, policy: policy, to: &listing)
                record += Int(record.loadUnaligned(as: UInt32.self))
            }
        }
        return true
    }

    private static func append(
        _ record: UnsafeRawPointer, folder: String, prior: Int8, policy: FileSearchPolicy,
        to listing: inout Listing
    ) {
        let returned = record.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
        var field = record + 4 + MemoryLayout<attribute_set_t>.size
        if returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_ERROR) != 0 {
            field += MemoryLayout<UInt32>.size
        }
        guard returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_NAME) != 0 else {
            return
        }
        let reference = field.loadUnaligned(as: attrreference_t.self)
        let name = (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
        let length = Int(reference.attr_length) - 1
        field += MemoryLayout<attrreference_t>.size
        var type: UInt32 = 0
        if returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_OBJTYPE) != 0 {
            type = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        var mtime = 0
        if returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_MODTIME) != 0 {
            mtime = field.loadUnaligned(as: timespec.self).tv_sec
            field += MemoryLayout<timespec>.size
        }
        // Not entered: `/System/Volumes/Data` would list every firmlinked file a second time.
        if returned.dirattr & attrgroup_t(truncatingIfNeeded: ATTR_DIR_MOUNTSTATUS) != 0 {
            let status = field.loadUnaligned(as: UInt32.self)
            if status & UInt32(DIR_MNTSTATUS_MNTPOINT | DIR_MNTSTATUS_TRIGGER) != 0 { return }
        }
        guard length > 0, length <= Int(UInt16.max),
            !policy.ignore.excludes(
                name: name, length: length,
                path: {
                    Self.path(folder, String(cString: name))
                })
        else { return }

        let isDirectory = type == VDIR.rawValue
        let isHidden = name.pointee == 0x2E
        listing.entries.append(
            Entry(
                nameStart: UInt32(listing.names.count), nameLength: UInt16(length),
                isDirectory: isDirectory, prior: isHidden ? 0 : prior,
                mtime: UInt32(clamping: mtime), child: none))
        listing.names.append(contentsOf: UnsafeRawBufferPointer(start: name, count: length))
    }

    final class Crawl: @unchecked Sendable {
        private let policy: FileSearchPolicy
        private let condition = NSCondition()
        private var pending: [(id: UInt32, path: String, prior: Int8)]
        private var finished: [(id: UInt32, listing: Listing)] = []
        private var busy = 0
        private var nextID: UInt32
        private var listedCount = 0

        /// Listing `i` for `i < roots.count` is root `i`.
        init(roots: [(path: String, prior: Int8)], policy: FileSearchPolicy) {
            self.policy = policy
            pending = roots.enumerated().reversed().map { index, root in
                (UInt32(index), root.path, root.prior)
            }
            nextID = UInt32(roots.count)
        }

        var listed: Int { condition.withLock { listedCount } }

        func run(workers: Int) -> [Listing] {
            DispatchQueue.concurrentPerform(iterations: max(1, workers)) { _ in
                FileIndexCrawler.withBuffer { work($0) }
            }
            var listings = [Listing](repeating: Listing(), count: Int(nextID))
            for (id, listing) in finished { listings[Int(id)] = listing }
            finished = []
            return listings
        }

        private func work(_ buffer: UnsafeMutableRawBufferPointer) {
            condition.lock()
            while true {
                while pending.isEmpty && busy > 0 { condition.wait() }
                guard let folder = pending.popLast() else { break }
                busy += 1
                condition.unlock()

                var listing = Listing()
                _ = FileIndexCrawler.list(
                    folder.path, prior: folder.prior, policy: policy, buffer: buffer,
                    into: &listing)
                var folders: [(index: Int, path: String)] = []
                for index in listing.entries.indices where listing.entries[index].isDirectory {
                    let path = FileIndexCrawler.path(
                        folder.path, listing.name(of: listing.entries[index]))
                    listing.entries[index].prior = policy.prior(of: path)
                    folders.append((index, path))
                }

                condition.lock()
                for (index, path) in folders {
                    listing.entries[index].child = nextID
                    pending.append((nextID, path, listing.entries[index].prior))
                    nextID += 1
                }
                listedCount += listing.entries.count
                finished.append((folder.id, listing))
                busy -= 1
                if !folders.isEmpty || busy == 0 { condition.broadcast() }
            }
            condition.broadcast()
            condition.unlock()
        }
    }
}
