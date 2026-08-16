import AppKit
import SwiftUI

@MainActor
@Observable
final class NotesCoordinator {
    private enum Presentation {
        case editor
        case create
        case search
    }

    private let store: NotesStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private unowned let core: AppCore
    @ObservationIgnored private lazy var windowController = NotesWindowController(coordinator: self)
    @ObservationIgnored private lazy var switcherController = NoteSwitcherWindowController(
        coordinator: self)
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var issueTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = 0
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    private var pendingPresentation: Presentation?
    private var enablementGeneration = 0
    private(set) var isSwitcherPresented = false
    private(set) var switcherSelection: NoteID?
    private(set) var switcherFocusRevision = 0
    private(set) var characterCount = 0
    private var switcherRename = NoteSwitcherRenameState()
    private var presentationGeneration = 0

    init(
        store: NotesStore,
        settings: AppSettings,
        appIndex: AppIndex,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.core = core
        store.onIssue = { [weak self] issue in self?.present(issue) }
    }

    var editorInput: NoteEditorInput {
        NoteEditorInput(
            id: store.activeID ?? NoteID(rawValue: ""),
            source: store.source,
            epoch: store.editorEpoch)
    }

    var hasActiveNote: Bool { store.activeID != nil }
    var isActiveNoteEmpty: Bool { store.activeID != nil && store.source.isEmpty }
    /// UTF-16 units, straight off the text storage: the only length TextKit hands back in O(1).
    var characterCountLabel: String {
        characterCount == 1 ? "1 character" : "\(characterCount) characters"
    }

    var searchQueryBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.store.searchQuery ?? "" },
            set: { [weak self] in self?.store.updateSearchQuery($0) })
    }

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
        appIndex.setCommandsVisible([.showNotes, .createNote, .searchNotes], settings.notesEnabled)
        guard !settings.notesEnabled else { return }
        presentationGeneration &+= 1
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

    /// Quit waits on this so the 300 ms autosave debounce cannot swallow the last edit.
    func prepareForTermination() async {
        await store.flush()
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
        guard settings.notesEnabled, store.isLoaded else { return }
        if isSwitcherPresented {
            switcherFocusRevision &+= 1
            return
        }
        isSwitcherPresented = true
        switcherSelection = store.activeID ?? store.summaries.first?.id
        switcherFocusRevision &+= 1
        windowController.presentSwitcher(switcherController)
    }

    func closeSwitcher(focusEditor: Bool = true) {
        guard isSwitcherPresented || !store.searchQuery.isEmpty else { return }
        switcherRename.cancel()
        isSwitcherPresented = false
        switcherSelection = nil
        store.cancelSearch()
        switcherController.hide()
        if focusEditor { windowController.focusEditor() }
    }

    func hide() {
        presentationGeneration &+= 1
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
        runOperation { [weak self] generation in
            guard let self else { return }
            let selected = await store.select(id) { [weak self] in
                self?.permitsCompletion(generation) ?? false
            }
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            guard permitsCompletion(generation) else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        }
    }

    func rename(_ id: NoteID, to title: String) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            guard let renamedID, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = renamedID
            if renamedID == store.activeID, permitsCompletion(generation) {
                windowController.show(focusEditor: false)
            }
        }
    }

    func trashSwitcherSelection() {
        guard let id = switcherSelection ?? store.activeID else { return }
        trash(id)
    }

    func handleDeleteShortcut() -> Bool {
        guard isSwitcherPresented, !switcherRename.isActive else { return false }
        trashSwitcherSelection()
        return true
    }

    func trash(_ id: NoteID) {
        guard let title = store.summaries.first(where: { $0.id == id })?.title else { return }
        runOperation { [weak self] generation in
            guard let self else { return }
            let confirmed = await core.confirm(
                title: "Move “\(title)” to Trash?",
                message: "You can recover it from the Trash in Finder.",
                symbol: nil,
                confirmTitle: "Move to Trash")
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
            // Nothing left to browse, so the empty state owns the window rather than a bare list.
            if store.summaries.isEmpty { closeSwitcher(focusEditor: false) }
            guard permitsCompletion(generation) else { return }
            windowController.show(focusEditor: !isSwitcherPresented)
        }
    }

    func openNotesFolder() {
        guard let fileURL = store.activeFileURL else {
            NSWorkspace.shared.open(store.notesDirectory)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func updateSource(_ source: String) {
        store.updateSource(source)
    }

    func updateCharacterCount(_ input: NoteEditorInput, _ count: Int) {
        guard input == editorInput else { return }
        characterCount = count
    }

    func editorReady(_ textView: NoteTextView) {
        windowController.editorReady(textView)
    }

    private func request(_ presentation: Presentation) {
        guard settings.notesEnabled else { return }
        pendingPresentation = presentation
        guard loadTask == nil else { return }
        let generation = enablementGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            // Create is its own load: the collection it would wait for is the one it adds to.
            let loaded = presentation == .create ? await store.create() : await store.start()
            guard generation == enablementGeneration else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            loadTask = nil
            guard loaded, settings.notesEnabled, !Task.isCancelled else { return }
            // The note this task just made satisfies a create still pending; never make a second.
            if presentation == .create, pendingPresentation == .create {
                pendingPresentation = .editor
            }
            guard let next = pendingPresentation else { return }
            pendingPresentation = nil
            await present(next)
        }
    }

    private func present(_ presentation: Presentation) async {
        switch presentation {
        case .editor:
            closeSwitcher()
            windowController.show(focusEditor: true)
        case .create:
            let generation = presentationGeneration
            guard await store.create(), settings.notesEnabled, !Task.isCancelled,
                generation == presentationGeneration
            else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        case .search:
            // The switcher hangs off the note window, so that window has to exist first.
            windowController.show(focusEditor: false)
            openSwitcher()
        }
    }

    /// A newer show or hide retires an older operation's right to put what it loaded on screen.
    private func permitsCompletion(_ generation: Int) -> Bool {
        windowController.isVisible && generation == presentationGeneration
    }

    /// One collection operation at a time: a newer request cancels and supersedes an in-flight one.
    private func runOperation(_ body: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        operationID &+= 1
        let id = operationID
        let generation = presentationGeneration
        operationTask = Task { [weak self] in
            guard let self else { return }
            await body(generation)
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
                let retry = await core.reportFailure(
                    title: "Couldn't Open Note",
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: "Retry")
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await core.reportFailure(
                    title: "Couldn't Save Note",
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: "Retry")
                if retry { await store.retrySave() }
            case .operation(let failure):
                _ = await core.reportFailure(
                    title: "Couldn't Update Note",
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: nil)
            }
            issueTask = nil
            if let pendingIssue {
                self.pendingIssue = nil
                present(pendingIssue)
            }
        }
    }
}
