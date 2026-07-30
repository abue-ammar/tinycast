// Standalone contract tests for the real pure snippet sources and main-actor store watcher.

import AppKit
import Foundation

@main
@MainActor
struct SnippetsTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        testIdentityAndRevision()
        testRaycastImport()
        try testMarkdownCodec()
        try testRepositoryStorage()
        try await testRepositoryConcurrency()
        try await testDeliveryQueueAndPasteboard()
        try await testStoreWatcher()
        testTemplateExpansion()
        testDynamicPlaceholders()
        testKeywordPolicy()
        testKeywordLifecycle()
        testKeywordListenerLifecycle()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testIdentityAndRevision() {
        let snippet = Snippet(name: "Same", text: "Body")
        let first = record("/tmp/one.md", snippet)
        let second = record("/tmp/two.md", snippet)

        check("stored identity is the standardized source path", first.id == "/tmp/one.md")
        check("identical snippets at different paths keep distinct identities", first.id != second.id)
        check(
            "source revision is deterministic",
            SnippetSourceRevision(content: "same") == SnippetSourceRevision(content: "same"))
        check(
            "source revision changes with source content",
            SnippetSourceRevision(content: "same") != SnippetSourceRevision(content: "same\n"))
    }

    private static func testRaycastImport() {
        let imported = RaycastSnippetImport.parse([
            ["name": "Email", "text": "person@example.com", "keyword": "  !email  "],
            ["name": "Multiline 雪", "text": "First\nSecond"],
            ["name": "Blank Keyword", "text": "Body", "keyword": "   "],
            ["name": "   ", "text": "Skipped"],
            ["name": "Missing Text"],
        ])

        check("Raycast import ignores an unrecognized container",
            RaycastSnippetImport.parse(["snippets": []]).isEmpty)
        check("Raycast import keeps valid entries and source order",
            imported.map(\.name) == ["Email", "Multiline 雪", "Blank Keyword"])
        // The remaining assertions index into the result, so a wrong count has to fail rather than trap.
        guard imported.count == 3 else { return }
        check("Raycast import preserves text and Unicode", imported[1].text == "First\nSecond")
        check("Raycast import trims keywords and normalizes blanks",
            imported[0].keyword == "!email" && imported[2].keyword == nil)
        check("Raycast import uses safe Tinycast defaults",
            imported.allSatisfy { $0.isEnabled && !$0.showsConfirmation })
    }

    private static func testMarkdownCodec() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/codec.md")
        let snippet = Snippet(
            name: "Quote \" slash \\ line\nreturn\rtab\t雪",
            text: "\nFirst body line\n\nLast body line\r\n",
            keyword: "!\"\\\n\t",
            isEnabled: false,
            showsConfirmation: true)
        let serialized = SnippetMarkdownSerializer.serialize(snippet)
        let parsed = try SnippetMarkdownSerializer.parse(content: serialized, fileURL: fileURL)

        check("Markdown codec round-trips escaped quoted scalars", parsed == snippet)
        check("serializer emits canonical key order", serialized.hasPrefix(
            "---\nname: \"Quote \\\" slash \\\\ line\\nreturn\\rtab\\t雪\"\nkeyword: \"!\\\"\\\\\\n\\t\"\nenabled: false\nshow_confirmation: true\n---\n"))
        check("Markdown codec preserves leading, blank, CRLF, and trailing body boundaries", parsed.text == snippet.text)

        let injection = Snippet(name: "Safe\"\nenabled: false", text: "Body")
        let injectionSource = SnippetMarkdownSerializer.serialize(injection)
        check("quoted scalar encoding prevents frontmatter line injection", !injectionSource.contains("\nenabled: false\nenabled:"))
        let parsedInjection = try SnippetMarkdownSerializer.parse(
            content: injectionSource,
            fileURL: fileURL)
        check("injection-shaped scalar round-trips literally", parsedInjection == injection)

        let crlfInjection = Snippet(
            name: "Safe\r\nenabled: false",
            text: "Body",
            keyword: "!key\r\nshow_confirmation: false")
        let crlfInjectionSource = SnippetMarkdownSerializer.serialize(crlfInjection)
        let parsedCRLFInjection = try SnippetMarkdownSerializer.parse(
            content: crlfInjectionSource,
            fileURL: fileURL)
        check("CRLF scalar graphemes are escaped and round-trip literally",
            parsedCRLFInjection == crlfInjection
                && !crlfInjectionSource.contains("Safe\r\nenabled"))
        expectParseError(
            "raw CRLF inside a quoted scalar is rejected",
            content: "---\r\nname: \"Safe\r\nenabled: false\"\r\n---\r\nBody",
            fileURL: fileURL)

        let crlf = "---\r\nname: \"CRLF\"\r\nshow_confirmation: true\r\n---\r\n\r\nBody\r\n"
        let crlfParsed = try SnippetMarkdownSerializer.parse(content: crlf, fileURL: fileURL)
        check("CRLF frontmatter parses its keys", crlfParsed.showsConfirmation)
        check("CRLF frontmatter consumes only its structural boundary", crlfParsed.text == "\r\nBody\r\n")
        let missingHUD = try SnippetMarkdownSerializer.parse(
            content: "---\nname: \"No HUD\"\n---\nBody",
            fileURL: fileURL)
        check("missing show_confirmation defaults false", !missingHUD.showsConfirmation)
        expectParseError("show_confirmation uses strict booleans", content: "---\nshow_confirmation: TRUE\n---\n", fileURL: fileURL)

        let delimiterBody = "---\nname: \"Delimiter Body\"\nenabled: true\n---\nFirst\n---\nLast\n"
        let delimiterParsed = try SnippetMarkdownSerializer.parse(
            content: delimiterBody,
            fileURL: fileURL)
        check("frontmatter delimiters inside the body remain literal", delimiterParsed.text == "First\n---\nLast\n")

        let bodyOnly = "--- not frontmatter\n\nBody"
        let bodyOnlyParsed = try SnippetMarkdownSerializer.parse(
            content: bodyOnly,
            fileURL: URL(fileURLWithPath: "/tmp/body-only-name.md"))
        check("content without an exact opening delimiter remains the body", bodyOnlyParsed.text == bodyOnly)
        check("filename fallback is deterministic", bodyOnlyParsed.name == "Body Only Name")

        let blankNameParsed = try SnippetMarkdownSerializer.parse(
            content: "---\nname: \" \\t \"\n---\nBody",
            fileURL: URL(fileURLWithPath: "/tmp/blank-name-file.md"))
        let emptyNameParsed = try SnippetMarkdownSerializer.parse(
            content: "---\nname: \"\"\n---\nBody",
            fileURL: URL(fileURLWithPath: "/tmp/blank-name-file.md"))
        check("a blank frontmatter name falls back to the filename",
            blankNameParsed.name == "Blank Name File" && emptyNameParsed.name == "Blank Name File")

        expectParseError("missing closing delimiter is rejected", content: "---\nname: \"Broken\"\n", fileURL: fileURL)
        expectParseError("non-exact closing delimiter is rejected", content: "---\nname: \"Broken\"\n--- \n", fileURL: fileURL)
        expectParseError("unquoted scalar is rejected", content: "---\nname: Broken\n---\n", fileURL: fileURL)
        expectParseError("invalid scalar escape is rejected", content: "---\nname: \"Bad\\q\"\n---\n", fileURL: fileURL)
        expectParseError("non-strict boolean is rejected", content: "---\nenabled: FALSE\n---\n", fileURL: fileURL)
        expectParseError("duplicate keys are rejected", content: "---\nname: \"A\"\nname: \"B\"\n---\n", fileURL: fileURL)
        expectParseError("the removed showInLauncher alias is rejected", content: "---\nshowInLauncher: false\n---\n", fileURL: fileURL)
        expectParseError("unknown frontmatter key is rejected", content: "---\nunknown: \"value\"\n---\n", fileURL: fileURL)
        // These keys were removed or renamed; a file still carrying one is reported, not silently half-loaded.
        expectParseError("the removed category key is rejected", content: "---\ncategory: \"Work\"\n---\n", fileURL: fileURL)
        expectParseError("the removed show_in_launcher key is rejected", content: "---\nshow_in_launcher: true\n---\n", fileURL: fileURL)
        expectParseError("the renamed show_hud key is rejected", content: "---\nshow_hud: true\n---\n", fileURL: fileURL)
    }

    private static func testRepositoryStorage() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "tinycast-snippets-tests-\(UUID().uuidString)",
            isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let channelRoot = root.appendingPathComponent("channels", isDirectory: true)
        let stable = SnippetRepository(
            bundleIdentifier: "com.tinycast.app",
            applicationSupportRoot: channelRoot)
        let beta = SnippetRepository(
            bundleIdentifier: "com.tinycast.app.beta",
            applicationSupportRoot: channelRoot)
        let dev = SnippetRepository(
            bundleIdentifier: "com.tinycast.app.dev",
            applicationSupportRoot: channelRoot)

        check("stable, beta, and dev repositories use isolated directories",
            Set([stable.snippetsDirectory, beta.snippetsDirectory, dev.snippetsDirectory]).count == 3)
        let firstLoad = try stable.load()
        check("a fresh channel starts with an empty library",
            firstLoad.records.isEmpty && firstLoad.issues.isEmpty)
        check("the first load creates the channel's snippets folder",
            fm.fileExists(atPath: stable.snippetsDirectory.path))
        check("loading one channel does not create another",
            !fm.fileExists(atPath: dev.snippetsDirectory.path))
        let secondLoad = try stable.load()
        check("a repeated load of an empty library stays empty", secondLoad.records.isEmpty)

        let corruptRoot = root.appendingPathComponent("partial-load", isDirectory: true)
        let corruptRepository = SnippetRepository(
            bundleIdentifier: "com.example.partial",
            applicationSupportRoot: corruptRoot)
        try fm.createDirectory(at: corruptRepository.snippetsDirectory, withIntermediateDirectories: true)
        let validURL = corruptRepository.snippetsDirectory.appendingPathComponent("valid.md")
        try SnippetMarkdownSerializer.serialize(Snippet(name: "Valid", text: "Body"))
            .write(to: validURL, atomically: true, encoding: .utf8)
        let invalidURL = corruptRepository.snippetsDirectory.appendingPathComponent("invalid.md")
        try "---\nname: unquoted\n---\nBody".write(
            to: invalidURL,
            atomically: true,
            encoding: .utf8)
        let partial = try corruptRepository.load()
        check("a malformed file does not hide valid records", partial.records.map(\.snippet.name) == ["Valid"])
        check("malformed files are returned as per-file issues",
            partial.issues.count == 1
                && partial.issues[0].fileURL.standardizedFileURL.path == invalidURL.standardizedFileURL.path)

        let directoryEntryURL = corruptRepository.snippetsDirectory.appendingPathComponent(
            "folder.md",
            isDirectory: true)
        try fm.createDirectory(at: directoryEntryURL, withIntermediateDirectories: true)
        let linkedEntryURL = corruptRepository.snippetsDirectory.appendingPathComponent("linked.md")
        try fm.createSymbolicLink(at: linkedEntryURL, withDestinationURL: validURL)
        let nonRegularEntries = try corruptRepository.load()
        check("a directory named like a snippet is neither loaded nor reported as an issue",
            !nonRegularEntries.records.contains {
                $0.id == directoryEntryURL.standardizedFileURL.path
            }
                && !nonRegularEntries.issues.contains {
                    $0.fileURL.standardizedFileURL.path == directoryEntryURL.standardizedFileURL.path
                })
        check("a snippet file symlinked into the folder still loads",
            nonRegularEntries.records.contains {
                $0.id == linkedEntryURL.standardizedFileURL.path
            })

        let crudRoot = root.appendingPathComponent("crud", isDirectory: true)
        let crudRepository = SnippetRepository(
            bundleIdentifier: "com.example.crud",
            applicationSupportRoot: crudRoot)
        let imported = try crudRepository.create([
            Snippet(name: "Imported", text: "One"),
            Snippet(name: "Imported", text: "Two", keyword: "!two"),
        ])
        check("batch import creates every snippet without overwriting duplicate names",
            imported.map { $0.fileURL.lastPathComponent } == ["imported.md", "imported-2.md"])
        let importedReload = try crudRepository.load()
        check("batch import round-trips through Markdown storage",
            importedReload.records.filter { $0.snippet.name == "Imported" }.count == 2)

        let first = try crudRepository.create(Snippet(name: "Same", text: "One"))
        let second = try crudRepository.create(Snippet(name: "Same", text: "Two"))
        check("create never overwrites an existing slug",
            first.fileURL.lastPathComponent == "same.md" && second.fileURL.lastPathComponent == "same-2.md")
        let oddURL = crudRepository.snippetsDirectory.appendingPathComponent("unrelated-filename.md")
        try SnippetMarkdownSerializer.serialize(Snippet(name: "Frontmatter Name", text: "Odd"))
            .write(to: oddURL, atomically: true, encoding: .utf8)
        let withOddFilename = try crudRepository.load()
        check("frontmatter names do not replace path identity",
            withOddFilename.records.contains { $0.id == oddURL.path && $0.snippet.name == "Frontmatter Name" })

        var edited = first.snippet
        edited.name = "Renamed in Frontmatter"
        edited.text = "Saved"
        let saved = try crudRepository.save(
            edited,
            fileURL: first.fileURL,
            expectedRevision: first.sourceRevision)
        let afterSave = try crudRepository.load()
        check("save keeps the original file identity", saved.id == first.id)
        check("save updates in place without creating duplicates",
            afterSave.records.filter { $0.id == first.id }.count == 1
                && !fm.fileExists(atPath: crudRepository.snippetsDirectory.appendingPathComponent("renamed-in-frontmatter.md").path))

        let externallyRenamedURL = crudRepository.snippetsDirectory.appendingPathComponent("external-rename.md")
        try fm.moveItem(at: second.fileURL, to: externallyRenamedURL)
        let afterRename = try crudRepository.load()
        check("an external rename is modeled as delete plus create",
            !afterRename.records.contains { $0.id == second.id }
                && afterRename.records.contains { $0.id == externallyRenamedURL.path })

        try "External change".write(to: saved.fileURL, atomically: true, encoding: .utf8)
        do {
            _ = try crudRepository.save(
                saved.snippet,
                fileURL: saved.fileURL,
                expectedRevision: saved.sourceRevision)
            check("stale saves report a revision conflict", false)
        } catch SnippetRepository.RepositoryError.conflict {
            check("stale saves report a revision conflict", true)
        }
        do {
            try crudRepository.delete(
                fileURL: saved.fileURL,
                expectedRevision: saved.sourceRevision)
            check("stale deletes report a revision conflict", false)
        } catch SnippetRepository.RepositoryError.conflict {
            check("stale deletes report a revision conflict", true)
        }
        // Everything below needs the reloaded record; report the loss instead of trapping, and keep the later contracts running.
        if let currentSaved = try crudRepository.load().records.first(where: { $0.id == saved.id }) {
            try crudRepository.delete(
                fileURL: currentSaved.fileURL,
                expectedRevision: currentSaved.sourceRevision)
            check("delete removes exactly the requested file",
                !fm.fileExists(atPath: currentSaved.fileURL.path)
                    && fm.fileExists(atPath: externallyRenamedURL.path))
            do {
                _ = try crudRepository.save(
                    currentSaved.snippet,
                    fileURL: root.appendingPathComponent("outside.md"),
                    expectedRevision: currentSaved.sourceRevision)
                check("repository rejects writes outside the channel directory", false)
            } catch SnippetRepository.RepositoryError.invalidFileLocation {
                check("repository rejects writes outside the channel directory", true)
            }
            do {
                try crudRepository.delete(
                    fileURL: currentSaved.fileURL,
                    expectedRevision: currentSaved.sourceRevision)
                check("deleting an already removed file reports file not found", false)
            } catch SnippetRepository.RepositoryError.fileNotFound {
                check("deleting an already removed file reports file not found", true)
            }
        } else {
            check("delete removes exactly the requested file", false)
            check("repository rejects writes outside the channel directory", false)
            check("deleting an already removed file reports file not found", false)
        }

    }

    private static func testRepositoryConcurrency() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "tinycast-snippets-concurrency-\(UUID().uuidString)",
            isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        var initializationHeld = true
        for index in 0..<25 where initializationHeld {
            let iterationRoot = root.appendingPathComponent("init-\(index)", isDirectory: true)
            let repository = SnippetRepository(
                bundleIdentifier: "com.example.concurrent-init",
                applicationSupportRoot: iterationRoot)
            async let first = Task.detached {
                Result { try repository.create(Snippet(name: "First", text: "One")) }
            }.value
            async let second = Task.detached {
                Result { try repository.create(Snippet(name: "Second", text: "Two")) }
            }.value
            let results = await [first, second]
            let records = results.compactMap { try? $0.get() }
            initializationHeld = records.count == 2
                && records.allSatisfy { fm.fileExists(atPath: $0.fileURL.path) }
        }
        check("concurrent initialization and creates preserve both committed files",
            initializationHeld)

        let saveRoot = root.appendingPathComponent("save", isDirectory: true)
        let repository = SnippetRepository(
            bundleIdentifier: "com.example.concurrent-save",
            applicationSupportRoot: saveRoot)
        let secondRepositoryOwner = SnippetRepository(
            bundleIdentifier: "com.example.concurrent-save",
            applicationSupportRoot: saveRoot)
        let stored = try repository.create(Snippet(name: "Race", text: "Original"))
        var firstEdit = stored.snippet
        firstEdit.text = "First"
        var secondEdit = stored.snippet
        secondEdit.text = "Second"
        async let firstSave = Task.detached {
            Result { try repository.save(
                firstEdit,
                fileURL: stored.fileURL,
                expectedRevision: stored.sourceRevision) }
        }.value
        async let secondSave = Task.detached {
            Result { try secondRepositoryOwner.save(
                secondEdit,
                fileURL: stored.fileURL,
                expectedRevision: stored.sourceRevision) }
        }.value
        let saveResults = await [firstSave, secondSave]
        let successCount = saveResults.filter {
            if case .success = $0 { return true }
            return false
        }.count
        let conflictCount = saveResults.filter {
            guard case .failure(let error) = $0,
                case SnippetRepository.RepositoryError.conflict = error
            else { return false }
            return true
        }.count
        check("per-channel repository owners serialize revision validation with commit",
            successCount == 1 && conflictCount == 1)

        let physicalSupport = root.appendingPathComponent("physical-support", isDirectory: true)
        let symlinkedSupport = root.appendingPathComponent("symlinked-support", isDirectory: true)
        try fm.createDirectory(at: physicalSupport, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: symlinkedSupport, withDestinationURL: physicalSupport)
        var aliasCoordinationHeld = true
        for index in 0..<20 where aliasCoordinationHeld {
            let bundleIdentifier = "com.example.symlink-save-\(index)"
            let revalidation = RevalidationRendezvous()
            let hooks = SnippetRepository.MutationHooks(afterRevalidation: { mutation, _ in
                guard case .save = mutation else { return }
                revalidation.arriveAndWait()
            })
            let directRepository = SnippetRepository(
                bundleIdentifier: bundleIdentifier,
                applicationSupportRoot: physicalSupport,
                mutationHooks: hooks)
            let symlinkedRepository = SnippetRepository(
                bundleIdentifier: bundleIdentifier,
                applicationSupportRoot: symlinkedSupport,
                mutationHooks: hooks)
            let symlinkedRecord = try symlinkedRepository.create(
                Snippet(name: "Alias Race", text: "Original"))
            guard let directRecord = try directRepository.load().records.first(where: {
                $0.fileURL.lastPathComponent == symlinkedRecord.fileURL.lastPathComponent
            }) else {
                aliasCoordinationHeld = false
                continue
            }
            var directEdit = directRecord.snippet
            directEdit.text = "Direct \(index)"
            var symlinkedEdit = symlinkedRecord.snippet
            symlinkedEdit.text = "Symlinked \(index)"

            async let directSave = Task.detached {
                Result { try directRepository.save(
                    directEdit,
                    fileURL: directRecord.fileURL,
                    expectedRevision: directRecord.sourceRevision) }
            }.value
            async let symlinkedSave = Task.detached {
                Result { try symlinkedRepository.save(
                    symlinkedEdit,
                    fileURL: symlinkedRecord.fileURL,
                    expectedRevision: symlinkedRecord.sourceRevision) }
            }.value
            let results = await [directSave, symlinkedSave]
            let successes = results.filter {
                if case .success = $0 { return true }
                return false
            }.count
            let conflicts = results.filter {
                guard case .failure(let error) = $0,
                    case SnippetRepository.RepositoryError.conflict = error
                else { return false }
                return true
            }.count
            aliasCoordinationHeld = successes == 1 && conflicts == 1
        }
        check("direct and symlinked channel aliases share revision coordination",
            aliasCoordinationHeld)

        let boundaryRoot = root.appendingPathComponent("mutation-boundary", isDirectory: true)
        let boundaryBundle = "com.example.mutation-boundary"
        let boundaryRepository = SnippetRepository(
            bundleIdentifier: boundaryBundle,
            applicationSupportRoot: boundaryRoot)
        let boundaryRecord = try boundaryRepository.create(
            Snippet(name: "Boundary", text: "Original"))
        let racingRepository = SnippetRepository(
            bundleIdentifier: boundaryBundle,
            applicationSupportRoot: boundaryRoot,
            mutationHooks: .init(beforeRevalidation: { mutation, fileURL in
                let text = switch mutation {
                case .save: "External before save"
                case .delete: "External before delete"
                }
                try? Data(text.utf8).write(to: fileURL, options: .atomic)
            }))
        var boundaryEdit = boundaryRecord.snippet
        boundaryEdit.text = "Tinycast edit"
        do {
            _ = try racingRepository.save(
                boundaryEdit,
                fileURL: boundaryRecord.fileURL,
                expectedRevision: boundaryRecord.sourceRevision)
            check("save revalidates inside coordinated access at the mutation boundary", false)
        } catch SnippetRepository.RepositoryError.conflict {
            let content = try String(contentsOf: boundaryRecord.fileURL, encoding: .utf8)
            check("save revalidates inside coordinated access at the mutation boundary",
                content == "External before save")
        }
        if let deleteRecord = try boundaryRepository.load().records.first(where: {
            $0.id == boundaryRecord.id
        }) {
            do {
                try racingRepository.delete(
                    fileURL: deleteRecord.fileURL,
                    expectedRevision: deleteRecord.sourceRevision)
                check("delete revalidates inside coordinated access at the mutation boundary", false)
            } catch SnippetRepository.RepositoryError.conflict {
                let content = try String(contentsOf: deleteRecord.fileURL, encoding: .utf8)
                check("delete revalidates inside coordinated access at the mutation boundary",
                    fm.fileExists(atPath: deleteRecord.fileURL.path)
                        && content == "External before delete")
            }
        } else {
            check("delete revalidates inside coordinated access at the mutation boundary", false)
        }
    }

    private static func testDeliveryQueueAndPasteboard() async throws {
        let queue = SnippetDeliveryQueue()
        var order: [String] = []
        queue.enqueue(isAutomatic: false) {
            order.append("first-start")
            try? await Task.sleep(for: .milliseconds(30))
            order.append("first-end")
        }
        queue.enqueue(isAutomatic: false) {
            order.append("second")
        }
        await queue.drain()
        check("interactive deliveries are retained and serialized",
            order == ["first-start", "first-end", "second"] && queue.isIdle)

        var automaticRan = false
        queue.enqueue(isAutomatic: false) {
            try? await Task.sleep(for: .milliseconds(30))
        }
        queue.enqueue(isAutomatic: true) {
            automaticRan = true
        }
        queue.cancelAutomatic()
        await queue.drain()
        check("automatic cancellation cannot run a queued stale delivery", !automaticRan)

        var completionCount = 0
        let completion = SnippetDeliveryCompletion { completionCount += 1 }
        completion.confirm()
        completion.confirm()
        check("delivery completion invokes its callback exactly once after confirmation",
            completion.isConfirmed && completionCount == 1)

        check("unavailable AX text attributes use the event delivery fallback",
            SnippetAccessibilityReplacement.unavailable.fallsBackToEvents)
        check("a rejected AX keyword replacement fails closed instead of deleting by events",
            !SnippetAccessibilityReplacement.rejected.fallsBackToEvents)
        check("unreadable AX state accepts a posted paste after the conservative delay",
            SnippetPasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: 15,
                hadPreviousState: true,
                readStateAfterPaste: false))
        check("readable unchanged AX state is not treated as a confirmed paste",
            !SnippetPasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: 79,
                hadPreviousState: true,
                readStateAfterPaste: true))

        let backingPasteboard = NSPasteboard(
            name: .init("tinycast-snippets-tests-\(UUID().uuidString)"))
        let pasteboard = CountingPasteboard(backing: backingPasteboard)
        defer { backingPasteboard.releaseGlobally() }
        let customType = NSPasteboard.PasteboardType("com.example.custom")
        let firstItem = NSPasteboardItem()
        firstItem.setString("Original", forType: .string)
        firstItem.setData(Data([0, 1, 2, 3]), forType: customType)
        let secondType = NSPasteboard.PasteboardType("com.example.second")
        let secondItem = NSPasteboardItem()
        secondItem.setData(Data([4, 5, 6]), forType: secondType)
        check("pasteboard fixture writes multiple items and types",
            pasteboard.replaceObjects([firstItem, secondItem]))

        let lease = TemporaryPasteboardLease.begin(
            text: "Temporary",
            pasteboard: pasteboard)
        check("temporary pasteboard ownership preserves the original item shape",
            lease?.isOwned == true
                && pasteboard.string(forType: .string) == "Temporary"
                && pasteboard.pasteboardItems?.count == 2
                && pasteboard.pasteboardItems?[0].data(forType: customType)
                    == Data([0, 1, 2, 3])
                && pasteboard.pasteboardItems?[1].data(forType: secondType)
                    == Data([4, 5, 6]))
        let clearCountBeforeRestore = pasteboard.clearCount
        let writeCountBeforeRestore = pasteboard.writeCount
        let restoreResult = lease?.restoreIfOwned()
        let restoredItems = pasteboard.pasteboardItems
        check("pasteboard restoration preserves every item, type, and payload",
            restoreResult != nil
                && restoredItems?.count == 2
                && restoredItems?[0].string(forType: .string) == "Original"
                && restoredItems?[0].data(forType: customType) == Data([0, 1, 2, 3])
                && restoredItems?[1].data(forType: secondType) == Data([4, 5, 6]))
        check("pasteboard restoration does not clear before a fallible write",
            pasteboard.clearCount == clearCountBeforeRestore
                && pasteboard.writeCount == writeCountBeforeRestore)

        pasteboard.writeFailuresRemaining = 1
        var recoveredMutationCount: Int?
        let failedLease = TemporaryPasteboardLease.begin(
            text: "Temporary failure",
            pasteboard: pasteboard,
            onMutation: { recoveredMutationCount = $0 })
        check("a failed temporary write restores the original clipboard before falling back",
            failedLease == nil
                && pasteboard.string(forType: .string) == "Original"
                && pasteboard.pasteboardItems?.count == 2
                && recoveredMutationCount == pasteboard.changeCount)

        let supersededLease = TemporaryPasteboardLease.begin(
            text: "Temporary again",
            pasteboard: pasteboard)
        let newerItem = NSPasteboardItem()
        newerItem.setString("Newer copy", forType: .string)
        _ = pasteboard.replaceObjects([newerItem])
        check("pasteboard restoration never overwrites a newer copy",
            supersededLease?.restoreIfOwned() == .superseded
                && pasteboard.string(forType: .string) == "Newer copy")

        _ = pasteboard.replaceObjects([])
        check("an empty clipboard declines temporary ownership for the Unicode fallback",
            TemporaryPasteboardLease.begin(
                text: "Temporary from empty",
                pasteboard: pasteboard) == nil
                && pasteboard.pasteboardItems?.isEmpty != false)

        let imageOnlyItem = NSPasteboardItem()
        imageOnlyItem.setData(Data([9, 8, 7]), forType: .png)
        _ = pasteboard.replaceObjects([imageOnlyItem])
        check("a non-text clipboard declines temporary ownership without changing its payload",
            TemporaryPasteboardLease.begin(
                text: "Temporary over image",
                pasteboard: pasteboard) == nil
                && pasteboard.pasteboardItems?.count == 1
                && pasteboard.data(forType: .png) == Data([9, 8, 7]))
    }

    private static func testStoreWatcher() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "tinycast-snippets-watcher-\(UUID().uuidString)",
            isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let repository = SnippetRepository(
            bundleIdentifier: "com.example.watcher",
            applicationSupportRoot: root)
        let store = SnippetsStore(repository: repository)
        var snapshotCount = 0
        store.onSnapshot = { _ in snapshotCount += 1 }

        await store.start()
        check("store initialization publishes a ready snapshot",
            store.state == .ready && store.snippets.isEmpty && snapshotCount == 1)

        let externalURL = repository.snippetsDirectory.appendingPathComponent("external.md")
        try SnippetMarkdownSerializer.serialize(Snippet(name: "External", text: "One"))
            .write(to: externalURL, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500))
        check("watcher reloads an externally created file",
            store.snippets.contains { $0.id == externalURL.path && $0.snippet.text == "One" })

        try SnippetMarkdownSerializer.serialize(Snippet(name: "External", text: "Two"))
            .write(to: externalURL, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500))
        check("watcher observes atomic file replacement",
            store.record(id: externalURL.path)?.snippet.text == "Two")

        let inPlaceSource = SnippetMarkdownSerializer.serialize(
            Snippet(name: "External", text: "Three"))
        let handle = try FileHandle(forWritingTo: externalURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(inPlaceSource.utf8))
        try handle.close()
        try await Task.sleep(for: .milliseconds(500))
        check("watcher observes same-inode truncate and write",
            store.record(id: externalURL.path)?.snippet.text == "Three")

        let replacementDirectory = repository.channelDirectory.appendingPathComponent(
            ".watcher-replacement",
            isDirectory: true)
        try fm.createDirectory(at: replacementDirectory, withIntermediateDirectories: true)
        let replacementURL = replacementDirectory.appendingPathComponent("replacement.md")
        try SnippetMarkdownSerializer.serialize(Snippet(name: "Replacement", text: "Directory"))
            .write(to: replacementURL, atomically: true, encoding: .utf8)
        _ = try fm.replaceItemAt(
            repository.snippetsDirectory,
            withItemAt: replacementDirectory,
            backupItemName: nil,
            options: [])
        try await Task.sleep(for: .milliseconds(700))
        let installedReplacementURL = repository.snippetsDirectory.appendingPathComponent("replacement.md")
        check("watcher rearms after directory replacement",
            store.snippets.count == 1 && store.snippets.first?.id == installedReplacementURL.path)

        let renamedDirectory = repository.channelDirectory.appendingPathComponent(
            ".watcher-renamed-away",
            isDirectory: true)
        try fm.moveItem(at: repository.snippetsDirectory, to: renamedDirectory)
        try fm.createDirectory(at: repository.snippetsDirectory, withIntermediateDirectories: true)
        let recreatedURL = repository.snippetsDirectory.appendingPathComponent("recreated.md")
        try SnippetMarkdownSerializer.serialize(Snippet(name: "Recreated", text: "Newest"))
            .write(to: recreatedURL, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(700))
        check("watcher rearms after an explicit rename-away and recreation",
            store.snippets.count == 1
                && store.record(id: recreatedURL.path)?.snippet.text == "Newest")
        try fm.removeItem(at: renamedDirectory)

        try fm.removeItem(at: repository.snippetsDirectory)
        try await Task.sleep(for: .milliseconds(700))
        check("watcher recreates a deleted initialized directory without samples",
            store.state == .ready && store.snippets.isEmpty
                && fm.fileExists(atPath: repository.snippetsDirectory.path))
        let afterDeleteURL = repository.snippetsDirectory.appendingPathComponent("after-delete.md")
        try SnippetMarkdownSerializer.serialize(Snippet(name: "After Delete", text: "Rearmed"))
            .write(to: afterDeleteURL, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500))
        check("watcher continues after deleted-directory recovery",
            store.record(id: afterDeleteURL.path)?.snippet.text == "Rearmed")

        let beforeBurst = snapshotCount
        for index in 0..<3 {
            let fileURL = repository.snippetsDirectory.appendingPathComponent("burst-\(index).md")
            try SnippetMarkdownSerializer.serialize(
                Snippet(name: "Burst \(index)", text: "\(index)"))
                .write(to: fileURL, atomically: true, encoding: .utf8)
        }
        try await Task.sleep(for: .milliseconds(500))
        check("watcher debounces a burst into one published reload",
            snapshotCount == beforeBurst + 1
                && store.snippets.filter { $0.snippet.name.hasPrefix("Burst ") }.count == 3)

        let corruptURL = repository.snippetsDirectory.appendingPathComponent("corrupt.md")
        try "---\nname: invalid\n---\n".write(
            to: corruptURL,
            atomically: true,
            encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500))
        check("watcher publishes corrupt-file issues without dropping valid files",
            store.issues.contains { $0.fileURL.lastPathComponent == "corrupt.md" }
                && store.record(id: afterDeleteURL.path) != nil)

        store.stop()
        let stoppedSnapshotCount = snapshotCount
        store.retry()
        try SnippetMarkdownSerializer.serialize(Snippet(name: "Stopped", text: "Ignored"))
            .write(
                to: repository.snippetsDirectory.appendingPathComponent("stopped.md"),
                atomically: true,
                encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))
        check("retry after stop cannot restart loading or watchers",
            snapshotCount == stoppedSnapshotCount)
        store.stop()
    }

    private static func testTemplateExpansion() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 24, hour: 13, minute: 5))!
        let context = SnippetTemplateEngine.ExpansionContext(
            clipboard: "{date} 📋",
            selection: "{cursor} selected",
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone)

        let dateValues = record(
            "/tmp/date-values.md",
            Snippet(name: "Date Values", text: "{date}|{time}"))
        let expandedDateValues = SnippetTemplateEngine.expand(
            dateValues,
            snippets: [dateValues],
            context: context)
        check("default date and time tokens use the injected locale, calendar, and time zone",
            expandedDateValues.text == "Jul 24, 2026|1:05\u{202F}PM")

        let values = record(
            "/tmp/values.md",
            Snippet(
                name: "Values",
                text: "C:{clipboard}|S:{selection}|D:{date format=\"yyyy-MM-dd HH:mm\"}|{argument name=\"First\"}|{argument}|{argument name=\"First\"}"))
        let missing = SnippetTemplateEngine.expand(values, snippets: [values], context: context)
        check("missing arguments are unique and ordered by appearance", missing.missingArguments.map(\.name) == ["First", "Argument"])
        check("missing argument tokens stay visible until values are supplied", missing.text.hasSuffix("{argument name=\"First\"}|{argument}|{argument name=\"First\"}"))

        let expandedValues = SnippetTemplateEngine.expand(
            values,
            snippets: [values],
            context: context,
            userArguments: ["First": "{clipboard}", "Argument": "{cursor}"])
        check("clipboard, selection, and arguments insert token-shaped text literally", expandedValues.text == "C:{date} 📋|S:{cursor} selected|D:2026-07-24 13:05|{clipboard}|{cursor}|{clipboard}")
        check("injected cursor-shaped text does not set cursor position", expandedValues.cursorOffsetFromEnd == nil)
        check("all supplied arguments clear the missing list", expandedValues.missingArguments.isEmpty)

        let literalBraces = record(
            "/tmp/literal-braces.md",
            Snippet(name: "Literal Braces", text: "{\"generated\":\"{date}\"}|struct { value: {time} }"))
        let literalBraceResult = SnippetTemplateEngine.expand(
            literalBraces,
            snippets: [literalBraces],
            context: context)
        check("literal JSON and code braces do not mask nested valid tokens",
            literalBraceResult.text == "{\"generated\":\"Jul 24, 2026\"}|struct { value: 1:05\u{202F}PM }")

        let promptContextSnippet = record(
            "/tmp/prompt-context.md",
            Snippet(name: "Prompt Context", text: "{clipboard}|{selection}|{date format=\"HH:mm\"}|{argument name=\"Value\"}"))
        let beforePrompt = SnippetTemplateEngine.expand(
            promptContextSnippet,
            snippets: [promptContextSnippet],
            context: context)
        let afterPrompt = SnippetTemplateEngine.expand(
            promptContextSnippet,
            snippets: [promptContextSnippet],
            context: context,
            userArguments: ["Value": "Done"])
        check("argument prompts reuse the captured expansion context",
            beforePrompt.text.replacingOccurrences(
                of: "{argument name=\"Value\"}",
                with: "Done") == afterPrompt.text)

        let duplicateZ = record("/tmp/z-child.md", Snippet(name: "Child", text: "Z"))
        let duplicateA = record("/tmp/a-child.md", Snippet(name: "Child", text: "A", keyword: "!CHILD"))
        let keywordTarget = record("/tmp/keyword.md", Snippet(name: "Other", text: "K", keyword: "!Key"))
        let references = record(
            "/tmp/references.md",
            Snippet(name: "References", text: "{snippet:cHiLd}|{snippet:!kEy}|{snippet:missing}"))
        let referenced = SnippetTemplateEngine.expand(
            references,
            snippets: [duplicateZ, keywordTarget, references, duplicateA],
            context: context)
        check("duplicate name references resolve by stable path identity", referenced.text == "A|K|{snippet:missing}")
        check("name and keyword references are case-insensitive", referenced.text.hasPrefix("A|K|"))
        check("missing references remain visible", referenced.text.hasSuffix("{snippet:missing}"))

        let disabledChild = record(
            "/tmp/disabled-child.md",
            Snippet(name: "Disabled", text: "Secret", keyword: "!disabled", isEnabled: false))
        let disabledReferences = record(
            "/tmp/disabled-references.md",
            Snippet(name: "Disabled References", text: "{snippet:Disabled}|{snippet:!disabled}"))
        let disabledResult = SnippetTemplateEngine.expand(
            disabledReferences,
            snippets: [disabledChild, disabledReferences],
            context: context)
        check("a disabled snippet cannot be expanded by name or keyword reference",
            disabledResult.text == "{snippet:Disabled}|{snippet:!disabled}")

        let cursorChild = record(
            "/tmp/cursor-child.md",
            Snippet(name: "Cursor Child", text: "👨‍👩‍👧‍👦{cursor}é{cursor}"))
        let cursorRoot = record(
            "/tmp/cursor-root.md",
            Snippet(name: "Cursor Root", text: "🙂{snippet:Cursor Child}終{cursor}"))
        let cursorResult = SnippetTemplateEngine.expand(
            cursorRoot,
            snippets: [cursorRoot, cursorChild],
            context: context)
        check("all cursor tokens are removed from final text", cursorResult.text == "🙂👨‍👩‍👧‍👦é終")
        check("first final cursor includes nested cursors", cursorResult.cursorOffsetFromEnd == 2)

        let nestedArguments = record(
            "/tmp/nested-arguments.md",
            Snippet(name: "Nested Arguments", text: "{argument name=\"Nested\"}|{argument name=\"Root\"}"))
        let argumentRoot = record(
            "/tmp/argument-root.md",
            Snippet(name: "Argument Root", text: "{argument name=\"Root\"}|{snippet:Nested Arguments}|{argument name=\"Last\"}"))
        let argumentResult = SnippetTemplateEngine.expand(
            argumentRoot,
            snippets: [argumentRoot, nestedArguments],
            context: context)
        check("nested arguments follow final appearance order", argumentResult.missingArguments.map(\.name) == ["Root", "Nested", "Last"])

        let cycleA = record("/tmp/cycle-a.md", Snippet(name: "A", text: "{snippet:B}"))
        let cycleB = record("/tmp/cycle-b.md", Snippet(name: "B", text: "{snippet:A}"))
        let cycleResult = SnippetTemplateEngine.expand(cycleA, snippets: [cycleA, cycleB], context: context)
        check("cycles are detected with stable record IDs and remain visible", cycleResult.text == "{snippet:A}")

        let depthRecords = (0...6).map { index in
            record(
                "/tmp/depth-\(index).md",
                Snippet(name: "S\(index)", text: index == 6 ? "End" : "{snippet:S\(index + 1)}"))
        }
        let depthResult = SnippetTemplateEngine.expand(
            depthRecords[0],
            snippets: depthRecords,
            context: context)
        check("reference depth limit leaves the unexpanded token visible", depthResult.text == "{snippet:S6}")
    }

    /// The Raycast-compatible placeholder set: every token, parameter and modifier, against an injected clock, locale, clipboard history and UUID source.
    private static func testDynamicPlaceholders() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 24, hour: 13, minute: 5))!
        let uuids = UUIDSequence()
        let context = SnippetTemplateEngine.ExpansionContext(
            clipboardHistory: ["  newest  ", "older", "oldest"],
            selection: "picked",
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            makeUUID: { uuids.next() })

        func expand(_ text: String, arguments: [String: String] = [:]) -> SnippetTemplateEngine
            .ExpansionResult
        {
            let subject = record("/tmp/placeholders.md", Snippet(name: "Subject", text: text))
            return SnippetTemplateEngine.expand(
                subject, snippets: [subject], context: context, userArguments: arguments)
        }

        // New date/time tokens.
        check("datetime combines the date and time styles",
            expand("{datetime}").text == "Jul 24, 2026 at 1:05\u{202F}PM")
        check("day renders the weekday name", expand("{day}").text == "Friday")

        // Offsets: signed, multi-unit, and every documented unit.
        check("a single signed offset shifts the date",
            expand("{date offset=\"+1d\"}").text == "Jul 25, 2026")
        check("offsets accept a bare unquoted value", expand("{day offset=-3d}").text == "Tuesday")
        check("multiple offsets apply in order",
            expand("{date offset=\"+2y +5M\"}").text == "Dec 24, 2028")
        check("minute and hour offsets shift the time",
            expand("{time offset=\"+3h +30m\"}").text == "4:35\u{202F}PM")
        check("an unknown offset unit leaves the token literal",
            expand("{date offset=\"+1w\"}").text == "{date offset=\"+1w\"}")
        check("an offset without an amount leaves the token literal",
            expand("{date offset=\"d\"}").text == "{date offset=\"d\"}")

        // Locale and format.
        check("locale overrides the context locale",
            expand("{date locale=\"fr-FR\"}").text == "24 juil. 2026")
        check("format and locale together are rejected as ambiguous",
            expand("{date format=\"yyyy\" locale=\"fr-FR\"}").text
                == "{date format=\"yyyy\" locale=\"fr-FR\"}")
        check("format still applies with an offset",
            expand("{date offset=\"-1d\" format=\"yyyy-MM-dd\"}").text == "2026-07-23")

        // UUID comes from the injected source, once per token.
        check("each uuid token draws a fresh value", expand("{uuid}|{uuid}").text == "uuid-1|uuid-2")

        // Clipboard history.
        check("clipboard offset zero is the current clipboard",
            expand("{clipboard}").text == "  newest  ")
        check("clipboard offset reaches back through history",
            expand("{clipboard offset=1}|{clipboard offset=2}").text == "older|oldest")
        check("a clipboard offset past the end expands to nothing",
            expand("{clipboard offset=9}").text.isEmpty)
        check("a negative clipboard offset leaves the token literal",
            expand("{clipboard offset=-1}").text == "{clipboard offset=-1}")

        // Modifier pipeline.
        check("uppercase and lowercase modifiers apply",
            expand("{selection | uppercase}|{selection | lowercase}").text == "PICKED|picked")
        check("trim strips surrounding whitespace", expand("{clipboard | trim}").text == "newest")
        check("modifiers chain left to right",
            expand("{clipboard | trim | uppercase}").text == "NEWEST")
        check("percent-encode escapes everything outside the unreserved set",
            expand("{argument name=\"U\" | percent-encode}", arguments: ["U": "a b/c?d&e=f~g-h"]).text
                == "a%20b%2Fc%3Fd%26e%3Df~g-h")
        check("json-stringify escapes without adding quotes",
            expand("{argument name=\"J\" | json-stringify}", arguments: ["J": "a\"b\\c\nd"]).text
                == "a\\\"b\\\\c\\nd")
        check("raw is accepted and changes nothing",
            expand("{clipboard | raw}").text == "  newest  ")
        check("an unknown modifier leaves the token literal",
            expand("{clipboard | shout}").text == "{clipboard | shout}")
        check("a modifier on a structural token leaves it literal",
            expand("{cursor | uppercase}").text == "{cursor | uppercase}")
        check("a pipe inside a quoted value is not a modifier separator",
            expand("{date format=\"yyyy|MM\"}").text == "2026|07")

        // Arguments: defaults and options.
        let defaulted = expand("{argument name=\"Tone\" default=\"happy\"}")
        check("an argument default expands without prompting",
            defaulted.text == "happy" && defaulted.missingArguments.isEmpty)
        check("a supplied value beats the default",
            expand("{argument name=\"Tone\" default=\"happy\"}", arguments: ["Tone": "sad"]).text
                == "sad")
        let optioned = expand("{argument name=\"Tone\" options=\"happy, sad, professional\"}")
        check("options travel with the missing argument",
            optioned.missingArguments == [
                .init(name: "Tone", options: ["happy", "sad", "professional"])
            ])
        check("an empty options list leaves the token literal",
            expand("{argument name=\"Tone\" options=\", \"}").text
                == "{argument name=\"Tone\" options=\", \"}")

        // Raycast's snippet spelling resolves like Tinycast's.
        let child = record("/tmp/ph-child.md", Snippet(name: "Child", text: "nested"))
        let byName = record("/tmp/ph-name.md", Snippet(name: "ByName", text: "{snippet name=\"Child\"}"))
        let byColon = record("/tmp/ph-colon.md", Snippet(name: "ByColon", text: "{snippet:Child}"))
        let pool = [child, byName, byColon]
        check("snippet name= resolves identically to snippet:",
            SnippetTemplateEngine.expand(byName, snippets: pool, context: context).text == "nested"
                && SnippetTemplateEngine.expand(byColon, snippets: pool, context: context).text
                    == "nested")
        let disabledChild = record(
            "/tmp/ph-disabled.md", Snippet(name: "Off", text: "secret", isEnabled: false))
        let referencesDisabled = record(
            "/tmp/ph-ref-off.md", Snippet(name: "Ref", text: "{snippet name=\"Off\"}"))
        check("snippet name= cannot reach a disabled snippet",
            SnippetTemplateEngine.expand(
                referencesDisabled,
                snippets: [disabledChild, referencesDisabled],
                context: context
            ).text == "{snippet name=\"Off\"}")

        // Malformed tokens stay literal rather than vanishing.
        check("an unknown placeholder stays literal", expand("{weather}").text == "{weather}")
        check("an unknown parameter leaves the token literal",
            expand("{date style=\"long\"}").text == "{date style=\"long\"}")
        check("a duplicated parameter leaves the token literal",
            expand("{date offset=\"+1d\" offset=\"+2d\"}").text
                == "{date offset=\"+1d\" offset=\"+2d\"}")
        check("an unterminated quote leaves the token literal",
            expand("{date format=\"yyyy}").text == "{date format=\"yyyy}")
        check("a parameter on a token that takes none leaves it literal",
            expand("{uuid offset=1}").text == "{uuid offset=1}")
        check("an empty clipboard history expands the clipboard to nothing",
            SnippetTemplateEngine.expand(
                record("/tmp/ph-empty.md", Snippet(name: "E", text: "[{clipboard}]")),
                snippets: [],
                context: SnippetTemplateEngine.ExpansionContext(
                    clipboardHistory: [],
                    selection: "",
                    now: now,
                    calendar: calendar,
                    locale: Locale(identifier: "en_US_POSIX"),
                    timeZone: timeZone)
            ).text == "[]")
    }

    private static func testKeywordPolicy() {
        let base = Date(timeIntervalSince1970: 1_000)
        var policy = SnippetKeywordPolicy(keywords: [
            .init(snippetID: "/tmp/short.md", value: "bc"),
            .init(snippetID: "/tmp/long.md", value: "abc"),
            .init(snippetID: "/tmp/z-duplicate.md", value: "!dup"),
            .init(snippetID: "/tmp/a-duplicate.md", value: "!DUP"),
            .init(snippetID: "/tmp/trimmed.md", value: "  !trim  "),
            .init(
                snippetID: "/tmp/too-long.md",
                value: String(repeating: "x", count: SnippetKeywordPolicy.maximumBufferLength + 1)),
        ])

        let longest = policy.process(.text("abc"), at: base)
        check("keyword matching prefers the longest suffix", longest?.snippetID == "/tmp/long.md")
        let duplicate = policy.process(.text("!DuP"), at: base.addingTimeInterval(1))
        check("duplicate keywords resolve by stable snippet identity",
            duplicate?.snippetID == "/tmp/a-duplicate.md")
        let trimmed = policy.process(.text("!trim"), at: base.addingTimeInterval(1.5))
        check("keyword matching trims surrounding whitespace and deletes only the trigger",
            trimmed == .init(
                snippetID: "/tmp/trimmed.md",
                keyword: "!trim",
                deletionCount: 5))
        check("keywords longer than the buffer cap are excluded",
            !policy.keywords.contains { $0.snippetID == "/tmp/too-long.md" })

        let syntheticInput = SnippetKeywordPolicy.classifyInput(
            text: "p",
            isSynthetic: true,
            secureEventInputEnabled: false,
            isFlagsChanged: false,
            isKeyDown: true,
            hasCommandOrControl: false,
            isResetKey: false,
            isDeleteBackward: false)
        check("synthetic Tinycast events are classified as ignored", syntheticInput == .ignored)
        _ = policy.process(.text("!du"), at: base.addingTimeInterval(2))
        _ = policy.process(syntheticInput, at: base.addingTimeInterval(2.5))
        let afterSynthetic = policy.process(.text("p"), at: base.addingTimeInterval(3))
        check("ignored synthetic events do not alter the keyword buffer",
            afterSynthetic?.snippetID == "/tmp/a-duplicate.md")

        let secureInput = SnippetKeywordPolicy.classifyInput(
            text: "x",
            isSynthetic: false,
            secureEventInputEnabled: true,
            isFlagsChanged: false,
            isKeyDown: true,
            hasCommandOrControl: false,
            isResetKey: false,
            isDeleteBackward: false)
        check("Secure Event Input classifies keystrokes as a buffer reset", secureInput == .reset)
        let modifiedInput = SnippetKeywordPolicy.classifyInput(
            text: "x",
            isSynthetic: false,
            secureEventInputEnabled: false,
            isFlagsChanged: false,
            isKeyDown: true,
            hasCommandOrControl: true,
            isResetKey: false,
            isDeleteBackward: false)
        check("command and control shortcuts classify as buffer resets", modifiedInput == .reset)

        let shiftTransition = SnippetKeywordPolicy.classifyInput(
            text: nil,
            isSynthetic: false,
            secureEventInputEnabled: false,
            isFlagsChanged: true,
            isKeyDown: false,
            hasCommandOrControl: false,
            isResetKey: false,
            isDeleteBackward: false)
        var shiftedKeywordPolicy = SnippetKeywordPolicy(keywords: [
            .init(snippetID: "/tmp/notes.md", value: "!notes")
        ])
        _ = shiftedKeywordPolicy.process(.text("!"), at: base.addingTimeInterval(10))
        _ = shiftedKeywordPolicy.process(shiftTransition, at: base.addingTimeInterval(10.1))
        let shiftedKeywordMatch = shiftedKeywordPolicy.process(
            .text("notes"),
            at: base.addingTimeInterval(10.2))
        check("Shift and Option flag transitions preserve modifier-produced keywords",
            shiftTransition == .ignored
                && shiftedKeywordMatch?.snippetID == "/tmp/notes.md")

        _ = policy.process(.text("a"), at: base.addingTimeInterval(40))
        let afterTimeout = policy.process(.text("bc"), at: base.addingTimeInterval(56))
        check("keyword buffer resets after the inactivity timeout", afterTimeout?.snippetID == "/tmp/short.md")

        _ = policy.process(.text("!dux"), at: base.addingTimeInterval(60))
        _ = policy.process(.deleteBackward, at: base.addingTimeInterval(61))
        let afterDelete = policy.process(.text("p"), at: base.addingTimeInterval(62))
        check("backspace updates the buffered suffix deterministically",
            afterDelete?.snippetID == "/tmp/a-duplicate.md")

        _ = policy.process(
            .text(String(repeating: "x", count: SnippetKeywordPolicy.maximumBufferLength + 20)),
            at: base.addingTimeInterval(70))
        check("keyword buffer is capped", policy.buffer.count == SnippetKeywordPolicy.maximumBufferLength)
        _ = policy.process(.reset, at: base.addingTimeInterval(71))
        check("navigation and session resets clear the complete buffer", policy.buffer.isEmpty)

    }

    private static func testKeywordLifecycle() {
        typealias Lifecycle = SnippetKeywordLifecyclePolicy

        let consentOff = Lifecycle.decide(
            isRequested: false,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .absent)
        check("listener remains off without consent",
            consentOff == .init(status: .off, tapAction: .none))

        let stopWithTap = Lifecycle.decide(
            isRequested: false,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .active)
        check("stop tears down an installed tap synchronously",
            stopWithTap == .init(status: .off, tapAction: .tearDown))

        let waiting = Lifecycle.decide(
            isRequested: true,
            isSessionActive: true,
            hasAccessibility: false,
            tapState: .absent)
        check("consent waits without the Accessibility grant and does not install a tap",
            waiting == .init(status: .needsAccessibility, tapAction: .none))

        let grantsArrived = Lifecycle.decide(
            isRequested: true,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .absent)
        check("a later health check installs the tap after the grant arrives",
            grantsArrived == .init(status: .needsAccessibility, tapAction: .install))
        let retryAfterFailure = Lifecycle.decide(
            isRequested: true,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .absent)
        check("tap creation failure remains retryable on the next health check",
            grantsArrived.tapAction == .install && retryAfterFailure.tapAction == .install)

        let active = Lifecycle.decide(
            isRequested: true,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .active)
        check("listener reports active only with the grant and a live tap",
            active == .init(status: .active, tapAction: .none))
        check("repeated start is idempotent when the tap is already active",
            Lifecycle.decide(
                isRequested: true,
                isSessionActive: true,
                hasAccessibility: true,
                tapState: .active) == active)

        let revoked = Lifecycle.decide(
            isRequested: true,
            isSessionActive: true,
            hasAccessibility: false,
            tapState: .active)
        check("permission revocation moves to waiting and tears down the tap",
            revoked == .init(status: .needsAccessibility, tapAction: .tearDown))

        let disabled = Lifecycle.decide(
            isRequested: true,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .disabled)
        check("a disabled tap is re-enabled before the listener can be active",
            disabled == .init(status: .needsAccessibility, tapAction: .reenable))

        let inactiveSession = Lifecycle.decide(
            isRequested: true,
            isSessionActive: false,
            hasAccessibility: true,
            tapState: .active)
        check("session resignation tears down the tap and leaves consent waiting",
            inactiveSession == .init(status: .needsAccessibility, tapAction: .tearDown))

        let rapidOff = Lifecycle.decide(
            isRequested: false,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .active)
        let rapidOn = Lifecycle.decide(
            isRequested: true,
            isSessionActive: true,
            hasAccessibility: true,
            tapState: .absent)
        check("rapid off then on cannot preserve a stale active tap",
            rapidOff.tapAction == .tearDown
                && rapidOff.status == .off
                && rapidOn.tapAction == .install
                && rapidOn.status == .needsAccessibility)
    }

    private static func testKeywordListenerLifecycle() {
        let permissions = FakeSnippetPermissions()
        let tap = FakeSnippetKeywordTapController()
        tap.installFailuresRemaining = 1
        let listener = SnippetKeywordListener(
            tapController: tap,
            accessibilityTrusted: { permissions.accessibility },
            secureEventInputEnabled: { false },
            now: { Date(timeIntervalSince1970: 1_000) },
            syntheticEventTag: 123,
            logsTapFailures: false)

        listener.start { _, _, _, _ in }
        check("real listener waits without permissions and does not install",
            listener.status == .needsAccessibility && tap.installCount == 0)

        permissions.accessibility = true
        listener.healthCheck()
        check("real listener keeps a failed tap installation retryable",
            listener.status == .needsAccessibility
                && tap.installCount == 1
                && tap.state == .absent)
        listener.healthCheck()
        check("real listener applies installation after grants arrive",
            listener.status == .active
                && tap.installCount == 2
                && tap.state == .active)

        listener.start { _, _, _, _ in }
        check("real listener repeated start does not install a second tap",
            listener.status == .active && tap.installCount == 2)

        tap.state = .disabled
        listener.healthCheck()
        check("real listener applies tap re-enable and returns active",
            listener.status == .active
                && tap.reenableCount == 1
                && tap.state == .active)

        tap.reenableSucceeds = false
        tap.state = .disabled
        listener.healthCheck()
        check("real listener recreates a tap when re-enable fails",
            listener.status == .active
                && tap.tearDownCount >= 1
                && tap.installCount == 3)
        tap.reenableSucceeds = true

        permissions.accessibility = false
        listener.healthCheck()
        check("real listener tears down synchronously on permission revocation",
            listener.status == .needsAccessibility && tap.state == .absent)

        permissions.accessibility = true
        listener.healthCheck()
        check("real listener reinstalls after permission regrant",
            listener.status == .active && tap.state == .active)

        listener.stop()
        check("real listener stop is authoritative",
            listener.status == .off && tap.state == .absent)
        listener.start { _, _, _, _ in }
        listener.stop()
        check("real listener rapid on and off leaves no tap",
            listener.status == .off && tap.state == .absent)
    }

    private static func record(_ path: String, _ snippet: Snippet) -> StoredSnippet {
        let source = SnippetMarkdownSerializer.serialize(snippet)
        return StoredSnippet(
            fileURL: URL(fileURLWithPath: path),
            snippet: snippet,
            sourceRevision: SnippetSourceRevision(content: source))
    }

    private static func expectParseError(_ description: String, content: String, fileURL: URL) {
        do {
            _ = try SnippetMarkdownSerializer.parse(content: content, fileURL: fileURL)
            check(description, false)
        } catch let error as SnippetMarkdownSerializer.ParseError {
            check(description, error.localizedDescription.contains(fileURL.path))
        } catch {
            check(description, false)
        }
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
            passes += 1
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}

