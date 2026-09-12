import Foundation

struct SnippetRepository: Sendable {
    /// Holds no state beyond the `NSLock` every access already goes through.
    private final class DirectoryLock: @unchecked Sendable {
        private let lock = NSLock()

        func withLock<Value>(
            _ operation: () throws(RepositoryError) -> Value
        ) throws(RepositoryError) -> Value {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }

    /// `locks` is only ever read or written inside `lock.withLock`, which is the whole guarantee.
    private final class DirectoryLockTable: @unchecked Sendable {
        private let lock = NSLock()
        private var locks: [String: DirectoryLock] = [:]

        func directoryLock(for channelDirectory: URL) -> DirectoryLock {
            let identity = canonicalIdentity(for: channelDirectory)
            return lock.withLock {
                if let existing = locks[identity] { return existing }
                let directoryLock = DirectoryLock()
                locks[identity] = directoryLock
                return directoryLock
            }
        }

        private func canonicalIdentity(for directory: URL) -> String {
            let fileManager = FileManager.default
            var existingAncestor = directory.standardizedFileURL
            var missingComponents: [String] = []

            while !fileManager.fileExists(atPath: existingAncestor.path) {
                let parent = existingAncestor.deletingLastPathComponent()
                guard parent.path != existingAncestor.path else { break }
                missingComponents.append(existingAncestor.lastPathComponent)
                existingAncestor = parent
            }

            var resolved = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
            for component in missingComponents.reversed() {
                resolved.appendPathComponent(component, isDirectory: true)
            }
            return resolved.standardizedFileURL.path
        }
    }

    private static let directoryLocks = DirectoryLockTable()

    enum Mutation: Sendable {
        case save
        case delete
    }

    struct MutationHooks: Sendable {
        var beforeRevalidation: @Sendable (Mutation, URL) -> Void = { _, _ in }
    }

    struct Snapshot: Sendable, Equatable {
        let records: [StoredSnippet]
        let issues: [Issue]
    }

    struct Issue: Identifiable, Sendable, Equatable {
        let fileURL: URL
        let message: String

        var id: String { fileURL.standardizedFileURL.path }
    }

    enum RepositoryError: Error, LocalizedError, Sendable, Equatable {
        case conflict(
            fileURL: URL,
            expected: SnippetSourceRevision,
            actual: SnippetSourceRevision?
        )
        case fileNotFound(URL)
        case invalidFileLocation(URL)
        case io(fileURL: URL, message: String)

        var errorDescription: String? {
            switch self {
            case .conflict(let fileURL, _, _):
                return
                    "The snippet changed on disk. Reload it before saving or deleting. (\(fileURL.lastPathComponent))"
            case .fileNotFound(let fileURL):
                return "The snippet file no longer exists. (\(fileURL.lastPathComponent))"
            case .invalidFileLocation(let fileURL):
                return "The snippet file is outside this Tinycast channel. (\(fileURL.path))"
            case .io(let fileURL, let message):
                return "Could not access \(fileURL.path): \(message)"
            }
        }
    }

    let bundleIdentifier: String
    let channelDirectory: URL
    let snippetsDirectory: URL

