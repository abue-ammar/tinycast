import Foundation

@main
@MainActor
struct NotesTests {
    private static var failures = 0

    static func main() async throws {
        try testRepositoryAndSearch()
        testDerivedTitles()
        testMarkdownParser()
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
            "task titles omit checkbox syntax",
            NoteTitle.firstLine(of: "- [ ] Groceries\n- [x] milk") == "Groceries")
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

    private static func testMarkdownParser() {
        let tiled = ["a\nb\n", "a\r\nb", "\n\n", "x", "a\u{2029}b\rc"]
        check("empty source has no lines", NoteMarkdownParser.parse("").lines.isEmpty)
        for source in tiled {
            let lines = NoteMarkdownParser.parse(source).lines
            let string = source as NSString
            var location = 0
            var agrees = true
            for line in lines {
                agrees = agrees && line.range == string.lineRange(for: NSRange(location: location, length: 0))
                location = NSMaxRange(line.range)
            }
            check("lines tile \(source.debugDescription) like NSString", agrees && location == string.length)
        }
        check("a final terminator adds no empty line", NoteMarkdownParser.parse("a\n").lines.count == 1)
        let crlf = NoteMarkdownParser.parse("# Hi\r\nnext").lines
        check(
            "a CRLF terminator belongs to the range, never the content",
            crlf[0].range == NSRange(location: 0, length: 6)
                && crlf[0].contentRange == NSRange(location: 2, length: 2))

        check(
            "each line kind is recognised",
            kinds("para\n\n# One\n###### Six\n- a\n* b\n+ c\n1. d\n12) e\n- [ ] f\n- [x] g\n> q\n>> r\n---")
                == [
                    .paragraph, .blank, .heading(level: 1), .heading(level: 6), .bullet, .bullet, .bullet,
                    .ordered(number: 1), .ordered(number: 12), .task(checked: false),
                    .task(checked: true), .quote(depth: 1), .quote(depth: 2), .rule
                ])
        check(
            "rules win over lists, and hashtags stay paragraphs",
            kinds("- - -\n***\n___\n#hashtag\n####### seven\n3.14 pi\n-\n#")
                == [.rule, .rule, .rule, .paragraph, .paragraph, .paragraph, .bullet, .heading(level: 1)])
        check("quote nesting counts every marker", kinds("> > nested") == [.quote(depth: 2)])

        let heading = NoteMarkdownParser.parse("## Title ##").lines[0]
        check(
            "a heading marker covers the hashes and one space; a closing run stays content",
            heading.markerRange == NSRange(location: 0, length: 3)
                && substring("## Title ##", heading.contentRange) == "Title ##")

        let tasks = "- [ ] a\n- [x] b\n- [X] c\n-[ ] d\n- [y] e\n  - [ ]"
        let taskLines = NoteMarkdownParser.parse(tasks).lines
        check(
            "task checkboxes cover the bracket triple",
            taskLines[0].checkboxRange == NSRange(location: 2, length: 3)
                && substring(tasks, taskLines[1].checkboxRange) == "[x]"
                && substring(tasks, taskLines[2].checkboxRange) == "[X]"
                && taskLines[5].checkboxRange == NSRange(location: 43, length: 3))
        check(
            "malformed boxes are not tasks",
            taskLines[3].kind == .paragraph && taskLines[4].kind == .bullet
                && taskLines[4].checkboxRange == nil)
        check(
            "a task marker runs through the space after the box",
            substring(tasks, taskLines[0].markerRange) == "- [ ] "
                && substring(tasks, taskLines[0].contentRange) == "a")

        check(
            "two-space, four-space and tab indentation nest by the indent stack",
            levels("- a\n  - b\n    - c\n- d") == [0, 1, 2, 0]
                && levels("1. a\n    1. b\n\t- c") == [0, 1, 1])
        check("a blank line keeps list depth", levels("- a\n  - b\n\n  - c") == [0, 1, 0, 1])
        check("a paragraph resets list depth", levels("- a\n  - b\npara\n  - c") == [0, 1, 0, 0])

        let fenced = "```swift\n# not heading\n**x**\n````\nafter\n~~~\ncode"
        let fence = NoteMarkdownParser.parse(fenced)
        check(
            "fences mark their lines as code with no inlines",
            fence.lines.map(\.kind) == [
                .fenceOpen(language: "swift"), .code, .code, .fenceClose, .paragraph,
                .fenceOpen(language: nil), .code
            ] && fence.lines[2].inlines.isEmpty)
        check(
            "fence blocks list open through close, and an unclosed one runs to the end",
            fence.fenceBlocks == [0...3, 5...6])
        check(
            "a backtick fence never closes on tildes or a shorter run",
            kinds("````\n~~~~\n```\n````") == [.fenceOpen(language: nil), .code, .code, .fenceClose])
        check(
            "a backtick info string may not contain a backtick",
            kinds("``` a`b") == [.paragraph] && kinds("~~~ a`b") == [.fenceOpen(language: "a`b")])
        check(
            "fence lines hide whole, with an empty content range",
            fence.lines[0].markerRange == NSRange(location: 0, length: 8)
                && fence.lines[0].contentRange.length == 0)

        check(
            "emphasis, strong, both and strikethrough",
            spans("**a** _b_ ***c*** ~~d~~") == [
                .init(.strong, "a"), .init(.emphasis, "b"), .init(.strongEmphasis, "c"),
                .init(.strikethrough, "d")
            ])
        check(
            "nested spans are separate values, outer first",
            spans("**bold _both_**") == [.init(.strong, "bold _both_"), .init(.emphasis, "both")])
        check("unmatched delimiters stay text", spans("**open and * alone ~~no").isEmpty)
        check("intraword underscores stay text", spans("snake_case_name").isEmpty)
        check("whitespace-flanked delimiters do not open", spans("a * b * c").isEmpty)
        check("an escape stops a delimiter", spans("\\*not\\* *yes*") == [.init(.emphasis, "yes")])
        let strong = NoteMarkdownParser.parse("x **a** y").lines[0].inlines[0]
        check(
            "delimiter markers are hidden runs",
            strong.markerRanges == [NSRange(location: 2, length: 2), NSRange(location: 5, length: 2)]
                && strong.range == NSRange(location: 2, length: 5))

        check(
            "code spans match runs of equal length and are not parsed further",
            spans("``a ` **b**`` `c`") == [.init(.code, "a ` **b**"), .init(.code, "c")])
        check("an unclosed backtick is text", spans("`open **b**") == [.init(.strong, "b")])

        let linkSource = "see [**a** b](https://x.com/(y)) now"
        check(
            "a link parses its label and keeps balanced parentheses",
            spans(linkSource) == [
                .init(.link(destination: "https://x.com/(y)"), "**a** b"), .init(.strong, "a")
            ])
        let link = NoteMarkdownParser.parse(linkSource).lines[0].inlines[0]
        check(
            "a link hides its bracket and its destination",
            link.markerRanges.map { substring(linkSource, $0) } == ["[", "](https://x.com/(y))"])
        check("an image stays literal", spans("![alt **x**](a.png)").isEmpty)
        check("a destination with a space is not a link", spans("[a](b c)").isEmpty)

        check(
            "bare URLs link with trailing punctuation trimmed",
            spans("go https://a.com/x. or (http://b.org/p_(1)), ok")
                == [.init(.autolink, "https://a.com/x"), .init(.autolink, "http://b.org/p_(1)")])
        check(
            "bare URLs never link inside code, a link or a word",
            spans("`https://a.com` [https://b.com](https://c.com) xhttps://d.com")
                == [.init(.code, "https://a.com"), .init(.link(destination: "https://c.com"), "https://b.com")])

        let table = "| Folder | Holds |\n| --- | :---: |\n| `App/` | **root** |\nnot | a row\n\n| after |"
        check(
            "a table is a header, a matching delimiter row and the pipe rows after it",
            kinds(table) == [.table, .table, .table, .table, .blank, .paragraph])
        check(
            "table rows stay literal, with no inline spans",
            NoteMarkdownParser.parse(table).lines.allSatisfy(\.inlines.isEmpty))
        check(
            "outer pipes are optional and alignment colons are allowed",
            kinds("a | b\n:-- | --:\nc | d") == [.table, .table, .table])
        check(
            "a pipe row without a delimiter row, or with the wrong cell count, is a paragraph",
            kinds("| a | b |\n| c | d |") == [.paragraph, .paragraph]
                && kinds("| a | b |\n| --- |") == [.paragraph, .paragraph])
        check(
            "a table inside a fence stays code, and a list line never starts one",
            kinds("```\n| a |\n| --- |\n```") == [.fenceOpen(language: nil), .code, .code, .fenceClose]
                && kinds("- | a |\n| --- |") == [.bullet, .paragraph])

        let emoji = "🧑🏽‍💻 **e\u{301}** 👍🏻"
        let emojiSpan = NoteMarkdownParser.parse(emoji).lines[0].inlines[0]
        check(
            "surrogate pairs and combining marks keep exact UTF-16 ranges",
            substring(emoji, emojiSpan.range) == "**e\u{301}**"
                && substring(emoji, emojiSpan.contentRange) == "e\u{301}")

        let index = NoteMarkdownParser.parse("ab\ncd\n")
        check(
            "line lookup covers the start, a terminator and the end of the source",
            index.lineIndex(at: 0) == 0 && index.lineIndex(at: 2) == 0 && index.lineIndex(at: 3) == 1
                && index.lineIndex(at: 6) == 1 && index.lineIndex(at: 7) == nil)
        check(
            "an empty range touches its line; a range ending at a line start does not reach it",
            index.lineIndexes(intersecting: NSRange(location: 2, length: 0)) == 0..<1
                && index.lineIndexes(intersecting: NSRange(location: 0, length: 3)) == 0..<1
                && index.lineIndexes(intersecting: NSRange(location: 1, length: 3)) == 0..<2)
    }

    private struct Span: Equatable {
        let kind: NoteMarkdown.Inline.Kind
        let text: String

        init(_ kind: NoteMarkdown.Inline.Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    private static func kinds(_ source: String) -> [NoteMarkdown.Line.Kind] {
        NoteMarkdownParser.parse(source).lines.map(\.kind)
    }

    private static func levels(_ source: String) -> [Int] {
        NoteMarkdownParser.parse(source).lines.map(\.level)
    }

    /// The first line's spans, each as its kind and the text of its content.
    private static func spans(_ source: String) -> [Span] {
        let inlines = NoteMarkdownParser.parse(source).lines.first?.inlines ?? []
        return inlines.map { Span($0.kind, (source as NSString).substring(with: $0.contentRange)) }
    }

    private static func substring(_ source: String, _ range: NSRange?) -> String? {
        range.map { (source as NSString).substring(with: $0) }
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
