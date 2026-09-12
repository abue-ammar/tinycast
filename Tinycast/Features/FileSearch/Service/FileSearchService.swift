import CoreServices
import Foundation
import UniformTypeIdentifiers

enum FileSearchService {
    enum Failure: Error {
        case couldNotCreateQuery
        case couldNotStartQuery
    }

    /// An empty query is the blank screen: what was used or changed lately, newest first.
    nonisolated static func search(
        query rawQuery: String, policy: FileSearchPolicy, filter: FileSearchFilter = .all
    ) throws -> [FileSearchResult] {
        try Signposts.interval("FileSearchService.search") {
            let selection = resolveScopes(policy)
            guard !rawQuery.isEmpty else {
                return try recent(scopes: selection.directories, policy: policy, filter: filter)
            }
            var results = rootResults(selection, query: rawQuery, policy: policy, filter: filter)
            guard
                !selection.directories.isEmpty,
                let expression = FileSearchQuery.expression(
                    for: rawQuery, excluding: policy.ignore.spotlightNameExclusions, filter: filter)
            else { return FileSearchQuery.rank(results, for: rawQuery, ignoring: policy.ignore) }

            var seen = Set(results.map(\.id))
            // Excluded before the stat: an ignored tree then costs a string test, not a file read.
            for path in try spotlightPaths(expression: expression, scopes: selection.directories)
            where !FileSearchQuery.isExcludedPath(path, ignoring: policy.ignore)
                && seen.insert(path).inserted
            {
                guard let result = resolve(path, homeDirectory: policy.homeDirectory) else {
                    continue
                }
                results.append(result)
            }
            return FileSearchQuery.rank(results, for: rawQuery, ignoring: policy.ignore)
        }
    }

    /// Two sorted queries merged by date: Spotlight sorts on one attribute, and both stamps matter.
    private nonisolated static func recent(
        scopes: [URL], policy: FileSearchPolicy, filter: FileSearchFilter
    ) throws -> [FileSearchResult] {
        guard !scopes.isEmpty else { return [] }
        let exclusions = policy.ignore.spotlightNameExclusions
        let limit = FileSearchQuery.recentLimit
        var dated: [String: Date] = [:]
        for stamp in FileSearchQuery.RecentStamp.allCases {
            let expression = FileSearchQuery.recentExpression(
                stamp: stamp, excluding: exclusions, filter: filter)
            // Only the head of a sorted list can reach the merged one, so only it is worth dating.
            for (path, date) in try spotlightPaths(
                expression: expression, scopes: scopes,
                sortedBy: stamp.rawValue as CFString, dating: limit)
            where !FileSearchQuery.isExcludedPath(path, ignoring: policy.ignore) {
                dated[path] = max(dated[path] ?? .distantPast, date)
            }
        }
        return dated.sorted { $0.value > $1.value }
            .lazy
            .compactMap { resolve($0.key, homeDirectory: policy.homeDirectory) }
            .prefix(limit)
            .map { $0 }
    }

    private nonisolated static func rootResults(
        _ selection: FileSearchScope.Selection, query: String, policy: FileSearchPolicy,
        filter: FileSearchFilter
    ) -> [FileSearchResult] {
        selection.rootItems.compactMap { candidate in
            guard
                filter.accepts(
                    contentType: candidate.contentType, isDirectory: candidate.isDirectory),
                FileSearchQuery.matches(filename: candidate.url.lastPathComponent, query: query)
            else { return nil }
            return FileSearchResult(
                url: candidate.url, isDirectory: candidate.isDirectory,
                homeDirectory: policy.homeDirectory)
        }
    }

    /// The path is the one attribute `MDQuery` hands back for free; every other one costs a fetch.
    private nonisolated static func spotlightPaths(
        expression: String, scopes: [URL]
    ) throws -> [String] {
        try execute(expression: expression, scopes: scopes, sortedBy: nil) { query, count in
            (0..<count).compactMap { path(in: query, at: $0) }
        }
    }

    /// Paired with the sort stamp, which is read for the first `dating` results and no further.
    private nonisolated static func spotlightPaths(
        expression: String, scopes: [URL], sortedBy stamp: CFString, dating: Int
    ) throws -> [(path: String, date: Date)] {
        try execute(expression: expression, scopes: scopes, sortedBy: stamp) { query, count in
            (0..<min(dating, count)).compactMap { index in
                guard let path = path(in: query, at: index),
                    let raw = MDQueryGetResultAtIndex(query, index)
                else { return nil }
                let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
                guard let date = MDItemCopyAttribute(item, stamp) as? Date else { return nil }
                return (path, date)
            }
        }
    }

    private nonisolated static func execute<Value>(
        expression: String, scopes: [URL], sortedBy stamp: CFString?,
        reading read: (MDQuery, CFIndex) -> Value
    ) throws -> Value {
        // The sort attribute has to be named at creation; set afterwards, `MDQuery` ignores it.
        guard let query = MDQueryCreate(nil, expression as CFString, nil, stamp.map { [$0] as CFArray })
        else { throw Failure.couldNotCreateQuery }
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        MDQuerySetMaxCount(query, FileSearchQuery.candidateLimit)
        if let stamp {
            MDQuerySetSortOptionFlagsForAttribute(
                query, stamp, kMDQueryReverseSortOrderFlag.rawValue)
        }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw Failure.couldNotStartQuery
        }
        return read(query, MDQueryGetResultCount(query))
    }

    private nonisolated static func path(in query: MDQuery, at index: CFIndex) -> String? {
        guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
        let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
        return MDItemCopyAttribute(item, kMDItemPath) as? String
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

    private nonisolated static func resolveScopes(
        _ policy: FileSearchPolicy
    )
        -> FileSearchScope.Selection
    {
        var directories = policy.directRoots
        var rootItems: [FileSearchScope.Candidate] = []
        if policy.includesHome {
            let selection = discoverScopes(homeDirectory: policy.homeDirectory)
            directories += selection.directories
            directories += cloudScopes(homeDirectory: policy.homeDirectory)
            rootItems = selection.rootItems
        }
        return FileSearchScope.Selection(
            directories: deduplicated(directories), rootItems: rootItems)
    }

    private nonisolated static func discoverScopes(homeDirectory: URL) -> FileSearchScope.Selection {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .isPackageKey, .contentTypeKey
        ]
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
                isPackage: values.isPackage == true,
                contentType: values.contentType)
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

    private nonisolated static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
