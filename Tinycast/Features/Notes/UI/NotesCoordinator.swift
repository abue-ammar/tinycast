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
    @ObservationIgnored private var operationID = 0
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    @ObservationIgnored private var measuredEditorHeight: (id: NoteID?, epoch: Int, height: CGFloat)?
    private var pendingPresentation: Presentation?
    private var enablementGeneration = 0
    private(set) var isSwitcherPresented = false
    private(set) var switcherSelection: NoteID?
    private(set) var switcherFocusRevision = 0
    private var switcherRename = NoteSwitcherRenameState()
    private var presentationGeneration = NotePresentationGeneration()

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
    var isSearching: Bool { store.isSearching }
    var visibleNotes: [NoteSummary] {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? store.summaries : store.searchResults.map(\.summary)
    }
    var switcherEditingID: NoteID? { switcherRename.id }
    var isRenamingSwitcherNote: Bool { switcherRename.isActive }
    var switcherTitleDraftBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.switcherRename.draft ?? "" },
            set: { [weak self] in self?.switcherRename.updateDraft($0) })
    }

    func applyEnabled() {
        enablementGeneration &+= 1
        let generation = enablementGeneration
        appIndex.setNotesCommandsVisible(settings.notesEnabled)
        guard !settings.notesEnabled else { return }
        presentationGeneration.advance()
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
        if isSwitcherPresented {
            switcherFocusRevision &+= 1
            return
        }
        isSwitcherPresented = true
        switcherSelection = store.activeID ?? store.summaries.first?.id
        switcherFocusRevision &+= 1
    }

    func closeSwitcher(focusEditor: Bool = true) {
        guard isSwitcherPresented || !store.searchQuery.isEmpty else { return }
        switcherRename.cancel()
        isSwitcherPresented = false
        switcherSelection = nil
        store.cancelSearch()
        if focusEditor { windowController.focusEditor() }
    }

    func hide() {
        presentationGeneration.advance()
        pendingPresentation = nil
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: true)
        Task { await store.flush() }
    }

    func handleEscape() {
        if isSwitcherPresented {
            closeSwitcher()
        } else {
            hide()
        }
    }

    func reconcileSwitcherSelection() {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        if let switcherSelection, notes.contains(where: { $0.id == switcherSelection }) { return }
        switcherSelection = notes.first?.id
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

    func activateSwitcherNote(_ id: NoteID) {
        switcherRename.cancel()
        select(id)
    }

    func beginSwitcherRename(_ summary: NoteSummary) {
        switcherRename.begin(id: summary.id, title: summary.title)
    }

    func commitSwitcherRename() {
        guard let committed = switcherRename.commit() else { return }
        rename(committed.id, to: committed.title)
        switcherFocusRevision &+= 1
    }

    func cancelSwitcherRename() {
        guard switcherRename.isActive else { return }
        switcherRename.cancel()
        switcherFocusRevision &+= 1
    }

    func select(_ id: NoteID) {
        runOperation { [weak self] capturedGeneration in
            guard let self else { return }
            let previousID = store.activeID
            let selected = await store.select(id) { [weak self] in
                guard let self else { return false }
                return presentationGeneration.permitsCompletion(
                    capturedGeneration: capturedGeneration,
                    isVisible: windowController.isVisible)
            }
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            guard
                presentationGeneration.permitsCompletion(
                    capturedGeneration: capturedGeneration,
                    isVisible: windowController.isVisible)
            else { return }
            closeSwitcher()
            showLoadedNote(
                focusEditor: true,
                heightBehavior: previousID == store.activeID ? .preserve : .content)
        }
    }

    func rename(_ id: NoteID, to title: String) {
        runOperation { [weak self] capturedGeneration in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            guard let renamedID, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = renamedID
            if renamedID == store.activeID,
                presentationGeneration.permitsCompletion(
                    capturedGeneration: capturedGeneration,
                    isVisible: windowController.isVisible)
            {
                showLoadedNote(focusEditor: false, heightBehavior: .preserve)
            }
        }
    }

    func trashSwitcherSelection() {
        guard let id = switcherSelection ?? store.activeID else { return }
        trash(id)
    }

    func handleDeleteShortcut() -> Bool {
        guard
            NoteShortcutPolicy.handlesDelete(
                switcherPresented: isSwitcherPresented,
                renameActive: switcherRename.isActive)
        else { return false }
        trashSwitcherSelection()
        return true
    }

    func trash(_ id: NoteID) {
        guard let title = store.summaries.first(where: { $0.id == id })?.title else { return }
        runOperation { [weak self] capturedGeneration in
            guard let self else { return }
            let previousID = store.activeID
            let confirmed = await confirmTrash(title)
            guard confirmed, settings.notesEnabled, !Task.isCancelled else { return }
            let switcherOrder = visibleNotes.map(\.id)
            let removed = await store.trash(id)
            guard removed, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = NoteSwitcherSelection.replacement(
                afterRemoving: id,
                from: switcherOrder,
                fallback: store.activeID ?? store.summaries.first?.id)
            guard
                presentationGeneration.permitsCompletion(
                    capturedGeneration: capturedGeneration,
                    isVisible: windowController.isVisible)
            else { return }
            showLoadedNote(
                focusEditor: !isSwitcherPresented,
                heightBehavior: previousID == store.activeID ? .preserve : .content)
        }
    }

    func revealInFinder() {
        guard let fileURL = store.activeFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func updateSource(_ source: String) {
        store.updateSource(source)
    }

    func updateEditorHeight(_ input: NoteEditorInput, _ height: CGFloat) {
        let current = editorInput
        guard !isSwitcherPresented, input.id == current.id, input.epoch == current.epoch else {
            return
        }
        measuredEditorHeight = (id: input.id, epoch: input.epoch, height: height)
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
                guard let next = pendingPresentation else { return }
                pendingPresentation = nil
                if next == .create {
                    closeSwitcher()
                    showLoadedNote(focusEditor: true, heightBehavior: .content)
                } else {
                    await present(next)
                }
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
            showLoadedNote(
                focusEditor: true,
                heightBehavior: windowController.isVisible ? .preserve : .content)
        case .create:
            let capturedGeneration = presentationGeneration.current
            guard await store.create(), settings.notesEnabled, !Task.isCancelled,
                presentationGeneration.permitsPresentation(
                    capturedGeneration: capturedGeneration)
            else { return }
            closeSwitcher()
            showLoadedNote(focusEditor: true, heightBehavior: .content)
        case .search:
            openSwitcher()
            showLoadedNote(
                focusEditor: false,
                heightBehavior: windowController.isVisible ? .preserve : .content)
        }
    }

    private func showLoadedNote(
        focusEditor: Bool,
        heightBehavior: NotesWindowController.HeightBehavior = .content
    ) {
        windowController.show(
            initialEditorHeight: { [weak self] in
                self?.premeasuredEditorHeight() ?? Theme.Size.noteMinimumHeight
            },
            focusEditor: focusEditor,
            heightBehavior: heightBehavior)
    }

    /// The last laid-out height for the current document, measured on demand once per show. Reusing
    /// it keeps an unchanged note from paying for a second full layout on every panel show.
    private func premeasuredEditorHeight() -> CGFloat {
        let input = editorInput
        if let measured = measuredEditorHeight,
            measured.id == input.id,
            measured.epoch == input.epoch
        {
            return measured.height
        }
        let height = NoteEditorView.contentHeight(for: input.source, width: Theme.Size.noteWidth)
        measuredEditorHeight = (id: input.id, epoch: input.epoch, height: height)
        return height
    }

    /// Runs one collection operation at a time. A newer request cancels and supersedes an in-flight
    /// one rather than being dropped; generation checks still gate any presentation it completes.
    private func runOperation(_ body: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        operationID &+= 1
        let id = operationID
        let capturedGeneration = presentationGeneration.current
        operationTask = Task { [weak self] in
            guard let self else { return }
            await body(capturedGeneration)
            if self.operationID == id { self.operationTask = nil }
        }
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
                    "text.page",
                    "Retry")
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await reportFailure(
                    "Couldn't Save Note",
                    failure.localizedDescription,
                    "text.page",
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
                    "text.page",
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