private final class RevalidationRendezvous: @unchecked Sendable {
    private let condition = NSCondition()
    private var arrivals = 0

    func arriveAndWait() {
        condition.lock()
        arrivals += 1
        if arrivals == 2 {
            condition.broadcast()
        } else {
            let deadline = Date().addingTimeInterval(0.25)
            while arrivals < 2, condition.wait(until: deadline) {}
        }
        condition.unlock()
    }
}

@MainActor
private final class CountingPasteboard: SnippetPasteboardAccess {
    let backing: NSPasteboard
    private(set) var clearCount = 0
    private(set) var writeCount = 0
    var writeFailuresRemaining = 0

    init(backing: NSPasteboard) {
        self.backing = backing
    }

    var changeCount: Int { backing.changeCount }
    var pasteboardItems: [NSPasteboardItem]? { backing.pasteboardItems }

    @discardableResult
    func clearContents() -> Int {
        clearCount += 1
        return backing.clearContents()
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        writeCount += 1
        if writeFailuresRemaining > 0 {
            writeFailuresRemaining -= 1
            return false
        }
        return backing.writeObjects(objects)
    }

    func replaceObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        clearContents()
        return objects.isEmpty || writeObjects(objects)
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        backing.string(forType: type)
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        backing.data(forType: type)
    }
}

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    func prepareForTinycastPasteboardMutation() {}
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {}
}

