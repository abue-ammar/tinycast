import Foundation

/// Names a spawned interpreter for Activity Monitor, which shows `p_comm`: the basename of the
/// file the kernel exec'd, and only a hard link changes it.
enum ProcessBadge {
    /// `p_comm` is `MAXCOMLEN` bytes, and a truncated badge reads worse than none at all.
    static let nameLimit = 16

    /// The link, or the executable untouched when none can be made: a badge is never worth a throw.
    static func badged(_ executable: URL, in root: URL? = nil) -> URL {
        let target = executable.resolvingSymlinksInPath()
        // A shebang script re-execs its interpreter, which overwrites the badge with `node`.
        guard !isScript(target) else { return executable }
        // dyld reads `@executable_path` from where it exec'd, so such a binary keeps its path.
        guard !dependsOnItsOwnPath(target) else { return executable }
        let name = badgeName(for: executable)
        guard name.utf8.count <= nameLimit, let root = root ?? defaultRoot()
        else { return executable }
        // Keyed by target: two interpreters sharing a basename must not share one link.
        let directory = root.appendingPathComponent(digest(target.path))
        guard (try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)) != nil
        else { return executable }

        let link = directory.appendingPathComponent(name)
        // An upgrade in place moves the inode, so a stale link would exec what it replaced.
        if sharesInode(link, target) { return link }
        // Hard links can't cross volumes, and the sealed system volume refuses them outright.
        let staging = directory.appendingPathComponent("\(name).\(UUID().uuidString)")
        guard (try? FileManager.default.linkItem(at: target, to: staging)) != nil else {
            return executable
        }
        // Renamed over, never removed first: a concurrent caller must not meet a missing path.
        guard rename(staging.path, link.path) == 0 else {
            try? FileManager.default.removeItem(at: staging)
            return executable
        }
        return link
    }

    /// Named for the command as invoked: `grok` resolves to a release filename nothing would fit.
    static func badgeName(for executable: URL) -> String {
        "Tinycast (\(executable.lastPathComponent))"
    }

    static func isScript(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data("#!".utf8)
    }

    /// FNV-1a rather than `hashValue`, which is seeded per launch: the link outlives the process.
    static func digest(_ path: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// True for anything not provably safe: unreadable, a shape this doesn't parse, or a load
    /// command naming `@executable_path`, all of which must keep the path they were installed at.
    static func dependsOnItsOwnPath(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
            let magic = try? handle.read(upToCount: 4), magic.count == 4
        else { return true }
        defer { try? handle.close() }
        switch Array(magic) {
        case [0xcf, 0xfa, 0xed, 0xfe]: return sliceNeedsItsPath(handle, at: 0)
        case [0xca, 0xfe, 0xba, 0xbe]: return fatNeedsItsPath(handle)
        default: return true
        }
    }

    /// Every slice is inspected: one that needs its own path is enough to leave the binary alone.
    private static func fatNeedsItsPath(_ handle: FileHandle) -> Bool {
        guard let count = try? handle.read(upToCount: 4).map({ bigEndian($0) }) ?? nil,
            count > 0, count <= 16
        else { return true }
        var offsets: [UInt32] = []
        for index in 0..<count {
            try? handle.seek(toOffset: UInt64(8 + index * 20 + 8))
            guard let offset = try? handle.read(upToCount: 4).map({ bigEndian($0) }) ?? nil
            else { return true }
            offsets.append(offset)
        }
        return offsets.contains { sliceNeedsItsPath(handle, at: UInt64($0)) }
    }

    private static func sliceNeedsItsPath(_ handle: FileHandle, at offset: UInt64) -> Bool {
        try? handle.seek(toOffset: offset)
        guard let header = try? handle.read(upToCount: 32), header.count == 32,
            Array(header.prefix(4)) == [0xcf, 0xfa, 0xed, 0xfe],
            let size = littleEndian(header[(header.startIndex + 20)..<(header.startIndex + 24)]),
            size > 0, size < 1 << 20,
            let commands = try? handle.read(upToCount: Int(size))
        else { return true }
        return commands.range(of: Data("@executable_path".utf8)) != nil
            || commands.range(of: Data("@loader_path".utf8)) != nil
    }

    private static func bigEndian(_ data: Data) -> UInt32? {
        guard data.count == 4 else { return nil }
        return data.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func littleEndian(_ data: Data) -> UInt32? {
        guard data.count == 4 else { return nil }
        return data.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func defaultRoot() -> URL? {
        AppPaths.applicationSupport().appendingPathComponent("Processes")
    }

    private static func sharesInode(_ link: URL, _ target: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let a = try? link.resourceValues(forKeys: keys).fileResourceIdentifier,
            let b = try? target.resourceValues(forKeys: keys).fileResourceIdentifier
        else { return false }
        return a.isEqual(b)
    }
}
