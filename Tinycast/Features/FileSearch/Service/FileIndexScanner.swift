import Darwin
import Foundation
import UniformTypeIdentifiers

/// The disk half of the index: one `getattrlistbulk` call lists a folder with every fact it needs.
enum FileIndexScanner {
    /// The memory budget's share: about 12 bytes an entry plus its slice of the interned names.
    static let entryLimit = 1_000_000

    /// A policy resolved against the disk, once per change of settings rather than per walk.
    struct Plan: Sendable, Equatable {
        let roots: [String]
        /// Where `Library` is left out: home's own folder and nowhere else.
        let homePath: String?
        let ignore: FileSearchIgnoreList
        let entryLimit: Int
    }

    struct Change: Sendable, Equatable {
        let path: String
        /// FSEvents lost the detail below `path`, so its whole subtree is listed again.
        let isRecursive: Bool
    }

    enum Outcome: Sendable, Equatable {
        case applied
        /// History was lost above a root: nothing short of a full walk is right.
        case needsRebuild
    }

    nonisolated static func plan(
        for policy: FileSearchPolicy, entryLimit: Int = FileIndexScanner.entryLimit
    ) -> Plan {
        var roots = policy.directRoots
        var homePath: String?
        if policy.includesHome {
            let home = policy.homeDirectory
            roots.append(home)
            homePath = realPath(home)
            for cloud in ["Library/CloudStorage", "Library/Mobile Documents/com~apple~CloudDocs"] {
                roots.append(home.appending(path: cloud, directoryHint: .isDirectory))
            }
        }
        var seen = Set<String>()
        let resolved = roots.compactMap(realPath).filter { seen.insert($0).inserted }
        return Plan(roots: resolved, homePath: homePath, ignore: policy.ignore, entryLimit: entryLimit)
    }

    nonisolated static func build(_ plan: Plan) -> FileNameIndex {
        Signposts.interval("FileIndexScanner.build") {
            var walker = Walker(plan: plan, index: FileNameIndex())
            defer { walker.close() }
            withoutMaterializing {
                for root in plan.roots {
                    let directory = walker.index.addRoot(path: root)
                    walker.walk(path: root, directory: directory, keeping: [:])
                }
            }
            return walker.index
        }
    }

    /// Brings each changed folder in line with the disk; an event outside the index changes nothing.
    nonisolated static func refresh(
        _ index: inout FileNameIndex, changes: [Change], plan: Plan
    ) -> Outcome {
        Signposts.interval("FileIndexScanner.refresh") {
            var walker = Walker(plan: plan, index: index)
            defer { walker.close() }
            let outcome = withoutMaterializing { () -> Outcome in
                for change in changes {
                    guard let directory = walker.index.directory(atPath: change.path) else {
                        if change.isRecursive && isAboveRoot(change.path, plan: plan) {
                            return .needsRebuild
                        }
                        continue
                    }
                    var keeping: [UInt32: Int32] = [:]
                    if change.isRecursive {
                        walker.index.replaceEntries(of: directory, with: [])
                    } else {
                        for entry in walker.index.entries(of: directory) {
                            if let child = entry.directory { keeping[entry.name] = child }
                        }
                    }
                    walker.walk(path: change.path, directory: directory, keeping: keeping)
                }
                return .applied
            }
            walker.index.compactNamesIfNeeded()
            index = walker.index
            return outcome
        }
    }

    nonisolated static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private nonisolated static func isAboveRoot(_ path: String, plan: Plan) -> Bool {
        let prefix = path == "/" ? "/" : path + "/"
        return plan.roots.contains { $0 == path || $0.hasPrefix(prefix) }
    }

    /// An iCloud placeholder has to stay one: listing it as a folder would download it.
    private nonisolated static func withoutMaterializing<T>(_ body: () -> T) -> T {
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        setiopolicy_np(
            IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
            IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer {
            if previous >= 0 {
                setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous)
            }
        }
        return body()
    }
}

