import Darwin
import Foundation

/// Every filesystem, stat and permission read; the decisions it defers to are the pure half.
enum UninstallScanner {
    struct SizeBudget: Sendable {
        /// Generous: an editor's support folder runs to ~90k entries. ~1s at 250k, off-main.
        var maxEntries = 250_000
        static let `default` = SizeBudget()
    }

    enum Failure: LocalizedError, Sendable {
        case refused

        var errorDescription: String? {
            switch self {
            case .refused:
                return "Tinycast can’t uninstall this app."
            }
        }
    }

    /// Every candidate with directory sizes still nil; fast enough that the list can paint on it.
    nonisolated static func discover(
        target: UninstallTarget, otherAppNames: [String], otherBundleIDs: [String],
        isTargetRunning: Bool, roots: [UninstallSearchRoot] = UninstallSearchRoot.all
    ) async throws -> UninstallPlan {
        try await Signposts.interval("UninstallScanner.discover") {
            let home = NSHomeDirectory()
            let environment = UninstallEnvironment(
                home: home, hasFullDiskAccess: detectFullDiskAccess(home: home))
            guard
                let identity = UninstallIdentity.make(
                    target: target, otherAppNames: otherAppNames, otherBundleIDs: otherBundleIDs,
                    ownBundleID: Bundle.main.bundleIdentifier, ownBundleURL: Bundle.main.bundleURL)
            else { throw Failure.refused }

            let bundlePath = target.bundleURL.standardizedFileURL.path
            let bundle = row(
                path: bundlePath, evidence: .bundle, environment: environment,
                displayName: target.bundleURL.deletingPathExtension().lastPathComponent)

            var buckets = [[UninstallCandidate]](repeating: [], count: roots.count)
            try await withThrowingTaskGroup(of: (Int, [UninstallCandidate]).self) { group in
                for (index, root) in roots.enumerated() {
                    group.addTask {
                        try Task.checkCancellation()
                        return (
                            index,
                            rows(
                                in: root, identity: identity, environment: environment,
                                bundlePath: bundlePath)
                        )
                    }
                }
                // At its own index, so `UninstallSearchRoot.all` order outlives completion order.
                for try await (index, found) in group { buckets[index] = found }
            }

            let gathered =
                [bundle].compactMap { $0 } + buckets.flatMap { $0 }
                + (try binRows(environment: environment, bundlePath: bundlePath))

            // One pass, in gathered order: a `Set` shared across tasks is what would race.
            var seen = Set<String>()
            let candidates = gathered.filter { seen.insert($0.path).inserted }

            // Bundle pinned first; the rest by path, which is the order the list shows.
            let leftovers = candidates.filter { $0.evidence != .bundle }.sorted { $0.path < $1.path }
            return UninstallPlan(
                target: target, candidates: candidates.filter { $0.evidence == .bundle } + leftovers,
                isTargetRunning: isTargetRunning)
        }
    }

    /// Streams each walk as it lands, so a row never waits on its neighbours; nil means unmeasured.
    nonisolated static func measure(
        paths: [String], budget: SizeBudget = .default,
        onMeasured: @escaping @Sendable @MainActor (String, MeasuredSize) -> Void
    ) async {
        await Signposts.interval("UninstallScanner.measure") {
            await withTaskGroup(of: (String, MeasuredSize)?.self) { group in
                for path in paths {
                    group.addTask {
                        guard let size = try? directorySize(of: path, budget: budget) else {
                            return nil
                        }
                        return (path, size)
                    }
                }
                // A cancelled or unreadable walk yields nothing, so its row stays pending.
                for await measured in group {
                    guard let (path, size) = measured else { continue }
                    await onMeasured(path, size)
                }
            }
        }
    }

    // MARK: - Private

    private static func rows(
        in root: UninstallSearchRoot, identity: UninstallIdentity,
        environment: UninstallEnvironment, bundlePath: String
    ) -> [UninstallCandidate] {
        let rootPath = root.path(home: environment.home)
        guard let names = childNames(of: rootPath) else { return [] }
        // One stat per root, not per row.
        let parent = parentFacts(of: rootPath)
        return UninstallRules.matches(childNames: names, in: root, identity: identity)
            .compactMap { match -> UninstallCandidate? in
                let path = (rootPath + "/" + match.name as NSString).standardizingPath
                guard
                    UninstallRules.isAcceptableCandidate(
                        path: path, rootPath: rootPath, home: environment.home,
                        bundlePath: bundlePath)
                else { return nil }
                return row(
                    path: path, evidence: match.evidence, environment: environment, parent: parent)
            }
    }

