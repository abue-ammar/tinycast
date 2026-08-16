import Foundation

struct NotesRepository: Sendable {
    typealias TrashOperation = @Sendable (URL) throws -> Void

    enum Failure: Error, LocalizedError, Sendable, Equatable {
        case conflict(
            fileURL: URL,
            expected: NoteDocument.Revision,
            actual: NoteDocument.Revision?
        )
        case invalidTitle(String)
        case unreadable(URL)
        case invalidLocation(URL)
        case io(fileURL: URL, message: String)

        var errorDescription: String? {
            switch self {
            case .conflict(let fileURL, _, _):
                return "The note changed on disk before it could be saved. (\(fileURL.lastPathComponent))"
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

    func loadOrCreate(preferredID: NoteID?) throws(Failure) -> ([NoteSummary], NoteDocument) {
        var summaries = try list()
        if let preferredID, summaries.contains(where: { $0.id == preferredID }) {
            return (summaries, try load(preferredID))
        }
        if let first = summaries.first {
            return (summaries, try load(first.id))
        }
        let document = try create()
        summaries = try list()
        return (summaries, document)
    }

    func load(_ id: NoteID) throws(Failure) -> NoteDocument {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = try Data(contentsOf: url)
            guard let source = String(data: data, encoding: .utf8) else {
                throw Failure.unreadable(url)
            }
            return NoteDocument(
                id: NoteID(rawValue: url.lastPathComponent),
                source: source,
                revision: NoteDocument.Revision(data: data))
        }
    }

    func create(title: String = "Untitled") throws(Failure) -> NoteDocument {
        try mappedError(at: notesDirectory) {
            try ensureDirectory()
            let base = try validatedTitle(title)
            let occupied = Set(try list().map { folded($0.id.rawValue) })
            var suffix = 1
            while true {
                let candidate = uniqueCandidate(base: base, suffix: suffix)
                if occupied.contains(folded(candidate.lastPathComponent)) {
                    suffix += 1
                    continue
                }
                do {
                    try writeNewFileAtomically(Data(), to: candidate)
                    return try load(NoteID(rawValue: candidate.lastPathComponent))
                } catch {
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        suffix += 1
                        continue
                    }
                    throw error
                }
            }
        }
    }

    func save(
        id: NoteID,
        source: String,
        expectedRevision: NoteDocument.Revision
    ) throws(Failure) -> NoteDocument {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = Data(source.utf8)
            return try coordinatedWrite(at: url, options: .forReplacing) { coordinatedURL in
                let mutationURL = try validatedFileURL(coordinatedURL)
                let actualRevision = try revisionIfPresent(at: mutationURL)
                guard actualRevision == expectedRevision else {
                    throw Failure.conflict(
                        fileURL: url,
                        expected: expectedRevision,
                        actual: actualRevision)
                }
                try data.write(to: mutationURL, options: .atomic)
                return NoteDocument(
                    id: id,
                    source: source,
                    revision: NoteDocument.Revision(data: data))
            }
        }
    }

    func rename(
        id: NoteID,
        title: String,
        expectedRevision: NoteDocument.Revision
    ) throws(Failure) -> NoteDocument {
        let sourceURL = fileURL(for: id)
        return try mappedError(at: sourceURL) {
            let sourceURL = try validatedFileURL(sourceURL)
            let base = try validatedTitle(title)
            if folded(base + ".md") == folded(id.rawValue) { return try load(id) }
            let occupied = Set(
                try list().lazy.filter { $0.id != id }.map { folded($0.id.rawValue) })
            var suffix = 1
            while true {
                let destination = uniqueCandidate(base: base, suffix: suffix)
                if occupied.contains(folded(destination.lastPathComponent))
                    || FileManager.default.fileExists(atPath: destination.path)
                {
                    suffix += 1
                    continue
                }
                do {
                    try coordinatedWrite(at: sourceURL, options: .forMoving) { coordinatedURL in
                        let mutationURL = try validatedFileURL(coordinatedURL)
                        let actualRevision = try revisionIfPresent(at: mutationURL)
                        guard actualRevision == expectedRevision else {
                            throw Failure.conflict(
                                fileURL: sourceURL,
                                expected: expectedRevision,
                                actual: actualRevision)
                        }
                        try FileManager.default.moveItem(at: mutationURL, to: destination)
                    }
                    return try load(NoteID(rawValue: destination.lastPathComponent))
                } catch {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        suffix += 1
                        continue
                    }
                    throw error
                }
            }
        }
    }

    func trash(id: NoteID, expectedRevision: NoteDocument.Revision) throws(Failure) {
        let candidate = fileURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            try coordinatedWrite(at: url, options: .forDeleting) { coordinatedURL in
                let mutationURL = try validatedFileURL(coordinatedURL)
                let actualRevision = try revisionIfPresent(at: mutationURL)
                guard actualRevision == expectedRevision else {
                    throw Failure.conflict(
                        fileURL: url,
                        expected: expectedRevision,
                        actual: actualRevision)
                }
                try trashOperation(mutationURL)
            }
        }
    }

    func saveConflictCopy(
        id: NoteID,
        source: String,
        now: Date,
        calendar: Calendar
    ) throws(Failure) -> URL {
        try mappedError(at: notesDirectory) {
            try ensureDirectory()
            let data = Data(source.utf8)
            let title = fileURL(for: id).deletingPathExtension().lastPathComponent
            let timestamp = conflictTimestamp(now: now, calendar: calendar)
            var suffix = 1
            while true {
                let suffixText = suffix == 1 ? "" : " \(suffix)"
                let candidate = notesDirectory.appendingPathComponent(
                    "\(title) (Tinycast Conflict \(timestamp)\(suffixText)).md")
                do {
                    try writeNewFileAtomically(data, to: candidate)
                    return candidate
                } catch {
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        suffix += 1
                        continue
                    }
                    throw error
                }
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
            guard let result = NoteSearch.match(query: query, summary: summary, source: source) else {
                continue
            }
            results.append(result)
            results.sort(by: NoteSearch.precedes)
            if results.count > limit { results.removeLast() }
        }
        return results
    }

    func fileURL(for id: NoteID) -> URL {
        notesDirectory.appendingPathComponent(id.rawValue)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: notesDirectory, withIntermediateDirectories: true)
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

    private func revisionIfPresent(at fileURL: URL) throws -> NoteDocument.Revision? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return NoteDocument.Revision(data: try Data(contentsOf: fileURL))
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

    private func conflictTimestamp(now: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: now)
        return String(
            format: "%04d-%02d-%02d %02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0)
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