/// One walk's state: the index it writes, a reused listing buffer and the package memo.
private struct Walker {
    var index: FileNameIndex
    private let plan: FileIndexScanner.Plan
    private let homePath: [UInt8]?
    private let roots: Set<[UInt8]>
    private let buffer: UnsafeMutableRawBufferPointer
    private var packageExtensions: [String: Bool] = [:]

    private static let bufferSize = 256 * 1024
    private static let openFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    private struct Child {
        let name: Range<Int>
        let kind: FileNameIndex.Kind
        let modified: UInt32
        let descends: Bool
    }

    private struct Pending {
        let name: [UInt8]
        let directory: Int32
    }

    init(plan: FileIndexScanner.Plan, index: FileNameIndex) {
        self.plan = plan
        self.index = index
        homePath = plan.homePath.map { Array($0.utf8) }
        roots = Set(plan.roots.map { Array($0.utf8) })
        buffer = .allocate(byteCount: Self.bufferSize, alignment: 8)
    }

    func close() { buffer.deallocate() }

    /// Lists `path` into `directory`; a folder named in `keeping` keeps its id and is not re-walked.
    mutating func walk(path: String, directory: Int32, keeping: [UInt32: Int32]) {
        let descriptor = open(path, Self.openFlags)
        guard descriptor >= 0 else {
            index.replaceEntries(of: directory, with: [])
            return
        }
        walk(descriptor: descriptor, path: Array(path.utf8), directory: directory, keeping: keeping)
    }

    private mutating func walk(
        descriptor: Int32, path: [UInt8], directory: Int32, keeping: [UInt32: Int32]
    ) {
        defer { Darwin.close(descriptor) }
        let (names, children) = list(descriptor, path: path)
        let room = plan.entryLimit - index.entryCount + index.entries(of: directory).count
        var entries = ContiguousArray<FileNameIndex.Entry>()
        var pending: [Pending] = []
        for child in children.prefix(max(0, room)) {
            let id = names.withUnsafeBufferPointer {
                index.intern(FileNameIndex.Bytes(rebasing: $0[child.name]))
            }
            guard child.descends else {
                entries.append(FileNameIndex.Entry(name: id, modified: child.modified, kind: child.kind))
                continue
            }
            let target = keeping[id] ?? index.addDirectory(name: id, parent: directory)
            if keeping[id] == nil {
                pending.append(Pending(name: Array(names[child.name]), directory: target))
            }
            entries.append(
                FileNameIndex.Entry(name: id, modified: child.modified, kind: .folder, directory: target))
        }
        index.replaceEntries(of: directory, with: entries)
        for child in pending {
            guard index.entryCount < plan.entryLimit else { break }
            let opened = (child.name + [0]).withUnsafeBufferPointer { name in
                name.withMemoryRebound(to: CChar.self) {
                    openat(descriptor, $0.baseAddress!, Self.openFlags)
                }
            }
            guard opened >= 0 else { continue }
            walk(
                descriptor: opened, path: path + [0x2F] + child.name, directory: child.directory,
                keeping: [:])
        }
    }

