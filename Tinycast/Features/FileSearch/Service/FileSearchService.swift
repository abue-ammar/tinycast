import CoreServices
import Foundation
import UniformTypeIdentifiers

enum FileSearchService {
    enum Failure: Error {
        case couldNotCreateQuery
        case couldNotStartQuery
    }

    /// An empty `rawQuery` is the blank screen: Spotlight's last-used order, not a name match.
    nonisolated static func search(
        query rawQuery: String, expression: String, policy: FileSearchPolicy,
        filter: FileSearchFilter = .all
    ) throws -> [FileSearchResult] {
        try Signposts.interval("FileSearchService.search") {
            let recent = rawQuery.isEmpty
            let selection = resolveScopes(policy)
            let scopes = selection.directories
            // A home-root item is matched by name, which a recents query has nothing to match.
            var results =
                recent
                ? []
                : rootResults(selection, query: rawQuery, policy: policy, filter: filter)
            if !scopes.isEmpty {
                var seen = Set(results.map(\.id))
                for result in try spotlightResults(
                    expression: expression, scopes: scopes, policy: policy, recent: recent)
                where seen.insert(result.id).inserted {
                    results.append(result)
                }
            }
            guard !recent else {
                return FileSearchQuery.filtered(
                    results, ignoring: policy.ignore, limit: FileSearchQuery.recentLimit)
            }
            return FileSearchQuery.rank(results, for: rawQuery, ignoring: policy.ignore)
        }
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

    private nonisolated static func spotlightResults(
        expression: String, scopes: [URL], policy: FileSearchPolicy, recent: Bool
    ) throws -> [FileSearchResult] {
        guard let query = MDQueryCreate(nil, expression as CFString, nil, nil) else {
            throw Failure.couldNotCreateQuery
        }
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        MDQuerySetMaxCount(query, FileSearchQuery.candidateLimit)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw Failure.couldNotStartQuery
        }

        var results: [(result: FileSearchResult, touched: Date)] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let rawItem = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(rawItem).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            let hidden = MDItemCopyAttribute(item, kMDItemFSInvisible) as? Bool ?? false
            guard !hidden else { continue }

            let contentType = (MDItemCopyAttribute(item, kMDItemContentType) as? String)
                .flatMap(UTType.init)
            guard contentType?.conforms(to: .application) != true else { continue }

            results.append(
                (
                    FileSearchResult(
                        url: URL(fileURLWithPath: path),
                        isDirectory: contentType?.conforms(to: .folder) == true,
                        homeDirectory: policy.homeDirectory),
                    recent ? touchDate(of: item) : .distantPast
                ))
        }
        // Sorted here rather than by `MDQuerySetSortOrder`, which honors neither key reliably.
        guard recent else { return results.map(\.result) }
        return results.sorted { $0.touched > $1.touched }.map(\.result)
    }

    /// Whichever of the two stamps is later; an unstamped file falls to the end of the list.
    private nonisolated static func touchDate(of item: MDItem) -> Date {
        let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let changed = MDItemCopyAttribute(item, kMDItemFSContentChangeDate) as? Date
        return max(used ?? .distantPast, changed ?? .distantPast)
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
