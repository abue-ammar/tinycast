import Foundation

@MainActor
@Observable
final class NotesStore {
    enum State: Sendable, Equatable {
        case idle
        case loading
        case ready
        case saving
        case conflict(String)
        case failed(String)
    }

    enum Issue: Sendable {
        case load(NotesRepository.Failure)
        case save(NotesRepository.Failure)
        case conflict(NotesRepository.Failure)
        case operation(NotesRepository.Failure)
    }

    private(set) var summaries: [NoteSummary] = []
    private(set) var activeID: NoteID?
    private(set) var source = ""
    private(set) var editorEpoch = 0
    private(set) var state: State = .idle
    private(set) var isDirty = false
    private(set) var currentIssue: Issue?
    private(set) var searchQuery = ""
    private(set) var searchResults: [NoteSearchResult] = []
    private(set) var isSearching = false
    var hasLoadedDocument: Bool { revision != nil && activeID != nil }
    var activeTitle: String {
        summaries.first(where: { $0.id == activeID })?.title
            ?? activeID.map { URL(fileURLWithPath: $0.rawValue).deletingPathExtension().lastPathComponent }
            ?? "Notes"
    }
    var activeFileURL: URL? { activeID.map(repository.fileURL(for:)) }
    let notesDirectory: URL
    var onIssue: ((Issue) -> Void)?

    private let repository: NotesRepository
    private let monitor: any NoteFileMonitoring
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private let loadSelection: @Sendable () -> NoteID?
    private let saveSelection: @Sendable (NoteID) -> Void
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchWorker: Task<[NoteSearchResult], Never>?
    private var revision: NoteDocument.Revision?
    private var editGeneration = 0
    private var isStarted = false
    private var saveHasStarted = false
    private var saveAgain = false
    private var fileChangePending = false
    private var reconcileGeneration = 0
    private var searchGeneration = 0

    init(
        repository: NotesRepository,
        monitor: any NoteFileMonitoring = NoteFileMonitor(),
        now: @escaping @Sendable () -> Date = { Date.now },
        calendar: @escaping @Sendable () -> Calendar = { Calendar.current },
        loadSelection: @escaping @Sendable () -> NoteID? = { nil },
        saveSelection: @escaping @Sendable (NoteID) -> Void = { _ in }
    ) {
        self.repository = repository
        self.monitor = monitor
        self.now = now
        self.calendar = calendar
        self.loadSelection = loadSelection
        self.saveSelection = saveSelection
        notesDirectory = repository.notesDirectory
        monitor.onChange = { [weak self] in self?.handleFileChange() }
    }

    isolated deinit {
        saveTask?.cancel()
        reconcileTask?.cancel()
        searchTask?.cancel()
        searchWorker?.cancel()
    }

    func start() async -> Bool {
        guard !isStarted else { return hasLoadedDocument }
        isStarted = true
        if isDirty, hasLoadedDocument {
            startMonitor()
            return true
        }
        return await reload(preferredID: activeID ?? loadSelection())
    }

    func reload() async -> Bool {
        await reload(preferredID: activeID ?? loadSelection())
    }

    func updateSource(_ updated: String) {
        guard revision != nil, updated != source else { return }
        source = updated
        isDirty = true
        editGeneration &+= 1
        guard !isConflicted else { return }
        state = saveHasStarted ? .saving : .ready
        scheduleSave(after: .milliseconds(300))
    }

    func retry() {
        guard isDirty, !isConflicted else { return }
        state = .ready
        scheduleSave(after: .zero)
    }

    @discardableResult
    func flush() async -> Bool {
        guard isStarted || isDirty else { return true }
        if isConflicted { return false }
        if let saveTask {
            if !saveHasStarted {
                saveTask.cancel()
                self.saveTask = nil
            } else {
                await saveTask.value
            }
        }
        guard isDirty else { return true }
        await saveImmediately()
        return !isDirty && !isConflicted
    }

