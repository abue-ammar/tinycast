import Foundation

@MainActor
@Observable
final class NotesStore {
    enum Issue: Sendable {
        case load(NotesRepository.Failure)
        case save(NotesRepository.Failure)
        case operation(NotesRepository.Failure)
    }

    private(set) var summaries: [NoteSummary] = []
    private(set) var activeID: NoteID?
    private(set) var source = ""
    private(set) var editorEpoch = 0
    private(set) var isDirty = false
    private(set) var isLoaded = false
    private(set) var searchQuery = ""
    private(set) var searchResults: [NoteSearchResult] = []
    private(set) var isSearching = false
    var activeTitle: String {
        summaries.first(where: { $0.id == activeID })?.title
            ?? activeID.map { URL(fileURLWithPath: $0.rawValue).deletingPathExtension().lastPathComponent }
            ?? "Notes"
    }
    var activeFileURL: URL? { activeID.map(repository.fileURL(for:)) }
    let notesDirectory: URL
    var onIssue: ((Issue) -> Void)?

    private let repository: NotesRepository
    private let loadSelection: @Sendable () -> NoteID?
    private let saveSelection: @Sendable (NoteID?) -> Void
    @ObservationIgnored private var saveDebounce: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchWorker: Task<[NoteSearchResult], Never>?
    private var saveFailed = false
    private var searchGeneration = 0

    init(
        repository: NotesRepository,
        loadSelection: @escaping @Sendable () -> NoteID? = { nil },
        saveSelection: @escaping @Sendable (NoteID?) -> Void = { _ in }
    ) {
        self.repository = repository
        self.loadSelection = loadSelection
        self.saveSelection = saveSelection
        notesDirectory = repository.notesDirectory
    }

    isolated deinit {
        saveDebounce?.cancel()
        searchTask?.cancel()
        searchWorker?.cancel()
    }

    /// Re-lists on every show — ⌘O makes the folder the user's — but never re-reads the live draft.
    func start() async -> Bool {
        guard isLoaded else { return await reload(preferredID: loadSelection()) }
        let repository = repository
        let result = await detached({ try repository.list() }, recover: { repository.notesDirectory })
        if case .success(let summaries) = result { self.summaries = summaries }
        return true
    }

    func reload() async -> Bool {
        await reload(preferredID: activeID ?? loadSelection())
    }

    func updateSource(_ updated: String) {
        guard activeID != nil, updated != source else { return }
        source = updated
        isDirty = true
        saveFailed = false
        scheduleSave()
    }

    @discardableResult
    func retrySave() async -> Bool {
        saveFailed = false
        return await flush()
    }

    /// The one place a write starts, so a debounced save and a flush can never overlap on one file.
    @discardableResult
    func flush() async -> Bool {
        saveDebounce?.cancel()
        saveDebounce = nil
        // Two rounds: one for a write already in flight, one for an edit that landed while it ran.
        for _ in 0..<2 {
            if let saveTask {
                await saveTask.value
                continue
            }
            guard isDirty, !saveFailed else { break }
            let task = Task { [weak self] in
                await self?.write()
                self?.saveTask = nil
            }
            saveTask = task
            await task.value
        }
        return !isDirty
    }

    @discardableResult
    func create() async -> Bool {
        guard await flush() else { return false }
        cancelSearch()
        let repository = repository
        let result = await detached {
            let document = try repository.create()
            return (document, try repository.list())
        } recover: {
            repository.notesDirectory
        }
        switch result {
        case .success(let payload):
            apply(payload.0, summaries: payload.1)
            return true
        case .failure(let failure):
            publish(.operation(failure))
            return false
        }
    }

    @discardableResult
    func select(
        _ id: NoteID,
        permitsApply: @MainActor () -> Bool = { true }
    ) async -> Bool {
        guard id != activeID else { return true }
        guard await flush() else { return false }
        guard permitsApply() else { return false }
        cancelSearch()
        let repository = repository
        let result = await detached {
            try repository.load(id)
        } recover: {
            repository.fileURL(for: id)
        }
        guard permitsApply(), !Task.isCancelled else { return false }
        switch result {
        case .success(let document):
            apply(document, summaries: summaries)
            return true
        case .failure(let failure):
            publish(.load(failure))
            return false
        }
    }