@MainActor
final class AppSettings {
    var snippetsEnabled = false
}

enum Permissions {
    static func ensureAccessibility() -> Bool { false }
    static func isAccessibilityTrusted() -> Bool { false }
}

enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
    @MainActor static func postCommandV(toPid pid: pid_t? = nil) {}
}

/// Deterministic `{uuid}` source. `@unchecked Sendable` with a lock because `makeUUID` is a `@Sendable` closure.
private final class UUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return "uuid-\(count)"
    }
}

@MainActor
private final class FakeSnippetPermissions {
    var accessibility = false
}

@MainActor
private final class FakeSnippetKeywordTapController: SnippetKeywordTapControlling {
    var state: SnippetKeywordLifecyclePolicy.TapState = .absent
    var installFailuresRemaining = 0
    var reenableSucceeds = true
    private(set) var installCount = 0
    private(set) var reenableCount = 0
    private(set) var tearDownCount = 0

    func install(listener: SnippetKeywordListener) -> Bool {
        installCount += 1
        if installFailuresRemaining > 0 {
            installFailuresRemaining -= 1
            state = .absent
            return false
        }
        state = .active
        return true
    }

    func reenable() -> Bool {
        reenableCount += 1
        state = reenableSucceeds ? .active : .disabled
        return reenableSucceeds
    }

    func tearDown() {
        tearDownCount += 1
        state = .absent
    }
}