    @discardableResult
    func create() async -> Bool {
        guard await flush() else { return false }
        isStarted = true
        cancelSearch()
        let repository = repository
        let result = await Task.detached(priority: .utility) {
            do {
                let document = try repository.create()
                return Result<(NoteDocument, [NoteSummary]), NotesRepository.Failure>.success(
                    (document, try repository.list()))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.notesDirectory, message: error.localizedDescription))
            }
        }.value
        switch result {
        case .success(let payload):
            apply(payload.0, summaries: payload.1)
            startMonitor()
            return true
        case .failure(let failure):
            failOperation(failure, affectsActive: false)
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
        let result = await Task.detached(priority: .utility) {
            do {
                return Result<NoteDocument, NotesRepository.Failure>.success(try repository.load(id))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.fileURL(for: id), message: error.localizedDescription))
            }
        }.value
        guard permitsApply(), !Task.isCancelled else { return false }
        switch result {
        case .success(let document):
            apply(document, summaries: summaries)
            startMonitor()
            return true
        case .failure(let failure):
            state = .failed(failure.localizedDescription)
            publish(.load(failure))
            return false
        }
    }

    @discardableResult
    func rename(_ id: NoteID, to title: String) async -> NoteID? {
        guard await flush() else { return nil }
        cancelSearch()
        let repository = repository
        let activeID = activeID
        let activeRevision = revision
        let result = await Task.detached(priority: .utility) {
            do {
                let revision: NoteDocument.Revision
                if id == activeID, let activeRevision {
                    revision = activeRevision
                } else {
                    revision = try repository.load(id).revision
                }
                let document = try repository.rename(
                    id: id, title: title, expectedRevision: revision)
                return Result<(NoteDocument, [NoteSummary]), NotesRepository.Failure>.success(
                    (document, try repository.list()))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.fileURL(for: id), message: error.localizedDescription))
            }
        }.value
        switch result {
        case .success(let payload):
            if id == activeID {
                apply(payload.0, summaries: payload.1)
            } else {
                summaries = payload.1
            }
            startMonitor()
            return payload.0.id
        case .failure(let failure):
            failOperation(failure, affectsActive: id == activeID)
            return nil
        }
    }

    @discardableResult
    func trash(_ id: NoteID) async -> Bool {
        guard await flush() else { return false }
        let repository = repository
        let activeID = activeID
        let activeRevision = revision
        let result = await Task.detached(priority: .utility) {
            do {
                let revision: NoteDocument.Revision
                if id == activeID, let activeRevision {
                    revision = activeRevision
                } else {
                    revision = try repository.load(id).revision
                }
                try repository.trash(id: id, expectedRevision: revision)
                var summaries = try repository.list()
                let document: NoteDocument?
                if id == activeID {
                    if let first = summaries.first {
                        document = try repository.load(first.id)
                    } else {
                        document = try repository.create()
                        summaries = try repository.list()
                    }
                } else {
                    document = nil
                }
                return Result<(NoteDocument?, [NoteSummary]), NotesRepository.Failure>.success(
                    (document, summaries))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.fileURL(for: id), message: error.localizedDescription))
            }
        }.value
        switch result {
        case .success(let payload):
            summaries = payload.1
            if let document = payload.0 { apply(document, summaries: payload.1) }
            cancelSearch()
            startMonitor()
            return true
        case .failure(let failure):
            failOperation(failure, affectsActive: id == activeID)
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

    func saveConflictCopyAndReload() async -> Result<URL, NotesRepository.Failure> {
        guard isConflicted, let activeID else {
            return .failure(
                .io(fileURL: notesDirectory, message: "The note no longer has a conflict."))
        }
        let draft = source
        let repository = repository
        let now = now()
        let calendar = calendar()
        let result = await Task.detached(priority: .utility) {
            do {
                let copy = try repository.saveConflictCopy(
                    id: activeID, source: draft, now: now, calendar: calendar)
                var summaries = try repository.list()
                let copyID = NoteID(rawValue: copy.lastPathComponent)
                let document: NoteDocument
                if summaries.contains(where: { $0.id == activeID }) {
                    document = try repository.load(activeID)
                } else if let first = summaries.first(where: { $0.id != copyID }) {
                    document = try repository.load(first.id)
                } else {
                    document = try repository.create()
                    summaries = try repository.list()
                }
                return Result<(URL, NoteDocument, [NoteSummary]), NotesRepository.Failure>.success(
                    (copy, document, summaries))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.fileURL(for: activeID), message: error.localizedDescription))
            }
        }.value
        switch result {
        case .success(let payload):
            apply(payload.1, summaries: payload.2)
            startMonitor()
            return .success(payload.0)
        case .failure(let failure):
            state = .conflict(failure.localizedDescription)
            return .failure(failure)
        }
    }

    func preserveConflictForTermination() async -> Bool {
        guard isConflicted, let activeID else { return await flush() }
        let draft = source
        let repository = repository
        let now = now()
        let calendar = calendar()
        return await Task.detached(priority: .utility) {
            do {
                _ = try repository.saveConflictCopy(
                    id: activeID, source: draft, now: now, calendar: calendar)
                return true
            } catch {
                return false
            }
        }.value
    }

    func stop() {
        isStarted = false
        saveTask?.cancel()
        saveTask = nil
        reconcileTask?.cancel()
        reconcileTask = nil
        reconcileGeneration &+= 1
        cancelSearch()
        monitor.stop()
    }

    private var isConflicted: Bool {
        if case .conflict = state { return true }
        return false
    }

    private func reload(preferredID: NoteID?) async -> Bool {
        state = .loading
        let repository = repository
        let result = await Task.detached(priority: .utility) {
            do {
                return Result<([NoteSummary], NoteDocument), NotesRepository.Failure>.success(
                    try repository.loadOrCreate(preferredID: preferredID))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.notesDirectory, message: error.localizedDescription))
            }
        }.value
        switch result {
        case .success(let payload):
            apply(payload.1, summaries: payload.0)
            startMonitor()
            return true
        case .failure(let failure):
            state = .failed(failure.localizedDescription)
            publish(.load(failure))
            return false
        }
    }

    private func scheduleSave(after delay: Duration) {
        guard !saveHasStarted else {
            saveAgain = true
            return
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if delay != .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.saveHasStarted = true
            await self.saveImmediately()
            self.saveHasStarted = false
            self.saveTask = nil
            if self.fileChangePending {
                self.fileChangePending = false
                self.scheduleReconcile()
            }
            if self.saveAgain || (self.isDirty && !self.isConflicted) {
                self.saveAgain = false
                self.scheduleSave(after: .milliseconds(300))
            }
        }
    }

    private func saveImmediately() async {
        guard isDirty, let revision, let activeID else { return }
        let savedSource = source
        let savedGeneration = editGeneration
        let repository = repository
        state = .saving
        let result = await Task.detached(priority: .utility) {
            do {
                let document = try repository.save(
                    id: activeID, source: savedSource, expectedRevision: revision)
                return Result<(NoteDocument, [NoteSummary]), NotesRepository.Failure>.success(
                    (document, try repository.list()))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.fileURL(for: activeID), message: error.localizedDescription))
            }
        }.value
        switch result {
        case .success(let payload):
            self.revision = payload.0.revision
            summaries = payload.1
            isDirty = savedGeneration != editGeneration || savedSource != source
            state = .ready
            currentIssue = nil
            startMonitor()
        case .failure(let failure):
            switch failure {
            case .conflict:
                state = .conflict(failure.localizedDescription)
                publish(.conflict(failure))
            default:
                state = .failed(failure.localizedDescription)
                publish(.save(failure))
            }
        }
    }

    private func handleFileChange() {
        guard isStarted else { return }
        if saveHasStarted {
            fileChangePending = true
            return
        }
        scheduleReconcile()
    }

    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileGeneration &+= 1
        let generation = reconcileGeneration
        reconcileTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.reconcileExternalFiles(generation: generation)
        }
    }

    private func reconcileExternalFiles(generation: Int) async {
        let repository = repository
        let activeID = activeID
        let result = await Task.detached(priority: .utility) {
            do {
                let summaries = try repository.list()
                let document: NoteDocument?
                if let activeID, summaries.contains(where: { $0.id == activeID }) {
                    document = try repository.load(activeID)
                } else {
                    document = nil
                }
                return Result<([NoteSummary], NoteDocument?), NotesRepository.Failure>.success(
                    (summaries, document))
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(
                    .io(fileURL: repository.notesDirectory, message: error.localizedDescription))
            }
        }.value
        guard isStarted, generation == reconcileGeneration, !Task.isCancelled else { return }
        switch result {
        case .success(let payload):
            summaries = payload.0
            if let document = payload.1 {
                guard document.revision != revision else {
                    startMonitor()
                    return
                }
                if isDirty {
                    enterConflict(actualRevision: document.revision)
                } else {
                    apply(document, summaries: payload.0)
                    startMonitor()
                }
            } else if isDirty {
                enterConflict(actualRevision: nil)
            } else {
                _ = await reload(preferredID: nil)
            }
        case .failure(let failure):
            state = .failed(failure.localizedDescription)
            publish(.load(failure))
        }
    }

    private func enterConflict(actualRevision: NoteDocument.Revision?) {
        saveTask?.cancel()
        saveTask = nil
        let fileURL = activeID.map(repository.fileURL(for:)) ?? notesDirectory
        let expected = revision ?? NoteDocument.Revision(data: Data())
        let failure = NotesRepository.Failure.conflict(
            fileURL: fileURL,
            expected: expected,
            actual: actualRevision)
        state = .conflict(failure.localizedDescription)
        publish(.conflict(failure))
    }

    private func apply(_ document: NoteDocument, summaries: [NoteSummary]) {
        self.summaries = summaries
        activeID = document.id
        source = document.source
        editorEpoch &+= 1
        revision = document.revision
        isDirty = false
        state = .ready
        currentIssue = nil
        saveSelection(document.id)
    }

    private func failOperation(_ failure: NotesRepository.Failure, affectsActive: Bool) {
        switch (failure, affectsActive) {
        case (.conflict(_, _, let actual), true):
            enterConflict(actualRevision: actual)
        default:
            state = .failed(failure.localizedDescription)
            publish(.operation(failure))
        }
    }

    private func publish(_ issue: Issue) {
        currentIssue = issue
        onIssue?(issue)
    }

    private func startMonitor() {
        guard isStarted, let activeFileURL else { return }
        monitor.start(directory: notesDirectory, fileURL: activeFileURL)
    }
}