    private let directoryLock: DirectoryLock
    private let mutationHooks: MutationHooks

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.tinycast.app",
        applicationSupportRoot: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0],
        mutationHooks: MutationHooks = MutationHooks()
    ) {
        self.bundleIdentifier = bundleIdentifier
        let channelDirectory = applicationSupportRoot.appendingPathComponent(
            bundleIdentifier,
            isDirectory: true)
        self.channelDirectory = channelDirectory
        directoryLock = Self.directoryLocks.directoryLock(for: channelDirectory)
        self.mutationHooks = mutationHooks
        snippetsDirectory = channelDirectory.appendingPathComponent("Snippets", isDirectory: true)
    }

    func load() throws(RepositoryError) -> Snapshot {
        try directoryLock.withLock { () throws(RepositoryError) -> Snapshot in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                let files = try markdownFiles(in: snippetsDirectory)
                var records: [StoredSnippet] = []
                var issues: [Issue] = []

                for fileURL in files {
                    do {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        let snippet = try SnippetMarkdownSerializer.parse(
                            content: content,
                            fileURL: fileURL)
                        records.append(
                            StoredSnippet(
                                fileURL: fileURL,
                                snippet: snippet,
                                sourceRevision: SnippetSourceRevision(content: content)))
                    } catch {
                        issues.append(Issue(fileURL: fileURL, message: error.localizedDescription))
                    }
                }

                records.sort(by: recordOrder)
                issues.sort { $0.fileURL.path < $1.fileURL.path }
                return Snapshot(records: records, issues: issues)
            }
        }
    }

    func create(_ snippet: Snippet) throws(RepositoryError) -> StoredSnippet {
        try directoryLock.withLock { () throws(RepositoryError) -> StoredSnippet in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                return try createUnlocked(snippet)
            }
        }
    }

    func create(_ snippets: [Snippet]) throws(RepositoryError) -> [StoredSnippet] {
        try directoryLock.withLock { () throws(RepositoryError) -> [StoredSnippet] in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                var created: [StoredSnippet] = []
                do {
                    for snippet in snippets {
                        created.append(try createUnlocked(snippet))
                    }
                    return created
                } catch {
                    for record in created.reversed() {
                        try? FileManager.default.removeItem(at: record.fileURL)
                    }
                    throw error
                }
            }
        }
    }

    func save(
        _ snippet: Snippet,
        fileURL: URL,
        expectedRevision: SnippetSourceRevision
    ) throws(RepositoryError) -> StoredSnippet {
        try directoryLock.withLock { () throws(RepositoryError) -> StoredSnippet in
            try mappedError(at: fileURL) {
                let fileURL = try validatedFileURL(fileURL)
                let content = SnippetMarkdownSerializer.serialize(snippet)
                return try coordinatedMutation(at: fileURL, options: .forReplacing) { coordinatedURL in
                    mutationHooks.beforeRevalidation(.save, coordinatedURL)
                    let mutationURL = try validatedFileURL(coordinatedURL)
                    let actualRevision = try revision(at: mutationURL)
                    guard actualRevision == expectedRevision else {
                        throw RepositoryError.conflict(
                            fileURL: fileURL,
                            expected: expectedRevision,
                            actual: actualRevision)
                    }
                    try Data(content.utf8).write(to: mutationURL, options: .atomic)
                    return StoredSnippet(
                        fileURL: fileURL,
                        snippet: snippet,
                        sourceRevision: SnippetSourceRevision(content: content))
                }
            }
        }
    }

    func delete(
        fileURL: URL,
        expectedRevision: SnippetSourceRevision
    ) throws(RepositoryError) {
        try directoryLock.withLock { () throws(RepositoryError) in
            try mappedError(at: fileURL) {
                let fileURL = try validatedFileURL(fileURL)
                try coordinatedMutation(at: fileURL, options: .forDeleting) { coordinatedURL in
                    mutationHooks.beforeRevalidation(.delete, coordinatedURL)
                    let mutationURL = try validatedFileURL(coordinatedURL)
                    let actualRevision = try revision(at: mutationURL)
                    guard actualRevision == expectedRevision else {
                        throw RepositoryError.conflict(
                            fileURL: fileURL,
                            expected: expectedRevision,
                            actual: actualRevision)
                    }
                    try FileManager.default.removeItem(at: mutationURL)
                }
            }
        }
    }

    /// Only has to guarantee the folder exists; intermediates cover the channel directory too.
    private func ensureSnippetsDirectory() throws {
        try FileManager.default.createDirectory(
            at: snippetsDirectory, withIntermediateDirectories: true)
    }

    private func markdownFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        .filter(Self.isLoadableFile)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // Keeps a directory or device node named `*.md` out; only non-files pay for resolving.
    private static func isLoadableFile(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return true }
        return
            (try? url.resolvingSymlinksInPath()
            .resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func createUnlocked(_ snippet: Snippet) throws -> StoredSnippet {
        let content = SnippetMarkdownSerializer.serialize(snippet)
        var suffix = 1

        while true {
            let fileURL = uniqueFileURL(
                for: snippet.name,
                suffix: suffix,
                in: snippetsDirectory)
            do {
                try writeNewFileAtomically(Data(content.utf8), to: fileURL)
                return StoredSnippet(
                    fileURL: fileURL,
                    snippet: snippet,
                    sourceRevision: SnippetSourceRevision(content: content))
            } catch {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    suffix += 1
                    continue
                }
                throw error
            }
        }
    }

    private func writeNewFileAtomically(_ data: Data, to fileURL: URL) throws {
        let temporaryURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func uniqueFileURL(for name: String, suffix: Int, in directory: URL) -> URL {
        let base = SnippetMarkdownSerializer.slug(for: name)
        let filename = suffix == 1 ? "\(base).md" : "\(base)-\(suffix).md"
        return directory.appendingPathComponent(filename)
    }

    private func validatedFileURL(_ fileURL: URL) throws -> URL {
        let standardized = fileURL.standardizedFileURL
        let parentPath = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path
        let snippetsPath = snippetsDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard parentPath == snippetsPath,
            standardized.pathExtension.lowercased() == "md"
        else {
            throw RepositoryError.invalidFileLocation(fileURL)
        }
        return standardized
    }

    private func revision(at fileURL: URL) throws -> SnippetSourceRevision {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RepositoryError.fileNotFound(fileURL)
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return SnippetSourceRevision(content: content)
    }

    private func recordOrder(_ lhs: StoredSnippet, _ rhs: StoredSnippet) -> Bool {
        let comparison = lhs.snippet.name.localizedCaseInsensitiveCompare(rhs.snippet.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func coordinatedMutation<Value>(
        at fileURL: URL,
        options: NSFileCoordinator.WritingOptions,
        _ mutation: (URL) throws -> Value
    ) throws -> Value {
        let fileCoordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        fileCoordinator.coordinate(
            writingItemAt: fileURL,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try mutation(coordinatedURL) }
        }
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw CocoaError(.fileWriteUnknown)
    }

    private func mappedError<Value>(
        at fileURL: URL,
        _ operation: () throws -> Value
    ) throws(RepositoryError) -> Value {
        do {
            return try operation()
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw .io(fileURL: fileURL, message: error.localizedDescription)
        }
    }

}
