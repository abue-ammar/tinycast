import Foundation

/// Reclaims a stranded build workspace and the storage of an extension no longer installed.
/// It names the workspace too, so creating one and sweeping for one can't disagree.
enum ExtensionCleanup {
    /// Injected, never read from `Bundle.main`: a harness would otherwise delete the real install.
    struct Roots: Sendable {
        var temp: URL
        var support: URL
        var data: URL
    }

    struct Report: Sendable, Equatable {
        var items = 0
        var bytes: Int64 = 0

        var isEmpty: Bool { items == 0 }
    }

    /// A build's scratch directory. Unique per install, so two can run without colliding.
    static func workspace(in temp: URL) -> URL {
        temp.appendingPathComponent(workspacePrefix + UUID().uuidString, isDirectory: true)
    }

    nonisolated static func defaultRoots() -> Roots {
        Roots(
            temp: FileManager.default.temporaryDirectory,
            support: ExtensionCatalog.supportRoot(),
            data: ExtensionCatalog.storageDirectory())
    }

    /// What `clean` would remove, so a button can say so before it is pressed.
    nonisolated static func reclaimable(installed: Set<String>, in roots: Roots) -> Report {
        var report = Report()
        for url in strays(installed: installed, in: roots) {
            report.items += 1
            report.bytes += size(of: url)
        }
        return report
    }

    /// A failed delete is skipped, not counted, so the total never claims space it didn't free.
    @discardableResult
    nonisolated static func clean(installed: Set<String>, in roots: Roots) -> Report {
        var report = Report()
        for url in strays(installed: installed, in: roots) {
            let bytes = size(of: url)
            guard (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            report.items += 1
            report.bytes += bytes
        }
        return report
    }

    /// A `defer` clears a workspace on every exit an install takes; this collects what a crash left.
    nonisolated static func sweepWorkspaces(in temp: URL) {
        for url in staleWorkspaces(in: temp) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Sized the way Finder does, so a number here matches the one in Get Info.
    nonisolated static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - What counts as a stray

    private static let workspacePrefix = "tinycast-install-"

    /// Narrow by construction: three roots, and inside them only what names itself ours or nothing.
    private nonisolated static func strays(installed: Set<String>, in roots: Roots) -> [URL] {
        let safe = Set(installed.map(ExtensionCatalog.safeName))
        let orphanedSupport = contents(of: roots.support).filter {
            !safe.contains($0.lastPathComponent)
        }
        let orphanedData = contents(of: roots.data).filter {
            $0.pathExtension == "json" && !safe.contains($0.deletingPathExtension().lastPathComponent)
        }
        return staleWorkspaces(in: roots.temp) + orphanedSupport + orphanedData
    }

    private nonisolated static func staleWorkspaces(in temp: URL) -> [URL] {
        contents(of: temp).filter { $0.lastPathComponent.hasPrefix(workspacePrefix) }
    }

    private nonisolated static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    /// An unreadable entry contributes nothing: the number is for a subtitle, not an invoice.
    private nonisolated static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func bytes(_ item: URL) -> Int64 {
            let values = try? item.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return 0 }
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            return bytes(url)
        }
        guard
            let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [])
        else { return 0 }
        return walker.reduce(into: Int64(0)) { total, item in
            if let item = item as? URL { total += bytes(item) }
        }
    }
}
