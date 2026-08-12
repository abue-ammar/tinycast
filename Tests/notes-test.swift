import Foundation

@main
@MainActor
struct NotesTests {
    private static var failures = 0

    static func main() async throws {
        try testRepositoryAndSearch()
        testMarkdownEditorModel()
        testWindowLayout()
        try await testStoreCollectionAndExternalEdits()

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

    private static func testMarkdownEditorModel() {
        let source = "# Heading\n- [x] **done** and [link](https://example.com)\n"
        let presentation = NoteMarkdownParser.parse(source)
        let kinds = presentation.constructs.map(\.kind)

        check("parser recognizes headings", kinds.contains(.heading(level: 1)))
        check("parser recognizes unordered lists", kinds.contains(.unorderedList))
        check("parser recognizes checked tasks", kinds.contains(.task(checked: true)))
        check("parser recognizes strong text", kinds.contains(.strong))
        check(
            "parser recognizes link destinations",
            kinds.contains(.link(destination: "https://example.com")))
        check(
            "every construct points inside unchanged source",
            presentation.constructs.allSatisfy {
                $0.range.location >= 0 && NSMaxRange($0.range) <= source.utf16.count
            })

        let projection = NoteDisplayProjection.build(
            source: source,
            presentation: presentation,
            activeSourceLocation: nil)
        check(
            "inactive Markdown occupies rendered width without source gaps",
            projection.string == "Heading\n• ☑ done and link\n")
        check("projection exposes one task control anchor", projection.tasks.count == 1)
        check("projection exposes one command-click link", projection.links.count == 1)
        check(
            "display selection maps back to literal source",
            projection.sourceRange(forDisplayRange: NSRange(location: 0, length: 7))
                == NSRange(location: 2, length: 7))
        check(
            "copying a complete projection includes every hidden marker",
            projection.sourceRange(
                forCopyingDisplayRange: NSRange(
                    location: 0,
                    length: (projection.string as NSString).length))
                == NSRange(location: 0, length: (source as NSString).length))
        let doneDisplayRange = (projection.string as NSString).range(of: "done")
        let doneSourceRange = (source as NSString).range(of: "**done**")
        check(
            "copying a whole rendered construct includes its delimiters",
            projection.sourceRange(forCopyingDisplayRange: doneDisplayRange) == doneSourceRange)
        let partialDoneRange = NSRange(location: doneDisplayRange.location + 1, length: 2)
        check(
            "copying part of a rendered construct remains character exact",
            (source as NSString).substring(
                with: projection.sourceRange(forCopyingDisplayRange: partialDoneRange)) == "on")

        let linkLocation = (source as NSString).range(of: "link").location
        let active = NoteDisplayProjection.build(
            source: source,
            presentation: presentation,
            activeSourceLocation: linkLocation)
        check(
            "entering a link reveals its complete literal source",
            active.string.contains("[link](https://example.com)"))

        let bold = NoteMarkdownEditing.plan(
            .bold,
            source: "hello",
            selection: NSRange(location: 0, length: 5))
        check("bold wraps the canonical selection", bold?.replacement == "**hello**")
        check("bold preserves the selected content", bold?.selection == NSRange(location: 2, length: 5))

        let renderedBold = "**bold**"
        let renderedBoldPresentation = NoteMarkdownParser.parse(renderedBold)
        let unbold = NoteMarkdownEditing.plan(
            .bold,
            source: renderedBold,
            selection: NSRange(location: 2, length: 4),
            presentation: renderedBoldPresentation)
        check(
            "bold removes formatting from a rendered selection",
            unbold?.range == NSRange(location: 0, length: 8))
        check("bold is a true toggle in live preview", unbold?.replacement == "bold")
        let caretUnbold = NoteMarkdownEditing.plan(
            .bold,
            source: renderedBold,
            selection: NSRange(location: 4, length: 0),
            presentation: renderedBoldPresentation)
        check("Bold at a bold caret removes the format", caretUnbold?.replacement == "bold")
        check("caret unformatting preserves its logical offset", caretUnbold?.selection.location == 2)
        let partiallyBold = "**two words**"
        let partialUnbold = NoteMarkdownEditing.plan(
            .bold,
            source: partiallyBold,
            selection: (partiallyBold as NSString).range(of: "words"),
            presentation: NoteMarkdownParser.parse(partiallyBold))
        check("Bold removes formatting from only the selected suffix", partialUnbold?.replacement == "**two **words")
        let nestedBold = "**_text_**"
        let nestedUnbold = NoteMarkdownEditing.plan(
            .bold,
            source: nestedBold,
            selection: NSRange(location: 0, length: (nestedBold as NSString).length),
            presentation: NoteMarkdownParser.parse(nestedBold))
        check("removing bold preserves nested italic source", nestedUnbold?.replacement == "_text_")

        let existingLink = "[label](https://old.test)"
        let existingLinkPlan = NoteMarkdownEditing.plan(
            .link,
            source: existingLink,
            selection: (existingLink as NSString).range(of: "label"),
            presentation: NoteMarkdownParser.parse(existingLink))
        check("Link edits an existing destination without nesting", existingLinkPlan?.changesSource == false)
        check(
            "Link selects the existing destination",
            (existingLink as NSString).substring(
                with: existingLinkPlan?.selection ?? NSRange()) == "https://old.test")

        let fenced = "```\ncode\n```\n"
        let unfenced = NoteMarkdownEditing.plan(
            .codeBlock,
            source: fenced,
            selection: NSRange(location: 6, length: 0),
            presentation: NoteMarkdownParser.parse(fenced))
        check("Code Block at a fenced caret removes the fences", unfenced?.replacement == "code\n")
        check(
            "the current inline format is reported to the menu",
            NoteMarkdownEditing.activeCommands(
                selection: NSRange(location: 2, length: 4),
                source: renderedBold,
                presentation: renderedBoldPresentation).contains(.bold))
        let mixedInlineSource = "**bold** plain"
        let mixedInlineState = NoteMarkdownEditing.activeCommands(
            selection: NSRange(location: 2, length: 12),
            source: mixedInlineSource,
            presentation: NoteMarkdownParser.parse(mixedInlineSource))
        check("partially bold selections do not report Bold as active", !mixedInlineState.contains(.bold))
        let adjacentBoldSource = "**one** **two**"
        let adjacentBoldState = NoteMarkdownEditing.activeCommands(
            selection: NSRange(location: 0, length: (adjacentBoldSource as NSString).length),
            source: adjacentBoldSource,
            presentation: NoteMarkdownParser.parse(adjacentBoldSource))
        check("fully bold selections report Bold as active", adjacentBoldState.contains(.bold))
        let mixedBlocksSource = "# Heading\nPlain"
        let mixedBlockState = NoteMarkdownEditing.activeCommands(
            selection: NSRange(location: 0, length: (mixedBlocksSource as NSString).length),
            source: mixedBlocksSource,
            presentation: NoteMarkdownParser.parse(mixedBlocksSource))
        check("mixed block selections do not report a heading", !mixedBlockState.contains(.heading1))
        check("mixed block selections do not report Normal", !mixedBlockState.contains(.normal))

        let mixed = NoteMarkdownEditing.plan(
            .taskList,
            source: "- first\n2. second\n",
            selection: NSRange(location: 0, length: 18))
        check(
            "mixed block formatting normalizes instead of double-prefixing",
            mixed?.replacement == "- [ ] first\n- [ ] second\n")

        let headingAtCaret = NoteMarkdownEditing.plan(
            .heading1,
            source: "Heading",
            selection: NSRange(location: 3, length: 0))
        check("heading formatting preserves a caret", headingAtCaret?.selection == NSRange(location: 5, length: 0))
        let normalAtCaret = NoteMarkdownEditing.plan(
            .normal,
            source: "# Heading",
            selection: NSRange(location: 5, length: 0))
        check("normal formatting preserves a caret", normalAtCaret?.selection == NSRange(location: 3, length: 0))
        let selectedHeading = NoteMarkdownEditing.plan(
            .heading2,
            source: "Heading",
            selection: NSRange(location: 0, length: 7))
        check(
            "block formatting preserves selected content instead of selecting its prefix",
            selectedHeading?.selection == NSRange(location: 3, length: 7))

        let insertedRule = NoteMarkdownEditing.plan(
            .horizontalRule,
            source: "important text",
            selection: NSRange(location: 5, length: 0))
        check("horizontal rules preserve the current paragraph", insertedRule?.range.length == 0)
        check("horizontal rules insert after a paragraph", insertedRule?.replacement == "\n---\n")
        let ruleResult = ("important text" as NSString).replacingCharacters(
            in: insertedRule?.range ?? NSRange(),
            with: insertedRule?.replacement ?? "")
        check("horizontal-rule insertion loses no text", ruleResult == "important text\n---\n")

        let continuedBullet = NoteMarkdownEditing.planListEdit(
            .newline,
            source: "- item",
            selection: NSRange(location: 6, length: 0))
        check("Return continues a bullet", continuedBullet?.replacement == "\n- ")
        check("continued bullets place the caret after their marker", continuedBullet?.selection.location == 9)
        let continuedTask = NoteMarkdownEditing.planListEdit(
            .newline,
            source: "- [x] done",
            selection: NSRange(location: 10, length: 0))
        check("Return continues a task unchecked", continuedTask?.replacement == "\n- [ ] ")
        let exitedList = NoteMarkdownEditing.planListEdit(
            .newline,
            source: "- ",
            selection: NSRange(location: 2, length: 0))
        check("Return exits an empty list item", exitedList?.replacement == "")
        check("Return removes the empty list marker", exitedList?.range == NSRange(location: 0, length: 2))
        let removedPrefix = NoteMarkdownEditing.planListEdit(
            .backspace,
            source: "- item",
            selection: NSRange(location: 2, length: 0))
        check("Backspace at list content removes its marker", removedPrefix?.replacement == "")
        let indented = NoteMarkdownEditing.planListEdit(
            .indent,
            source: "- item\n",
            selection: NSRange(location: 4, length: 0))
        check("Tab nests a list item", indented?.replacement == "    - item\n")
        let outdented = NoteMarkdownEditing.planListEdit(
            .outdent,
            source: "    - item\n",
            selection: NSRange(location: 8, length: 0))
        check("Shift-Tab outdents a list item", outdented?.replacement == "- item\n")
        let nestedEmptyReturn = NoteMarkdownEditing.planListEdit(
            .newline,
            source: "    - ",
            selection: NSRange(location: 6, length: 0))
        check("Return outdents an empty nested item", nestedEmptyReturn?.range == NSRange(location: 0, length: 4))
        check("an empty nested item keeps its list marker", nestedEmptyReturn?.selection.location == 2)
        let nestedBackspace = NoteMarkdownEditing.planListEdit(
            .backspace,
            source: "    - item",
            selection: NSRange(location: 6, length: 0))
        check("Backspace outdents a nested item", nestedBackspace?.range == NSRange(location: 0, length: 4))
        check("nested Backspace keeps the list marker", nestedBackspace?.selection.location == 2)
        let mixedIndent = NoteMarkdownEditing.planListEdit(
            .indent,
            source: "- item\nplain",
            selection: NSRange(location: 0, length: 12))
        check("mixed list and prose selections are not partially indented", mixedIndent == nil)

        let directory = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
        check(
            "relative links resolve against the note directory",
            NoteLinkDestination.resolve("files/item.txt", relativeTo: directory)?.url.path
                == "/tmp/notes/files/item.txt")
        check(
            "unapproved custom schemes stay inert",
            NoteLinkDestination.resolve("custom://value", relativeTo: directory) == nil)

        let insertion = NSRange(location: (source as NSString).range(of: "done").location + 2, length: 0)
        let edited = (source as NSString).replacingCharacters(in: insertion, with: "w")
        let incrementallyParsed = NoteMarkdownParser.update(
            previousSource: source,
            source: edited,
            presentation: presentation,
            editedRange: insertion,
            replacement: "w")
        check(
            "incremental parsing converges with a clean parse",
            incrementallyParsed == NoteMarkdownParser.parse(edited))

        let grammar = NoteMarkdownParser.parse(
            "word_within_word \\*literal* ***both*** [a [b]](folder/(x).md \"title\")\n"
                + "````swift\n*raw*\n````\n---\n- item")
        let grammarKinds = grammar.constructs.map(\.kind)
        check("triple delimiters produce strong emphasis", grammarKinds.contains(.strongEmphasis))
        check(
            "balanced link destinations discard optional titles",
            grammarKinds.contains(.link(destination: "folder/(x).md")))
        check(
            "matching long fences retain their language",
            grammarKinds.contains(.codeBlock(language: "swift")))
        check("intraword underscores stay literal", !grammarKinds.contains(.emphasis))
        check("horizontal rules win over list parsing", grammarKinds.contains(.horizontalRule))
        check("a list marker followed by content remains a list", grammarKinds.contains(.unorderedList))
        let ruleProjection = NoteDisplayProjection.build(
            source: "---\n",
            presentation: NoteMarkdownParser.parse("---\n"),
            activeSourceLocation: nil)
        check(
            "horizontal rules use one decoration anchor instead of text glyphs",
            ruleProjection.string == "\u{200B}\n")
        let activeRuleProjection = NoteDisplayProjection.build(
            source: "---\n",
            presentation: NoteMarkdownParser.parse("---\n"),
            activeSourceLocation: 1)
        check("active horizontal rules reveal literal source", activeRuleProjection.string == "---\n")
        check(
            "active horizontal-rule source remains visible",
            !activeRuleProjection.styles.contains { $0.style == .horizontalRule })

        let nestedSource = "# Heading with **bold _and italic_**\n"
        let nestedPresentation = NoteMarkdownParser.parse(nestedSource)
        check(
            "nested inline formatting retains its outer construct",
            nestedPresentation.constructs.contains { $0.kind == .strong })
        check(
            "nested inline formatting retains its inner construct",
            nestedPresentation.constructs.contains { $0.kind == .emphasis })
        check(
            "nested inline markers collapse without stray syntax",
            NoteDisplayProjection.build(
                source: nestedSource,
                presentation: nestedPresentation,
                activeSourceLocation: nil).string == "Heading with bold and italic\n")
    }

    private static func testWindowLayout() {
        let metrics = NoteWindowLayout.Metrics(
            width: 520,
            minimumHeight: 220,
            maximumHeight: 640,
            maximumScreenFraction: 0.7,
            fixedContentHeight: 84)
        check(
            "short notes use the minimum height",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 10, visibleScreenHeight: 900, metrics: metrics) == 220)
        check(
            "long notes stop at the display fraction",
            NoteWindowLayout.panelHeight(
                editorContentHeight: 900, visibleScreenHeight: 800, metrics: metrics) == 560)

        let current = CGRect(x: 300, y: 300, width: 520, height: 220)
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let resized = NoteWindowLayout.resizedFrame(
            currentFrame: current, height: 400, visibleFrame: visible, width: 520)
        check("resizing preserves the top edge", resized.maxY == current.maxY)
        check("resizing grows downward", resized.minY < current.minY)
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
        let store = NotesStore(
            repository: repository,
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
        let selected = await store.select(firstID)
        check(
            "select flushes and changes the active document",
            selected && store.source == "latest searchable body")

        let activeURL = repository.fileURL(for: firstID)
        try Data("external clean".utf8).write(to: activeURL, options: .atomic)
        await waitUntil { store.source == "external clean" }
        check("a clean external edit reloads", store.source == "external clean")

        try Data([0xFF]).write(to: activeURL, options: .atomic)
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

        let projectID = try require(renamedID)
        let trashed = await store.trash(projectID)
        check("a non-active note moves to Trash", trashed)
        check("trashing another note keeps the active source", store.activeID == firstID)
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

private enum TestFailure: Error {
    case missingValue
}
