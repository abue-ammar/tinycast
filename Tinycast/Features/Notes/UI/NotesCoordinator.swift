import AppKit
import SwiftUI

@MainActor
@Observable
final class NotesCoordinator {
    typealias FailureReporter = (
        _ title: String,
        _ message: String,
        _ symbol: String,
        _ recovery: String?
    ) async -> Bool
    typealias TrashConfirmer = (_ title: String) async -> Bool

    private enum Presentation {
        case editor
        case create
        case search
    }

    private let store: NotesStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let reportFailure: FailureReporter
    private let confirmTrash: TrashConfirmer
    private let showMessage: (_ message: String, _ tone: DialogTone) -> Void
    @ObservationIgnored private lazy var windowController = NotesWindowController(coordinator: self)
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var issueTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    private var pendingPresentation: Presentation?
    private var enablementGeneration = 0
    private(set) var isSwitcherPresented = false
    private(set) var isFormattingPresented = false {
        didSet {
            guard oldValue != isFormattingPresented else { return }
            windowController.setFormattingPresented(isFormattingPresented)
        }
    }
    private(set) var switcherSelection: NoteID?
    private(set) var switcherFocusRevision = 0

    init(
        store: NotesStore,
        settings: AppSettings,
        appIndex: AppIndex,
        reportFailure: @escaping FailureReporter,
        confirmTrash: @escaping TrashConfirmer,
        showMessage: @escaping (_ message: String, _ tone: DialogTone) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.reportFailure = reportFailure
        self.confirmTrash = confirmTrash
        self.showMessage = showMessage
        store.onIssue = { [weak self] issue in self?.present(issue) }
    }

    var editorInput: NoteEditorInput {
        NoteEditorInput(
            id: store.activeID ?? NoteID(rawValue: ""),
            source: store.source,
            epoch: store.editorEpoch)
    }