    /// Every child the policy admits, already classified: what is left out is never opened.
    private mutating func list(_ descriptor: Int32, path: [UInt8]) -> ([UInt8], [Child]) {
        let isHome = path == homePath
        var names: [UInt8] = []
        var children: [Child] = []
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr =
            attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FLAGS)
        attributes.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        while true {
            let count = getattrlistbulk(descriptor, &attributes, buffer.baseAddress, Self.bufferSize, 0)
            guard count > 0 else { break }
            var offset = 0
            for _ in 0..<count {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                if let record = Record(buffer, at: offset),
                    let (kind, descends) = admit(record, path: path, isHome: isHome)
                {
                    let start = names.count
                    names.append(contentsOf: record.name)
                    children.append(Child(
                        name: start..<names.count, kind: kind, modified: record.modified,
                        descends: descends))
                }
                offset += length
            }
        }
        return (names, children)
    }

    /// Hidden names, apps, `~/Library` and ignored names are structural: nothing re-admits them.
    private mutating func admit(
        _ record: Record, path: [UInt8], isHome: Bool
    ) -> (FileNameIndex.Kind, Bool)? {
        let name = record.name
        guard name.first != 0x2E, record.flags & UInt32(UF_HIDDEN) == 0 else { return nil }
        let text = String(decoding: name, as: UTF8.self)
        let lowered = text.lowercased()
        guard !lowered.hasSuffix(".app"), !(isHome && lowered == "library"),
            !plan.ignore.excludes(name: text)
        else { return nil }
        if plan.ignore.hasPathPatterns,
            plan.ignore.excludesWhole(path: String(decoding: path, as: UTF8.self) + "/" + text)
        {
            return nil
        }
        switch record.objectType {
        case UInt32(VREG.rawValue): return (.file, false)
        case UInt32(VLNK.rawValue): return (.link, false)
        case UInt32(VDIR.rawValue):
            let kind = folderKind(lowered)
            guard kind == .folder else { return (kind, false) }
            let isAnotherRoot = roots.contains(path + [0x2F] + Array(name))
            return (.folder, !record.isMount && !isAnotherRoot)
        default: return nil
        }
    }

    /// A package is one item to the user, so its contents are never walked.
    private mutating func folderKind(_ loweredName: String) -> FileNameIndex.Kind {
        guard let dot = loweredName.lastIndex(of: "."), dot != loweredName.startIndex else {
            return .folder
        }
        let pathExtension = String(loweredName[loweredName.index(after: dot)...])
        if let known = packageExtensions[pathExtension] { return known ? .package : .folder }
        let type = UTType(filenameExtension: pathExtension, conformingTo: .directory)
        let isPackage = type?.conforms(to: .package) == true
        packageExtensions[pathExtension] = isPackage
        return isPackage ? .package : .folder
    }
}

/// One `getattrlistbulk` record, read in the order the kernel packs the attributes asked for.
private struct Record {
    let name: FileNameIndex.Bytes
    let objectType: UInt32
    let modified: UInt32
    let flags: UInt32
    let isMount: Bool

    init?(_ buffer: UnsafeMutableRawBufferPointer, at start: Int) {
        func word(_ offset: Int) -> UInt32 {
            buffer.loadUnaligned(fromByteOffset: start + offset, as: UInt32.self)
        }
        let common = word(4)
        let directory = word(12)
        var field = 24
        if common & attrgroup_t(ATTR_CMN_ERROR) != 0 { field += 4 }
        guard common & attrgroup_t(ATTR_CMN_NAME) != 0 else { return nil }
        let nameOffset = Int(Int32(bitPattern: word(field)))
        let nameLength = Int(word(field + 4))
        guard nameLength > 1 else { return nil }
        name = FileNameIndex.Bytes(
            start: buffer.baseAddress!.advanced(by: start + field + nameOffset)
                .assumingMemoryBound(to: UInt8.self),
            count: nameLength - 1)
        field += 8
        var objectType: UInt32 = 0
        if common & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            objectType = word(field)
            field += 4
        }
        var modified: UInt32 = 0
        if common & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            let seconds = buffer.loadUnaligned(fromByteOffset: start + field, as: Int64.self)
            modified = UInt32(clamping: max(0, seconds))
            field += 16
        }
        var flags: UInt32 = 0
        if common & attrgroup_t(ATTR_CMN_FLAGS) != 0 {
            flags = word(field)
            field += 4
        }
        var isMount = false
        if directory & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 {
            isMount = word(field) & UInt32(DIR_MNTSTATUS_MNTPOINT | DIR_MNTSTATUS_TRIGGER) != 0
        }
        self.objectType = objectType
        self.modified = modified
        self.flags = flags
        self.isMount = isMount
    }
}
