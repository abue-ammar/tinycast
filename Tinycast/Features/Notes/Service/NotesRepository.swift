import Foundation

struct NotesRepository: Sendable {
    typealias TrashOperation = @Sendable (URL) throws -> Void

    enum Failure: Error, LocalizedError, Sendable, Equatable {
        case invalidTitle(String)
        case unreadable(URL)
        case invalidLocation(URL)
        case io(fileURL: URL, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidTitle(let title):
                return "“\(title)” can't be used as a note title."
            case .unreadable(let fileURL):
                return "The note isn't valid UTF-8. (\(fileURL.lastPathComponent))"
            case .invalidLocation(let fileURL):
                return "The note file is outside this Tinycast channel. (\(fileURL.path))"
            case .io(let fileURL, let message):
                return "Could not access \(fileURL.path): \(message)"
            }
        }
    }

    let notesDirectory: URL
    private let trashOperation: TrashOperation

    init(
        applicationSupportDirectory: URL,
        trashOperation: @escaping TrashOperation = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        notesDirectory = applicationSupportDirectory.appendingPathComponent(
            "Notes", isDirectory: true)
        self.trashOperation = trashOperation
    }

    func list() throws(Failure) -> [NoteSummary] {
        try mappedError(at: notesDirectory) {
            try ensureDirectory()
            let keys: Set<URLResourceKey> = [
                .contentModificationDateKey, .isHiddenKey, .isRegularFileKey,
                .isSymbolicLinkKey
            ]
            return try FileManager.default.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            // An entry that can't be read is skipped, never fatal: one bad file must not hide the rest.
            .compactMap { candidate -> NoteSummary? in
                guard candidate.pathExtension.caseInsensitiveCompare("md") == .orderedSame,
                    let values = try? candidate.resourceValues(forKeys: keys),
                    values.isRegularFile == true, values.isSymbolicLink != true,
                    values.isHidden != true,
                    let url = try? validatedFileURL(candidate)
                else { return nil }
                return NoteSummary(
                    id: NoteID(rawValue: url.lastPathComponent),
                    title: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: values.contentModificationDate ?? .distantPast)
            }
            .sorted(by: summaryPrecedes)
        }
    }

    /// A `nil` document is an empty collection, not a failure: creating is always the user's move.
    func load(preferredID: NoteID?) throws(Failure) -> ([NoteSummary], NoteDocument?) {
        let summaries = try list()
        if let preferredID, summaries.contains(where: { $0.id == preferredID }) {
            return (summaries, try load(preferredID))
        }
        guard let first = summaries.first else { return (summaries, nil) }
        return (summaries, try load(first.id))
    }

    func load(_ id: NoteID) throws(Failure) -> NoteDocument {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = try Data(contentsOf: url)
            guard let source = String(data: data, encoding: .utf8) else {
                throw Failure.unreadable(url)
            }
            return NoteDocument(id: NoteID(rawValue: url.lastPathComponent), source: source)
        }
    }

    func create(title: String = "Untitled") throws(Failure) -> NoteDocument {
        try mappedError(at: notesDirectory) {
            let url = try claimUniqueURL(base: try validatedTitle(title)) {
                try writeNewFileAtomically(Data(), to: $0)
            }
            return try load(NoteID(rawValue: url.lastPathComponent))
        }
    }

    func save(id: NoteID, source: String) throws(Failure) {
        let candidate = fileURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = Data(source.utf8)
            try coordinatedWrite(at: url, options: .forReplacing) { coordinatedURL in
                try data.write(to: try validatedFileURL(coordinatedURL), options: .atomic)
            }
        }
    }

    func rename(id: NoteID, title: String) throws(Failure) -> NoteID {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let sourceURL = try validatedFileURL(candidate)
            let base = try validatedTitle(title)
            // Exact, not folded: a change of case or accents alone is a rename the user asked for.
            guard base + ".md" != id.rawValue else { return id }
            let destination = try claimUniqueURL(base: base, renaming: id) { destination in
                try coordinatedWrite(at: sourceURL, options: .forMoving) { coordinatedURL in
                    try FileManager.default.moveItem(
                        at: try validatedFileURL(coordinatedURL), to: destination)
                }
            }
            return NoteID(rawValue: destination.lastPathComponent)
        }
    }

    func trash(id: NoteID) throws(Failure) {
        let candidate = fileURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            try coordinatedWrite(at: url, options: .forDeleting) { coordinatedURL in
                try trashOperation(try validatedFileURL(coordinatedURL))
            }
        }
    }

    func search(
        _ query: NoteSearch.Query,
        summaries: [NoteSummary],
        limit: Int = 200
    ) -> [NoteSearchResult] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var results: [NoteSearchResult] = []
        for summary in summaries {
            if Task.isCancelled { break }
            let source = try? load(summary.id).source
            if let result = NoteSearch.match(query: query, summary: summary, source: source) {
                results.append(result)
            }
        }
        return Array(results.sorted(by: NoteSearch.precedes).prefix(limit))
    }

    func fileURL(for id: NoteID) -> URL {
        notesDirectory.appendingPathComponent(id.rawValue)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: notesDirectory, withIntermediateDirectories: true)
    }

    /// Claims the first free `<base>.md`, `<base> 2.md`, …; a lost race only advances the suffix.
    private func claimUniqueURL(
        base: String,
        renaming id: NoteID? = nil,
        _ claim: (URL) throws -> Void
    ) throws -> URL {
        let occupied = Set(try list().lazy.filter { $0.id != id }.map { folded($0.id.rawValue) })
        var suffix = 1
        while true {
            let candidate = uniqueCandidate(base: base, suffix: suffix)
            let name = folded(candidate.lastPathComponent)
            // A case-only rename collides with its own file, which the move then replaces in place.
            let isSelf = id.map { name == folded($0.rawValue) } ?? false
            guard !occupied.contains(name),
                isSelf || !FileManager.default.fileExists(atPath: candidate.path)
            else {
                suffix += 1
                continue
            }
            do {
                try claim(candidate)
                return candidate
            } catch {
                guard !isSelf, FileManager.default.fileExists(atPath: candidate.path) else {
                    throw error
                }
                suffix += 1
            }
        }
    }

    private func validatedFileURL(_ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        let expectedParent = notesDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent().path == expectedParent.path,
            standardized.lastPathComponent == candidate.lastPathComponent,
            standardized.pathExtension.caseInsensitiveCompare("md") == .orderedSame
        else { throw Failure.invalidLocation(candidate) }
        return standardized
    }

    private func validatedTitle(_ raw: String) throws -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.lowercased().hasSuffix(".md") { title.removeLast(3) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != ".", title != "..", !title.hasPrefix("."),
            !title.contains("/"), !title.contains("\0")
        else { throw Failure.invalidTitle(raw) }
        return title
    }

    private func uniqueCandidate(base: String, suffix: Int) -> URL {
        let suffixText = suffix == 1 ? "" : " \(suffix)"
        return notesDirectory.appendingPathComponent("\(base)\(suffixText).md")
    }

    private func summaryPrecedes(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
    }

    private func writeNewFileAtomically(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func coordinatedWrite<Value>(
        at fileURL: URL,
        options: NSFileCoordinator.WritingOptions,
        _ mutation: (URL) throws -> Value
    ) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Swift.Error>?
        coordinator.coordinate(
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
    ) throws(Failure) -> Value {
        do {
            return try operation()
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .io(fileURL: fileURL, message: error.localizedDescription)
        }
    }
}
