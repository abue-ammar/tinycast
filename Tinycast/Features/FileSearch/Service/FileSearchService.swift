import CoreServices
import Foundation
import UniformTypeIdentifiers

/// The blank screen's rows, from Spotlight: only it knows when a file was last used.
enum FileSearchService {
    enum Failure: Error {
        case couldNotCreateQuery
        case couldNotStartQuery
    }

    /// Two sorted queries merged by date: Spotlight sorts on one attribute, and both stamps matter.
    nonisolated static func recent(
        policy: FileSearchPolicy, filter: FileSearchFilter = .all
    ) throws -> [FileSearchResult] {
        try Signposts.interval("FileSearchService.recent") {
            let scopes = resolveScopes(policy)
            guard !scopes.isEmpty else { return [] }
            let exclusions = policy.ignore.spotlightNameExclusions
            let limit = FileSearchRecents.limit
            var dated: [String: Date] = [:]
            for stamp in FileSearchRecents.Stamp.allCases {
                let expression = FileSearchRecents.expression(
                    stamp: stamp, excluding: exclusions, filter: filter)
                // Only the head of a sorted list can reach the merged one, so only it is worth dating.
                for (path, date) in try spotlightPaths(
                    expression: expression, scopes: scopes,
                    sortedBy: stamp.rawValue as CFString, dating: limit)
                where !FileSearchRecents.isExcludedPath(path, ignoring: policy.ignore) {
                    dated[path] = max(dated[path] ?? .distantPast, date)
                }
            }
            return dated.sorted { $0.value > $1.value }
                .lazy
                .compactMap { resolve($0.key, homeDirectory: policy.homeDirectory) }
                .prefix(limit)
                .map { $0 }
        }
    }

    /// Paired with the sort stamp, which is read for the first `dating` results and no further.
    private nonisolated static func spotlightPaths(
        expression: String, scopes: [URL], sortedBy stamp: CFString, dating: Int
    ) throws -> [(path: String, date: Date)] {
        // The sort attribute has to be named at creation; set afterwards, `MDQuery` ignores it.
        guard let query = MDQueryCreate(nil, expression as CFString, nil, [stamp] as CFArray)
        else { throw Failure.couldNotCreateQuery }
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        MDQuerySetMaxCount(query, FileSearchRecents.candidateLimit)
        MDQuerySetSortOptionFlagsForAttribute(query, stamp, kMDQueryReverseSortOrderFlag.rawValue)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw Failure.couldNotStartQuery
        }
        return (0..<min(dating, MDQueryGetResultCount(query))).compactMap { index in
            guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                let date = MDItemCopyAttribute(item, stamp) as? Date
            else { return nil }
            return (path, date)
        }
    }

    /// One stat answers what three metadata fetches used to, at a thousandth of the cost.
    private nonisolated static func resolve(
        _ path: String, homeDirectory: URL
    ) -> FileSearchResult? {
        let url = URL(fileURLWithPath: path)
        guard
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isHiddenKey, .contentTypeKey
            ]), values.isHidden != true, values.contentType?.conforms(to: .application) != true
        else { return nil }
        return FileSearchResult(
            url: url, isDirectory: values.isDirectory == true, homeDirectory: homeDirectory)
    }

    private nonisolated static func resolveScopes(_ policy: FileSearchPolicy) -> [URL] {
        var directories = policy.directRoots
        if policy.includesHome {
            directories += discoverScopes(homeDirectory: policy.homeDirectory)
            directories += cloudScopes(homeDirectory: policy.homeDirectory)
        }
        var seen = Set<String>()
        return directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private nonisolated static func discoverScopes(homeDirectory: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: homeDirectory, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles])) ?? []
        let candidates = urls.compactMap { url -> FileSearchScope.Candidate? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return FileSearchScope.Candidate(
                url: url,
                isDirectory: values.isDirectory == true,
                isHidden: values.isHidden == true,
                isPackage: values.isPackage == true)
        }
        return FileSearchScope.select(candidates)
    }

    private nonisolated static func cloudScopes(homeDirectory: URL) -> [URL] {
        let candidates = [
            homeDirectory.appending(path: "Library/CloudStorage", directoryHint: .isDirectory),
            homeDirectory.appending(
                path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        ]
        return candidates.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
