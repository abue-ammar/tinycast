import Foundation

@main
@MainActor
struct NotesTests {
    private static var failures = 0

    static func main() async throws {
        try testRepositoryAndSearch()
        testDerivedTitles()
        try testUnnamedNotesTitleThemselves()
        testSwitcherInteraction()
        try await testStoreCollectionAndAutosave()
        try await testCollectionMutationsFlushTheDraft()
        try await testStoreRecoversFromFailures()

        print(failures == 0 ? "Notes tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testRepositoryAndSearch() throws {
        let root = temporaryRoot("repository")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("com.tinycast.app")
        let stable = try repository(in: root, support: support)
        let development = try repository(
            in: root, support: root.appendingPathComponent("com.tinycast.app.dev"))

        try FileManager.default.createDirectory(
            at: stable.notesDirectory, withIntermediateDirectories: true)
        let floatingID = NoteID(rawValue: "Floating Note.md")
        try "existing".write(
            to: stable.fileURL(for: floatingID), atomically: true, encoding: .utf8)
        let firstLoad = try stable.load(preferredID: nil)
        check("an existing Floating Note is discovered without migration", firstLoad.1?.id == floatingID)
        check("existing Markdown source is preserved", firstLoad.1?.source == "existing")
        check(
            "channels receive different Notes directories",
            stable.notesDirectory.standardizedFileURL != development.notesDirectory.standardizedFileURL)

        let untitled = try stable.create()
        let secondUntitled = try stable.create()
        check("first creation uses the plain default title", untitled.id.rawValue == "Untitled.md")
        check("duplicate titles receive a numeric suffix", secondUntitled.id.rawValue == "Untitled 2.md")

        let source = "# Heading\n\nLiteral **Markdown** and café snow\n"
        try stable.save(id: untitled.id, source: source)
        check("UTF-8 Markdown round-trips unchanged", try stable.load(untitled.id).source == source)

        try Data("external".utf8).write(to: stable.fileURL(for: untitled.id), options: .atomic)
        try stable.save(id: untitled.id, source: source)
        check(
            "Tinycast is the only writer, so a save replaces whatever is on disk",
            try stable.load(untitled.id).source == source)

        let plan = try stable.create(title: "Plan")
        let foldedCollision = try stable.create(title: "plán")
        check(
            "title collisions are case- and diacritic-insensitive",
            foldedCollision.id.rawValue == "plán 2.md")
        let renamed = try stable.rename(id: secondUntitled.id, title: "Plan")
        check("rename uses the same unique-title rule", renamed.rawValue == "Plan 3.md")

        let recased = try stable.rename(id: renamed, title: "PLAN 3")
        check("a rename that changes only case renames the file", recased.rawValue == "PLAN 3.md")
        let accented = try stable.rename(id: recased, title: "Plán 3")
        check("a rename that adds only accents renames the file", accented.rawValue == "Plán 3.md")
        check(
            "a rename to the identical title is a no-op",
            try stable.rename(id: accented, title: "Plán 3") == accented)
        check(
            "a renamed note leaves no copy under its old name",
            !(try stable.list()).contains { $0.id.rawValue == "Plan 3.md" })

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

        let bodyMatches = stable.search(
            NoteSearch.Query("cafe snow"), summaries: try stable.list(), limit: 10)
        check(
            "search matches Markdown bodies without transforming source",
            bodyMatches.contains { $0.id == untitled.id })
        let titleMatches = stable.search(
            NoteSearch.Query("Plan"), summaries: try stable.list(), limit: 1)
        check("search obeys its presentation limit", titleMatches.count == 1)
        check(
            "title matches outrank body-only matches",
            titleMatches.first?.summary.title.hasPrefix("Plan") == true)

        try stable.trash(id: plan.id)
        check(
            "deletion moves the file through the injected Trash operation",
            FileManager.default.fileExists(
                atPath: trashDirectory(in: root).appendingPathComponent(plan.id.rawValue).path))

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
        check(
            "symlinked Markdown files are absent from enumeration",
            !(try stable.list()).contains { $0.id == symlinkID })

        let empty = try repository(
            in: root, support: root.appendingPathComponent("com.tinycast.app.empty"))
        let emptyLoad = try empty.load(preferredID: nil)
        check("an empty collection loads no document", emptyLoad.0.isEmpty && emptyLoad.1 == nil)
        check(
            "loading an empty collection creates no file",
            (try FileManager.default.contentsOfDirectory(atPath: empty.notesDirectory.path)).isEmpty)
    }

    private static func testDerivedTitles() {
        check(
            "the names Create claims are unnamed",
            NoteTitle.isUnnamed("Untitled") && NoteTitle.isUnnamed("Untitled 12"))
        check(
            "a typed title is never unnamed",
            !NoteTitle.isUnnamed("Plan") && !NoteTitle.isUnnamed("untitled")
                && !NoteTitle.isUnnamed("Untitled notes") && !NoteTitle.isUnnamed("Untitled 2b"))

        check(
            "a heading marker is not part of the derived title",
            NoteTitle.firstLine(of: "#  Groceries \n\nmilk") == "Groceries")
        check(
            "leading blank lines are skipped",
            NoteTitle.firstLine(of: "\n \t \n  café snow\nmore") == "café snow")
        check(
            "a hashtag is literal text, not a heading",
            NoteTitle.firstLine(of: "####### seven\n") == "####### seven"
                && NoteTitle.firstLine(of: "#tag") == "#tag")
        check(
            "a blank note derives no title",
            NoteTitle.firstLine(of: "") == nil && NoteTitle.firstLine(of: "\n  \n\t\n") == nil)
        check(
            "a wall of text is capped to one row",
            NoteTitle.firstLine(of: String(repeating: "a", count: 400))?.count == 120)
    }

    private static func testUnnamedNotesTitleThemselves() throws {
        let root = temporaryRoot("derived")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)

        let unnamed = try repository.create()
        try repository.save(id: unnamed.id, source: "# Groceries\n\nmilk\n")
        let named = try repository.create(title: "Plan")
        try repository.save(id: named.id, source: "# Ignored heading\n")

        let summaries = try repository.list()
        let unnamedSummary = try require(summaries.first { $0.id == unnamed.id })
        check("an unnamed note shows its first line", unnamedSummary.displayTitle == "Groceries")
        check("an unnamed note keeps its filename as its title", unnamedSummary.title == "Untitled")
        let namedSummary = try require(summaries.first { $0.id == named.id })
        check(
            "a named note ignores its first line",
            namedSummary.firstLine == nil && namedSummary.displayTitle == "Plan")

        let fuzzy = repository.search(NoteSearch.Query("Grcrs"), summaries: summaries, limit: 10)
        check(
            "search matches a derived title the body never spells out",
            fuzzy.count == 1 && fuzzy.first?.id == unnamed.id)

        let renamed = try repository.rename(id: unnamed.id, title: "Shopping")
        let afterRename = try require((try repository.list()).first { $0.id == renamed })
        check("naming a note retires its derived title", afterRename.firstLine == nil)
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

    private static func testStoreCollectionAndAutosave() async throws {
        let root = temporaryRoot("store")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let selection = SelectionBox()
        let store = NotesStore(
            repository: repository,
            loadSelection: { selection.id },
            saveSelection: { selection.id = $0 })
        let started = await store.create()
        check(
            "Create Note is one file when it is the first action",
            started && store.activeTitle == "Untitled" && store.summaries.count == 1)
        check("active selection is persisted separately from note files", selection.id == store.activeID)

        store.updateSource("# Draft heading\nbody")
        check(
            "an unnamed note titles itself from the live draft",
            store.activeTitle == "Draft heading")

        store.updateSource("first")
        store.updateSource("latest searchable body")
        await waitUntil { !store.isDirty }
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
        check(
            "rename updates active identity and title",
            renamedID == store.activeID && store.activeTitle == "Project")

        store.updateSearchQuery("searchable")
        await waitUntil { !store.isSearching }
        check(
            "on-demand search finds body text in another note",
            store.searchResults.contains { $0.id == firstID })
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
        store.updateSource("draft that outlives a switch")
        let switched = await store.select(try require(renamedID))
        let flushedOnSwitch = try String(contentsOf: activeURL, encoding: .utf8)
        check(
            "switching flushes the draft before it loads another note",
            switched && flushedOnSwitch == "draft that outlives a switch")
        _ = await store.select(firstID)

        let projectID = try require(renamedID)
        let trashed = await store.trash(projectID)
        check("a non-active note moves to Trash", trashed)
        check(
            "trashing another note moves it through the injected Trash operation",
            FileManager.default.fileExists(
                atPath: trashDirectory(in: root).appendingPathComponent(projectID.rawValue).path))
        check("trashing another note keeps the active note", store.activeID == firstID)

        for summary in store.summaries {
            _ = await store.trash(summary.id)
        }
        check(
            "deleting the last note leaves the collection empty",
            store.summaries.isEmpty && store.activeID == nil && store.source.isEmpty)
        check("an empty collection is still loaded", store.isLoaded)
        store.updateSource("ignored with no active note")
        check("editing does nothing while no note is active", store.source.isEmpty)
        let recreated = await store.create()
        check("creating restores an active note", recreated && store.activeID != nil)
        store.stop()
    }

    private static func testCollectionMutationsFlushTheDraft() async throws {
        let root = temporaryRoot("mutation-flush")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let store = NotesStore(repository: repository)

        _ = await store.create()
        let renameTarget = try require(store.activeID)
        _ = await store.create()
        let trashTarget = try require(store.activeID)
        _ = await store.create()
        let activeID = try require(store.activeID)
        let activeURL = repository.fileURL(for: activeID)

        store.updateSource("draft before rename")
        let renamed = await store.rename(renameTarget, to: "Renamed")
        check("renaming another note succeeds", renamed?.rawValue == "Renamed.md")
        check(
            "renaming another note writes the active draft first",
            try String(contentsOf: activeURL, encoding: .utf8) == "draft before rename")

        store.updateSource("draft before trash")
        let trashed = await store.trash(trashTarget)
        check("trashing another note succeeds", trashed)
        check(
            "trashing another note writes the active draft first",
            try String(contentsOf: activeURL, encoding: .utf8) == "draft before trash")
        check("the active note survives another note's deletion", store.activeID == activeID)

        store.updateSource("draft before self-rename")
        let selfRenamed = await store.rename(activeID, to: "Self")
        let selfRenamedID = try require(selfRenamed)
        check("renaming the active note re-points identity", store.activeID == selfRenamedID)
        check(
            "renaming the active note carries its draft into the new file",
            try String(contentsOf: repository.fileURL(for: selfRenamedID), encoding: .utf8)
                == "draft before self-rename")
        store.stop()
    }

    private static func testStoreRecoversFromFailures() async throws {
        let root = temporaryRoot("recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        try FileManager.default.createDirectory(
            at: repository.notesDirectory, withIntermediateDirectories: true)
        let unreadable = repository.fileURL(for: NoteID(rawValue: "Unreadable.md"))
        try Data([0xFF]).write(to: unreadable, options: .atomic)

        let failingStore = NotesStore(repository: repository)
        let firstStart = await failingStore.start()
        check("a store whose first load fails does not report itself loaded", !firstStart)
        try Data("repaired".utf8).write(to: unreadable, options: .atomic)
        let secondStart = await failingStore.start()
        check(
            "a failed start can be retried in the same session",
            secondStart && failingStore.source == "repaired")
        failingStore.stop()

        let store = NotesStore(repository: repository)
        _ = await store.start()
        let activeID = try require(store.activeID)
        let activeURL = repository.fileURL(for: activeID)

        store.updateSource("concurrent draft")
        async let firstFlush = store.flush()
        async let secondFlush = store.flush()
        let flushed = await [firstFlush, secondFlush]
        check("overlapping flushes agree on one save", flushed.allSatisfy { $0 })
        check("overlapping flushes leave no unsaved draft", !store.isDirty)
        check(
            "overlapping flushes write the draft once",
            try String(contentsOf: activeURL, encoding: .utf8) == "concurrent draft")

        store.updateSource("first edit")
        async let slowFlush = store.flush()
        store.updateSource("edit during the write")
        _ = await slowFlush
        _ = await store.flush()
        check(
            "an edit that lands during a write is not lost",
            try String(contentsOf: activeURL, encoding: .utf8) == "edit during the write")
        store.stop()
    }

    /// Deleting trashes for real, so every harness repository redirects that inside the root.
    private static func repository(in root: URL, support: URL? = nil) throws -> NotesRepository {
        let trash = trashDirectory(in: root)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return NotesRepository(
            applicationSupportDirectory: support ?? root,
            trashOperation: { url in
                try FileManager.default.moveItem(
                    at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            })
    }

    private static func trashDirectory(in root: URL) -> URL {
        root.appendingPathComponent("Trash", isDirectory: true)
    }

    private static func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "tinycast-notes-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure.missingValue }
        return value
    }

    @discardableResult
    private static func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
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

private enum TestFailure: Error {
    case missingValue
}