    var searchQueryBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.store.searchQuery ?? "" },
            set: { [weak self] in self?.store.updateSearchQuery($0) })
    }

    var state: NotesStore.State { store.state }
    var isDirty: Bool { store.isDirty }
    var activeTitle: String { store.activeTitle }
    var activeID: NoteID? { store.activeID }
    var isSearching: Bool { store.isSearching }
    var visibleNotes: [NoteSummary] {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? store.summaries : store.searchResults.map(\.summary)
    }

    func searchExcerpt(for id: NoteID) -> String? {
        store.searchResults.first(where: { $0.id == id })?.excerpt
    }

    func applyEnabled() {
        enablementGeneration &+= 1
        let generation = enablementGeneration
        appIndex.setNotesCommandsVisible(settings.notesEnabled)
        guard !settings.notesEnabled else { return }
        isFormattingPresented = false
        pendingPresentation = nil
        loadTask?.cancel()
        loadTask = nil
        operationTask?.cancel()
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: false)
        Task { [weak self] in
            guard let self else { return }
            _ = await store.flush()
            guard generation == enablementGeneration, !settings.notesEnabled else { return }
            store.stop()
        }
    }

    func show() {
        request(.editor)
    }

    func createNote() {
        request(.create)
    }

    func searchNotes() {
        request(.search)
    }

    func openSwitcher() {
        guard settings.notesEnabled, store.hasLoadedDocument else { return }
        isFormattingPresented = false
        isSwitcherPresented = true
        switcherSelection = store.activeID ?? store.summaries.first?.id
        switcherFocusRevision &+= 1
    }

    func closeSwitcher(focusEditor: Bool = true) {
        guard isSwitcherPresented || !store.searchQuery.isEmpty else { return }
        isSwitcherPresented = false
        switcherSelection = nil
        store.cancelSearch()
        if focusEditor { windowController.focusEditor() }
    }

    func hide() {
        pendingPresentation = nil
        isFormattingPresented = false
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: true)
        Task { await store.flush() }
    }

    func handleEscape() {
        if isFormattingPresented {
            isFormattingPresented = false
            windowController.focusEditor()
        } else if isSwitcherPresented {
            closeSwitcher()
        } else {
            hide()
        }
    }

    func updateSwitcherSelection(_ id: NoteID?) {
        switcherSelection = id
    }

    func moveSwitcherSelection(by offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        guard let current = switcherSelection,
            let index = notes.firstIndex(where: { $0.id == current })
        else {
            switcherSelection = notes[offset < 0 ? notes.count - 1 : 0].id
            return
        }
        switcherSelection = notes[(index + offset + notes.count) % notes.count].id
    }

    func selectSwitcherNote() {
        guard let switcherSelection else { return }
        select(switcherSelection)
    }

    func select(_ id: NoteID) {
        guard operationTask == nil else { return }
        isFormattingPresented = false
        operationTask = Task { [weak self] in
            guard let self else { return }
            let selected = await store.select(id)
            operationTask = nil
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            closeSwitcher()
            showLoadedNote(focusEditor: true)
        }
    }

    func rename(_ id: NoteID, to title: String) {
        guard operationTask == nil else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            operationTask = nil
            guard let renamedID, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = renamedID
            if renamedID == store.activeID { showLoadedNote(focusEditor: false) }
        }
    }

    func trashSwitcherSelection() {
        guard let id = switcherSelection ?? store.activeID else { return }
        trash(id)
    }

    func trash(_ id: NoteID) {
        guard operationTask == nil,
            let title = store.summaries.first(where: { $0.id == id })?.title
        else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            let confirmed = await confirmTrash(title)
            guard confirmed, settings.notesEnabled, !Task.isCancelled else {
                operationTask = nil
                return
            }
            let removed = await store.trash(id)
            operationTask = nil
            guard removed, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = store.activeID ?? store.summaries.first?.id
            showLoadedNote(focusEditor: !isSwitcherPresented)
        }
    }

    func revealInFinder() {
        guard let fileURL = store.activeFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func toggleFormatting() {
        guard settings.notesEnabled, store.hasLoadedDocument, !isSwitcherPresented else { return }
        isFormattingPresented.toggle()
    }

    func dismissFormatting() {
        isFormattingPresented = false
    }

    func updateFormattingFrame(_ frame: CGRect) {
        windowController.updateFormattingFrame(frame)
    }

    func applyFormatting(_ command: NoteMarkdownCommand) {
        guard isFormattingPresented else { return }
        isFormattingPresented = false
        windowController.perform(command)
    }

    func updateSource(_ source: String) {
        store.updateSource(source)
    }

    func openLink(_ raw: String) {
        guard let directory = store.activeFileURL?.deletingLastPathComponent(),
            let destination = NoteLinkDestination.resolve(raw, relativeTo: directory)
        else { return }
        Task { [weak self] in
            do {
                try await NoteLinkLauncher.open(destination)
            } catch {
                guard let self else { return }
                _ = await reportFailure(
                    "Couldn't Open Link",
                    error.localizedDescription,
                    "link",
                    nil)
            }
        }
    }

    func updateEditorHeight(_ height: CGFloat) {
        windowController.updateEditorHeight(height)
    }

    func editorReady(_ textView: NoteTextView) {
        windowController.editorReady(textView)
    }

    func dragEnded() {
        windowController.saveFrame()
    }

    func showCurrentIssue() {
        guard let issue = store.currentIssue else { return }
        present(issue)
    }

    private func request(_ presentation: Presentation) {
        guard settings.notesEnabled else { return }
        isFormattingPresented = false
        pendingPresentation = presentation
        guard loadTask == nil else { return }
        let generation = enablementGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            if presentation == .create {
                let created = await store.create()
                guard generation == enablementGeneration else {
                    if !settings.notesEnabled { store.stop() }
                    return
                }
                loadTask = nil
                guard created, settings.notesEnabled, !Task.isCancelled else { return }
                let next = pendingPresentation
                pendingPresentation = nil
                await present(next == .create ? .editor : next ?? .editor)
                return
            }
            let loaded = await store.start()
            guard generation == enablementGeneration else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            loadTask = nil
            guard loaded, settings.notesEnabled, !Task.isCancelled,
                let presentation = pendingPresentation
            else { return }
            pendingPresentation = nil
            await present(presentation)
        }
    }

    private func present(_ presentation: Presentation) async {
        switch presentation {
        case .editor:
            closeSwitcher()
            showLoadedNote(focusEditor: true)
        case .create:
            guard await store.create() else { return }
            closeSwitcher()
            showLoadedNote(focusEditor: true)
        case .search:
            openSwitcher()
            showLoadedNote(focusEditor: false)
        }
    }

    private func showLoadedNote(focusEditor: Bool) {
        let editorHeight = NoteEditorView.contentHeight(
            for: store.source,
            width: Theme.Size.noteWidth)
        windowController.show(initialEditorHeight: editorHeight, focusEditor: focusEditor)
    }

    private func present(_ issue: NotesStore.Issue) {
        guard issueTask == nil else {
            pendingIssue = issue
            return
        }
        issueTask = Task { [weak self] in
            guard let self else { return }
            switch issue {
            case .load(let failure):
                let retry = await reportFailure(
                    "Couldn't Open Note",
                    failure.localizedDescription,
                    "note.text",
                    "Retry")
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await reportFailure(
                    "Couldn't Save Note",
                    failure.localizedDescription,
                    "note.text",
                    "Retry")
                if retry { store.retry() }
            case .conflict(let failure):
                let recover = await reportFailure(
                    "Note Changed on Disk",
                    failure.localizedDescription,
                    "exclamationmark.triangle",
                    "Save Copy & Reload")
                if recover { await recoverConflict() }
            case .operation(let failure):
                _ = await reportFailure(
                    "Couldn't Update Note",
                    failure.localizedDescription,
                    "note.text",
                    nil)
            }
            issueTask = nil
            if let pendingIssue {
                self.pendingIssue = nil
                present(pendingIssue)
            }
        }
    }

    private func recoverConflict() async {
        switch await store.saveConflictCopyAndReload() {
        case .success(let fileURL):
            showMessage("Draft Saved as \(fileURL.lastPathComponent)", .success)
        case .failure(let failure):
            _ = await reportFailure(
                "Couldn't Preserve Note",
                failure.localizedDescription,
                "exclamationmark.triangle",
                nil)
        }
    }
}
