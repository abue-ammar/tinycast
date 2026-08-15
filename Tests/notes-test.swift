import Foundation

@main
@MainActor
struct NotesTests {
    private static var failures = 0

    static func main() async throws {
        try testRepositoryAndSearch()
        testSwitcherInteraction()
        testWindowLayout()
        try await testStoreCollectionAndExternalEdits()
        try await testCollectionMutationsRequireCleanDraft()

        print(failures == 0 ? "Notes tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testRepositoryAndSearch() throws {
        let root = temporaryRoot("repository")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("com.tinycast.app")
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let stable = NotesRepository(
            applicationSupportDirectory: support,
            trashOperation: { url in
                try FileManager.default.moveItem(
                    at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            })
        let development = NotesRepository(
            applicationSupportDirectory: root.appendingPathComponent("com.tinycast.app.dev"))

        try FileManager.default.createDirectory(
            at: stable.notesDirectory, withIntermediateDirectories: true)
        let floatingID = NoteID(rawValue: "Floating Note.md")
        try "existing".write(
            to: stable.fileURL(for: floatingID), atomically: true, encoding: .utf8)
        let firstLoad = try stable.loadOrCreate(preferredID: nil)
        check("an existing Floating Note is discovered without migration", firstLoad.1.id == floatingID)
        check("existing Markdown source is preserved", firstLoad.1.source == "existing")
        check(
            "channels receive different Notes directories",
            stable.notesDirectory.standardizedFileURL != development.notesDirectory.standardizedFileURL)

        let untitled = try stable.create()
        let secondUntitled = try stable.create()
        check("first creation uses the plain default title", untitled.id.rawValue == "Untitled.md")
        check("duplicate titles receive a numeric suffix", secondUntitled.id.rawValue == "Untitled 2.md")

        let source = "# Heading\n\nLiteral **Markdown** and café snow\n"
        let saved = try stable.save(
            id: untitled.id, source: source, expectedRevision: untitled.revision)
        let loaded = try stable.load(untitled.id)
        check("UTF-8 Markdown round-trips unchanged", loaded.source == source)
        check("the saved revision matches a fresh load", saved.revision == loaded.revision)

        try Data("external".utf8).write(to: stable.fileURL(for: untitled.id), options: .atomic)
        do {
            _ = try stable.save(
                id: untitled.id, source: "local", expectedRevision: saved.revision)
            check("an external edit rejects a stale save", false)
        } catch let failure {
            if case .conflict = failure {
                check("an external edit rejects a stale save", true)
            } else {
                check("a stale save reports a conflict", false)
            }
        }
        let externallyChanged = try stable.load(untitled.id)
        _ = try stable.save(
            id: untitled.id, source: source, expectedRevision: externallyChanged.revision)

        let plan = try stable.create(title: "Plan")
        let foldedCollision = try stable.create(title: "plán")
        check(
            "title collisions are case- and diacritic-insensitive",
            foldedCollision.id.rawValue == "plán 2.md")
        let renamed = try stable.rename(
            id: secondUntitled.id, title: "Plan", expectedRevision: secondUntitled.revision)
        check("rename uses the same unique-title rule", renamed.id.rawValue == "Plan 3.md")

        do {
            _ = try stable.create(title: "../escape")
            check("path-forming titles are rejected", false)
        } catch let failure {
            if case .invalidTitle = failure {
                check("path-forming titles are rejected", true)
            } else {
                check("an invalid title reports the title error", false)
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = Date(timeIntervalSince1970: 1_786_464_612)
        let firstCopy = try stable.saveConflictCopy(
            id: plan.id, source: "mine", now: date, calendar: calendar)
        let secondCopy = try stable.saveConflictCopy(
            id: plan.id, source: "mine too", now: date, calendar: calendar)
        check("conflict copies retain the note title", firstCopy.lastPathComponent.hasPrefix("Plan "))
        check("same-second conflict copies get unique names", firstCopy != secondCopy)
        check(
            "conflict copies preserve their source",
            try String(contentsOf: firstCopy, encoding: .utf8) == "mine")

        let bodyMatches = stable.search(
            NoteSearch.Query("cafe snow"), summaries: try stable.list(), limit: 10)
        check("search matches Markdown bodies without transforming source", bodyMatches.contains { $0.id == untitled.id })
        let titleMatches = stable.search(
            NoteSearch.Query("Plan"), summaries: try stable.list(), limit: 1)
        check("search obeys its presentation limit", titleMatches.count == 1)
        check("title matches outrank body-only matches", titleMatches.first?.summary.title.hasPrefix("Plan") == true)

        let currentPlan = try stable.load(plan.id)
        try Data("changed before trash".utf8).write(
            to: stable.fileURL(for: plan.id), options: .atomic)
        do {
            try stable.trash(id: plan.id, expectedRevision: currentPlan.revision)
            check("Trash rechecks the byte revision", false)
        } catch let failure {
            if case .conflict = failure {
                check("Trash rechecks the byte revision", true)
            } else {
                check("a stale Trash operation reports a conflict", false)
            }
        }
        let refreshedPlan = try stable.load(plan.id)
        try stable.trash(id: plan.id, expectedRevision: refreshedPlan.revision)
        check(
            "deletion moves the file through the injected Trash operation",
            FileManager.default.fileExists(
                atPath: trash.appendingPathComponent(plan.id.rawValue).path))

        let outside = root.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outside)
        let symlinkID = NoteID(rawValue: "Linked.md")
        try FileManager.default.createSymbolicLink(
            at: stable.fileURL(for: symlinkID), withDestinationURL: outside)
        do {
            _ = try stable.load(symlinkID)
            check("a note cannot escape its channel through a symlink", false)
        } catch let failure {
            if case .invalidLocation = failure {
                check("a note cannot escape its channel through a symlink", true)
            } else {
                check("an escaping symlink reports its invalid location", false)
            }
        }
        check("symlinked Markdown files are absent from enumeration", !(try stable.list()).contains { $0.id == symlinkID })
    }

    private static func testSwitcherInteraction() {
        let id = NoteID(rawValue: "Project.md")
        var rename = NoteSwitcherRenameState()
        check("switcher rename starts inactive", !rename.isActive)
        rename.begin(id: id, title: "Project")
        check("switcher rename captures identity and title", rename.id == id && rename.draft == "Project")
        rename.updateDraft("Project plan")
        let committed = rename.commit()
        check(
            "switcher rename commits once and clears its state",
            committed?.id == id && committed?.title == "Project plan" && !rename.isActive)
        check("an inactive rename cannot commit", rename.commit() == nil)

        check(
            "Command-Delete belongs to a non-renaming switcher",
            NoteShortcutPolicy.handlesDelete(switcherPresented: true, renameActive: false))
        check(
            "Command-Delete remains native while renaming",
            !NoteShortcutPolicy.handlesDelete(switcherPresented: true, renameActive: true))
        check(
            "Command-Delete remains native in the editor",
            !NoteShortcutPolicy.handlesDelete(switcherPresented: false, renameActive: false))

        var presentation = NotePresentationGeneration()
        let capturedGeneration = presentation.current
        check(
            "an unchanged visible window accepts an operation completion",
            presentation.permitsCompletion(
                capturedGeneration: capturedGeneration,
                isVisible: true))
        presentation.advance()
        check(
            "a newer presentation rejects an old operation completion",
            !presentation.permitsCompletion(
                capturedGeneration: capturedGeneration,
                isVisible: true))
        check(
            "a hidden window rejects an operation completion",
            !presentation.permitsCompletion(
                capturedGeneration: presentation.current,
                isVisible: false))

        let first = NoteID(rawValue: "First.md")
        let second = NoteID(rawValue: "Second.md")
        let third = NoteID(rawValue: "Third.md")
        let fallback = NoteID(rawValue: "Untitled.md")
        check(
            "Trash selects the next switcher row",
            NoteSwitcherSelection.replacement(
                afterRemoving: second,
                from: [first, second, third],
                fallback: fallback) == third)
        check(
            "Trash selects the previous row when removing the last one",
            NoteSwitcherSelection.replacement(
                afterRemoving: third,
                from: [first, second, third],
                fallback: fallback) == second)
        check(
            "Trash uses the post-operation fallback when no row remains",
            NoteSwitcherSelection.replacement(
                afterRemoving: first,
                from: [first],
                fallback: fallback) == fallback)
    }

    private static func testWindowLayout() {
        let metrics = NoteWindowLayout.Metrics(
            minimumHeight: 220,
            maximumHeight: 640,
            screenMargin: 16,
            fixedContentHeight: 44)
        check(
            "short notes use the minimum height",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 10, visibleScreenHeight: 900, metrics: metrics) == 220)
        check(
            "natural height includes fixed window chrome",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 300, visibleScreenHeight: 900, metrics: metrics) == 344)
        check(
            "additional content consumes the minimum-height editor capacity first",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 48,
                visibleScreenHeight: 900,
                metrics: metrics) == 220)
        check(
            "content at the minimum-height boundary does not resize the panel",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 176,
                visibleScreenHeight: 900,
                metrics: metrics) == 220)
        check(
            "content beyond the minimum-height boundary grows only by its overflow",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 177,
                visibleScreenHeight: 900,
                metrics: metrics) == 221)
        check(
            "deleting content shrinks the panel back to its minimum",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 48,
                visibleScreenHeight: 900,
                metrics: metrics) == 220)
        check(
            "long notes stop at the named maximum",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 900, visibleScreenHeight: 900, metrics: metrics) == 640)
        check(
            "screen margins constrain shorter displays",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 900, visibleScreenHeight: 500, metrics: metrics) == 468)
        check(
            "a screen below the normal minimum becomes the effective minimum",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 10, visibleScreenHeight: 180, metrics: metrics) == 180)

        let current = CGRect(x: 300, y: 300, width: 520, height: 220)
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let constrained = NoteWindowLayout.constrainedVisibleFrame(visible, metrics: metrics)
        check("the usable frame keeps the lower screen margin", constrained.minY == 16)
        check("the usable frame keeps the upper screen margin", constrained.maxY == 884)
        let resized = NoteWindowLayout.resizedFrame(
            currentFrame: current, height: 400, visibleFrame: constrained, width: 520)
        check("resizing preserves the top edge", resized.maxY == current.maxY)
        check("resizing grows downward", resized.minY < current.minY)

        let emergencyVisible = CGRect(x: 0, y: 0, width: 1_200, height: 180)
        let emergency = NoteWindowLayout.initialFrame(
            visibleFrame: emergencyVisible,
            height: 500,
            width: 520,
            centerLiftFraction: 0.08)
        check("a very short screen clamps the whole panel", emergency.height == 180)
        check(
            "a very short screen keeps the panel reachable",
            emergency.minY == emergencyVisible.minY && emergency.maxY == emergencyVisible.maxY)
    }

    private static func testStoreCollectionAndExternalEdits() async throws {
        let root = temporaryRoot("store")
        defer { try? FileManager.default.removeItem(at: root) }
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let repository = NotesRepository(
            applicationSupportDirectory: root,
            trashOperation: { url in
                try FileManager.default.moveItem(
                    at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            })
        let selection = SelectionBox()
        let monitor = NoteFileMonitorProbe()
        let store = NotesStore(
            repository: repository,
            monitor: monitor,
            loadSelection: { selection.id },
            saveSelection: { selection.id = $0 })
        let started = await store.create()
        check(
            "Create Note is one file when it is the first action",
            started && store.activeTitle == "Untitled" && store.summaries.count == 1)
        check("active selection is persisted separately from note files", selection.id == store.activeID)

        store.updateSource("first")
        try? await Task.sleep(for: .milliseconds(80))
        store.updateSource("latest searchable body")
        await waitUntil { !store.isDirty && store.state == .ready }
        let firstID = try require(store.activeID)
        check(
            "debounced autosave writes only the latest source",
            try String(contentsOf: repository.fileURL(for: firstID), encoding: .utf8)
                == "latest searchable body")

        let created = await store.create()
        check("store creates another note", created)
        let secondID = try require(store.activeID)
        check("the new note becomes active", secondID != firstID)
        let renamedID = await store.rename(secondID, to: "Project")
        check("rename updates active identity and title", renamedID == store.activeID && store.activeTitle == "Project")

        store.updateSearchQuery("searchable")
        await waitUntil { !store.isSearching }
        check("on-demand search finds body text in another note", store.searchResults.contains { $0.id == firstID })
        store.cancelSearch()
        let selectionBeforeRejection = selection.id
        let activeBeforeRejection = store.activeID
        let rejectedSelection = await store.select(firstID, permitsApply: { false })
        check(
            "a superseded selection cannot change or persist the active note",
            !rejectedSelection && store.activeID == activeBeforeRejection
                && selection.id == selectionBeforeRejection)
        let selected = await store.select(firstID)
        check(
            "select flushes and changes the active document",
            selected && store.source == "latest searchable body")

        let activeURL = repository.fileURL(for: firstID)
        try Data("external clean".utf8).write(to: activeURL, options: .atomic)
        monitor.sendChange()
        await waitUntil { store.source == "external clean" }
        check("a clean external edit reloads", store.source == "external clean")

        try Data([0xFF]).write(to: activeURL, options: .atomic)
        monitor.sendChange()
        await waitUntil {
            if case .failed = store.state { return true }
            return false
        }
        try Data("external repaired".utf8).write(to: activeURL, options: .atomic)
        let reloaded = await store.reload()
        check("an external load failure can be retried", reloaded)
        check("a successful reload clears the load issue", store.currentIssue == nil)

        store.updateSource("local draft")
        try Data("external dirty".utf8).write(to: activeURL, options: .atomic)
        monitor.sendChange()
        await waitUntil {
            if case .conflict = store.state { return true }
            return false
        }
        check("a dirty external edit keeps the local draft", store.source == "local draft")
        check("the conflict remains available after its first report", store.currentIssue != nil)

        let recovery = await store.saveConflictCopyAndReload()
        switch recovery {
        case .success(let copy):
            check(
                "conflict recovery saves the local draft",
                (try? String(contentsOf: copy, encoding: .utf8)) == "local draft")
            check("conflict recovery reloads the disk version", store.source == "external dirty")
            check("conflict recovery clears the active issue", store.currentIssue == nil)
        case .failure:
            check("conflict recovery succeeds", false)
        }

        store.updateSource("draft before external rename")
        try FileManager.default.moveItem(
            at: activeURL,
            to: repository.fileURL(for: NoteID(rawValue: "Externally Renamed.md")))
        monitor.sendChange()
        await waitUntil {
            if case .conflict = store.state { return true }
            return false
        }
        let renamedRecovery = await store.saveConflictCopyAndReload()
        switch renamedRecovery {
        case .success(let copy):
            check(
                "external-rename recovery preserves the dirty draft",
                (try? String(contentsOf: copy, encoding: .utf8))
                    == "draft before external rename")
            check(
                "external-rename recovery selects a remaining note",
                store.activeID != firstID
                    && store.activeID != NoteID(rawValue: copy.lastPathComponent)
                    && store.state == .ready)
        case .failure:
            check("external-rename recovery succeeds", false)
        }

        let activeAfterRename = try require(store.activeID)
        let activeAfterRenameURL = repository.fileURL(for: activeAfterRename)
        store.updateSource("draft before external deletion")
        try FileManager.default.removeItem(at: activeAfterRenameURL)
        for summary in try repository.list() {
            try FileManager.default.removeItem(at: repository.fileURL(for: summary.id))
        }
        monitor.sendChange()
        await waitUntil {
            if case .conflict = store.state { return true }
            return false
        }
        let deletedRecovery = await store.saveConflictCopyAndReload()
        switch deletedRecovery {
        case .success(let copy):
            let replacementID = try require(store.activeID)
            check(
                "external-deletion recovery preserves the dirty draft",
                (try? String(contentsOf: copy, encoding: .utf8))
                    == "draft before external deletion")
            check(
                "external-deletion recovery creates a canonical note",
                store.activeTitle == "Untitled" && store.state == .ready
                    && FileManager.default.fileExists(
                        atPath: repository.fileURL(for: replacementID).path))
        case .failure:
            check("external-deletion recovery succeeds", false)
        }

        let projectID = try require(renamedID)
        if (try repository.list()).contains(where: { $0.id == projectID }) {
            let trashed = await store.trash(projectID)
            check("a non-active note moves to Trash", trashed)
            check("trashing another note keeps the active source", store.activeID != projectID)
        }
        store.stop()
    }

    private static func testCollectionMutationsRequireCleanDraft() async throws {
        let root = temporaryRoot("mutation-flush")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = NotesRepository(applicationSupportDirectory: root)
        let monitor = NoteFileMonitorProbe()
        let store = NotesStore(repository: repository, monitor: monitor)

        _ = await store.create()
        let renameTarget = try require(store.activeID)
        _ = await store.create()
        let trashTarget = try require(store.activeID)
        _ = await store.create()
        let activeID = try require(store.activeID)

        store.updateSource("local draft")
        try Data("external edit".utf8).write(
            to: repository.fileURL(for: activeID), options: .atomic)
        monitor.sendChange()
        await waitUntil {
            if case .conflict = store.state { return true }
            return false
        }

        let renamed = await store.rename(renameTarget, to: "Must Not Rename")
        check("renaming another note stops at an active conflict", renamed == nil)
        check(
            "a blocked rename leaves its target in place",
            FileManager.default.fileExists(atPath: repository.fileURL(for: renameTarget).path))

        let trashed = await store.trash(trashTarget)
        check("trashing another note stops at an active conflict", !trashed)
        check(
            "a blocked Trash leaves its target in place",
            FileManager.default.fileExists(atPath: repository.fileURL(for: trashTarget).path))
        store.stop()
    }

    private static func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "tinycast-notes-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure.missingValue }
        return value
    }

    private static func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func check(_ message: String, _ condition: @autoclosure () throws -> Bool) {
        do {
            if try condition() { return }
        } catch {
            print("FAIL: \(message) (\(error))")
            failures += 1
            return
        }
        print("FAIL: \(message)")
        failures += 1
    }
}

private final class SelectionBox: @unchecked Sendable {
    var id: NoteID?
}

@MainActor
private final class NoteFileMonitorProbe: NoteFileMonitoring {
    var onChange: (() -> Void)?
    private var isRunning = false

    func start(directory: URL, fileURL: URL) {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func sendChange() {
        guard isRunning else { return }
        isRunning = false
        onChange?()
    }
}

private enum TestFailure: Error {
    case missingValue
}