    /// Serial: four directories of cheap symlink reads, and nothing here needs a walk.
    private static func binRows(
        environment: UninstallEnvironment, bundlePath: String
    ) throws
        -> [UninstallCandidate]
    {
        var rows: [UninstallCandidate] = []
        for directory in UninstallSearchRoot.binDirectories {
            try Task.checkCancellation()
            let rootPath = (directory as NSString).expandingTildeInPath
            guard let names = childNames(of: rootPath) else { continue }
            let parent = parentFacts(of: rootPath)
            for name in names {
                let path = (rootPath + "/" + name as NSString).standardizingPath
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
                else { continue }
                // A relative link resolves against its own directory, not the cwd.
                let resolved =
                    target.hasPrefix("/")
                    ? target : (rootPath as NSString).appendingPathComponent(target)
                guard UninstallRules.isBundleSymlink(target: resolved, bundlePath: bundlePath),
                    let row = row(
                        path: path, evidence: .binSymlink, environment: environment, parent: parent)
                else { continue }
                rows.append(row)
            }
        }
        return rows
    }

    private static func childNames(of directory: String) -> [String]? {
        // Not `.skipsHiddenFiles`: dot-named leftovers are the ones a user would never find.
        try? FileManager.default.contentsOfDirectory(atPath: directory)
    }

    private static func row(
        path: String, evidence: UninstallEvidence, environment: UninstallEnvironment,
        displayName: String? = nil, parent: ParentFacts? = nil
    ) -> UninstallCandidate? {
        guard let scanned = inspect(path, parent: parent) else { return nil }
        let protection = UninstallProtectionRules.classify(scanned.facts, environment: environment)
        guard protection != .missing else { return nil }
        // A symlink is trashed as the link, so it never costs more than its own bytes.
        let walkable = scanned.isDirectory && !scanned.facts.isSymbolicLink
        return UninstallCandidate(
            path: path,
            name: displayName ?? (path as NSString).lastPathComponent,
            locationLabel: UninstallRules.abbreviate(
                (path as NSString).deletingLastPathComponent, home: environment.home),
            evidence: evidence,
            isDirectory: scanned.isDirectory,
            size: walkable ? nil : MeasuredSize(bytes: scanned.byteSize),
            protection: protection)
    }

    /// `lstat`, never `stat`: a symlink is judged as the link, not as whatever it points at.
    private static func inspect(
        _ path: String, parent: ParentFacts?
    )
        -> (facts: PathFacts, isDirectory: Bool, byteSize: Int64)?
    {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let parent = parent ?? parentFacts(of: (path as NSString).deletingLastPathComponent)
        let volumeIsReadOnly =
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsReadOnlyKey]))?
            .volumeIsReadOnly ?? false
        let facts = PathFacts(
            path: path,
            isSymbolicLink: (info.st_mode & S_IFMT) == S_IFLNK,
            volumeIsReadOnly: volumeIsReadOnly,
            isSystemRestricted: info.st_flags & UInt32(SF_RESTRICTED | SF_IMMUTABLE) != 0,
            isUserImmutable: info.st_flags & UInt32(UF_IMMUTABLE) != 0,
            isOwnedByCurrentUser: info.st_uid == geteuid(),
            parentIsWritable: parent.isWritable,
            parentIsSticky: parent.isSticky)
        // `st_size`, not `st_blocks`: a 593-byte plist occupies a block and must not read as 4 kB.
        return (facts, (info.st_mode & S_IFMT) == S_IFDIR, Int64(info.st_size))
    }

    /// The permission that actually governs a trash, resolved once per root.
    private static func parentFacts(of directory: String) -> ParentFacts {
        var info = stat()
        let sticky = stat(directory, &info) == 0 && (info.st_mode & S_ISVTX) != 0
        return ParentFacts(
            isWritable: FileManager.default.isWritableFile(atPath: directory), isSticky: sticky)
    }

    private struct ParentFacts {
        let isWritable: Bool
        let isSticky: Bool
    }

    /// Logical bytes, like Finder; an unreadable subtree is skipped, not abandoned.
    private static func directorySize(of path: String, budget: SizeBudget) throws -> MeasuredSize {
        let url = URL(fileURLWithPath: path)
        // Not the allocated keys: Xcode ships decmpfs-compressed, and blocks read 4.19 GB of 9.45.
        let keys: [URLResourceKey] = [.totalFileSizeKey, .fileSizeKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [],
                errorHandler: { _, _ in true })
        else { return .zero }

        // Hoisted: the loop runs up to `maxEntries` times, and this allocated a `Set` on each one.
        let keySet = Set(keys)
        var size = MeasuredSize()
        var entries = 0
        for case let item as URL in enumerator {
            // The long pole: cancellation has to land inside the walk, not just between walks.
            try Task.checkCancellation()
            entries += 1
            if entries > budget.maxEntries {
                size.isLowerBound = true
                break
            }
            let values = try? item.resourceValues(forKeys: keySet)
            size.bytes += Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
        }
        return size
    }

    /// Detected, never requested: TCC denies silently, and under-reporting only locks a row.
    private static func detectFullDiskAccess(home: String) -> Bool {
        let descriptor = open(home + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