    @discardableResult
    func rename(_ id: NoteID, to title: String) async -> NoteID? {
        guard await flush() else { return nil }
        cancelSearch()
        let repository = repository
        let result = await detached {
            let renamed = try repository.rename(id: id, title: title)
            return (renamed, try repository.list())
        } recover: {
            repository.fileURL(for: id)
        }
        switch result {
        case .success(let payload):
            summaries = payload.1
            if id == activeID {
                activeID = payload.0
                saveSelection(payload.0)
            }
            return payload.0
        case .failure(let failure):
            publish(.operation(failure))
            return nil
        }
    }

    @discardableResult
    func trash(_ id: NoteID) async -> Bool {
        guard await flush() else { return false }
        let repository = repository
        let replacesActive = id == activeID
        let result = await detached {
            try repository.trash(id: id)
            let summaries = try repository.list()
            let successor = replacesActive ? summaries.first : nil
            return (try successor.map { try repository.load($0.id) }, summaries)
        } recover: {
            repository.fileURL(for: id)
        }
        switch result {
        case .success(let payload):
            cancelSearch()
            // An empty collection is a legal resting state; only creating brings a note back.
            if replacesActive {
                apply(payload.0, summaries: payload.1)
            } else {
                summaries = payload.1
            }
            return true
        case .failure(let failure):
            publish(.operation(failure))
            return false
        }
    }

    func updateSearchQuery(_ updated: String) {
        searchQuery = updated
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let query = NoteSearch.Query(updated)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            searchTask = nil
            searchWorker = nil
            return
        }
        isSearching = true
        // The previous query's rows must not linger under the new query text.
        searchResults = []
        let repository = repository
        let summaries = summaries
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                Signposts.interval("Notes.search") {
                    repository.search(query, summaries: summaries)
                }
            }
            self.searchWorker = worker
            let results = await worker.value
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            self.searchResults = results
            self.isSearching = false
            self.searchWorker = nil
            self.searchTask = nil
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchWorker?.cancel()
        searchWorker = nil
        searchGeneration &+= 1
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    /// Never cancels an in-flight write; every caller flushes first.
    func stop() {
        saveDebounce?.cancel()
        saveDebounce = nil
        cancelSearch()
    }

    private func reload(preferredID: NoteID?) async -> Bool {
        let repository = repository
        let result = await detached {
            try repository.load(preferredID: preferredID)
        } recover: {
            repository.notesDirectory
        }
        switch result {
        case .success(let payload):
            apply(payload.1, summaries: payload.0)
            return true
        case .failure(let failure):
            publish(.load(failure))
            return false
        }
    }

    private func scheduleSave() {
        saveDebounce?.cancel()
        saveDebounce = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil, let self else { return }
            saveDebounce = nil
            await flush()
        }
    }

    private func write() async {
        guard isDirty, let activeID else { return }
        let savedSource = source
        let repository = repository
        let result = await detached {
            try repository.save(id: activeID, source: savedSource)
            return try repository.list()
        } recover: {
            repository.fileURL(for: activeID)
        }
        switch result {
        case .success(let summaries):
            self.summaries = summaries
            isDirty = savedSource != source
        case .failure(let failure):
            saveFailed = true
            publish(.save(failure))
        }
    }

    private func apply(_ document: NoteDocument?, summaries: [NoteSummary]) {
        self.summaries = summaries
        activeID = document?.id
        source = document?.source ?? ""
        editorEpoch &+= 1
        isDirty = false
        saveFailed = false
        isLoaded = true
        saveSelection(document?.id)
    }

    private func publish(_ issue: Issue) {
        onIssue?(issue)
    }

    /// Every repository call is blocking IO, so it runs off-main and reports one typed failure.
    private func detached<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value,
        recover fileURL: @escaping @Sendable () -> URL
    ) async -> Result<Value, NotesRepository.Failure> {
        await Task.detached(priority: .utility) {
            do {
                return .success(try work())
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(.io(fileURL: fileURL(), message: error.localizedDescription))
            }
        }.value
    }
}
