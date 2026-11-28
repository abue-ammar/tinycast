import Foundation
import Observation
import Testing

@testable import Tinycast

@MainActor
struct ClipboardTests {
    @MainActor
    private struct History {
        private let scratch: ScratchDirectory
        let directory: URL
        let store: ClipboardStore

        init(opensDatabase: Bool = true) throws {
            scratch = try ScratchDirectory("clipboard")
            directory = scratch.url.appending(path: "history")
            store = ClipboardStore(directory: directory, opensDatabase: opensDatabase)
        }

        func add(_ strings: String...) {
            for text in strings { store.addText(text, sourceBundleID: nil) }
        }

        func row(_ text: String) throws -> ClipboardItem {
            try #require(store.items.first { $0.text == text })
        }

        func pin(_ strings: String...) throws {
            for text in strings { store.togglePinned(try row(text)) }
        }
    }

    @Test func constructingAClosedStoreDoesNotTouchItsDirectoryUntilExplicitOpen() throws {
        let history = try History(opensDatabase: false)
        #expect(!FileManager.default.fileExists(atPath: history.directory.path))

        history.store.open()

        #expect(FileManager.default.fileExists(atPath: history.store.dbURL.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func clearAndCloseRetireImageCapturesWhileAFreshCapturePersists() async throws {
        let history = try History()
        let store = history.store
        let data = Data("captured image".utf8)

        let beforeClear = store.captureGeneration
        store.clearAll()
        store.addImage(data, sourceBundleID: nil, capture: beforeClear)
        let beforeClose = store.captureGeneration
        store.close()
        store.open()
        store.addImage(data, sourceBundleID: nil, capture: beforeClose)
        #expect(store.items.isEmpty)
        let blobs = try FileManager.default.contentsOfDirectory(atPath: store.imagesDir.path)
        #expect(blobs.isEmpty)

        store.addImage(data, sourceBundleID: nil, capture: store.captureGeneration)
        store.clearAll()
        let counts = Observations { store.items.count }
        store.addImage(data, sourceBundleID: nil, capture: store.captureGeneration)
        for await count in counts where count > 0 { break }
        try Task.checkCancellation()
        #expect(store.items.count == 1)
        let reopened = ClipboardStore(directory: history.directory)
        reopened.load()
        #expect(reopened.items.count == 1)
    }

    @Test func pinningAppendsToThePinnedSectionInPinOrder() throws {
        let history = try History()
        history.add("oldest", "middle", "newest")

        try history.pin("oldest")
        #expect(texts(in: history.store) == ["oldest", "newest", "middle"])
        try history.pin("middle")
        #expect(texts(in: history.store) == ["oldest", "middle", "newest"])
        try history.pin("newest")
        #expect(texts(in: history.store) == ["oldest", "middle", "newest"])
    }

    @Test func unpinningClearsThePinAndMakesTheRowMostRecent() throws {
        let history = try History()
        history.add("a", "b", "c")
        let original = try history.row("a")

        try history.pin("a", "a")

        #expect(texts(in: history.store) == ["a", "c", "b"])
        let unpinned = try history.row("a")
        #expect(!unpinned.isPinned)
        #expect(unpinned.createdAt > original.createdAt)
    }

    @Test func promotionKeepsPinnedRowsInPlaceAndMovesUnpinnedRows() throws {
        let history = try History()
        let store = history.store
        history.add("one", "two")
        try history.pin("one", "two")
        let pinned = try history.row("one")

        store.promote(pinned)
        #expect(texts(in: store) == ["one", "two"])
        let promoted = try history.row("one")
        #expect(promoted.createdAt == pinned.createdAt)

        history.add("three", "four")
        store.promote(try history.row("three"))
        #expect(texts(in: store) == ["one", "two", "three", "four"])
    }

    @Test func editingPreservesIdentityOrderAndPinAndUpdatesSearchAndStorage() throws {
        let history = try History()
        let store = history.store
        history.add("first draft", "pinned draft", "newest")
        try history.pin("pinned draft")
        let original = try history.row("first draft")

        let edited = try #require(try store.updateText("final copy", of: original))

        #expect(edited.id == original.id)
        #expect(texts(in: store) == ["pinned draft", "newest", "final copy"])
        #expect(store.search("draft", filter: .all).compactMap(\.text) == ["pinned draft"])
        #expect(store.search("final", filter: .all).map(\.id) == [original.id])

        _ = try store.updateText("pinned final", of: history.row("pinned draft"))
        let pinned = try history.row("pinned final")
        #expect(pinned.isPinned)

        let reopened = ClipboardStore(directory: history.directory)
        reopened.load()
        #expect(texts(in: reopened) == ["pinned final", "newest", "final copy"])
    }

    @Test func aDeletedRowCannotBeEditedBackIntoHistory() throws {
        let history = try History()
        history.add("first draft", "pinned draft", "newest")
        try history.pin("pinned draft")
        let deleted = try history.row("newest")
        history.store.remove(deleted)

        #expect(try history.store.updateText("ghost", of: deleted) == nil)
        #expect(!texts(in: history.store).contains("ghost"))
    }

    @Test func imageRowsCannotBeEditedAsText() throws {
        let history = try History()
        let image = ClipboardItem(imagePath: "/tmp/shot.png", sourceBundleID: nil)
        #expect(try history.store.updateText("caption", of: image) == nil)
    }

    @Test func editingHonorsTheCaptureLimitAndLeavesTheRowOnRejection() throws {
        let history = try History()
        history.add("short")
        let longest = String(repeating: "a", count: ClipboardStore.maxTextLength)
        let short = try history.row("short")
        #expect(try history.store.updateText(longest, of: short) != nil)
        let saved = try history.row(longest)

        #expect(throws: ClipboardStore.UpdateError.tooLong) {
            try history.store.updateText(longest + "a", of: saved)
        }
        #expect(texts(in: history.store) == [longest])
    }

    @Test func editingOutsideTheResidentWindowUpdatesTheSearchMemo() throws {
        let history = try History()
        let store = history.store
        store.importEntries(numberedEntries(count: 1200))
        let oldest = try #require(store.search("entry 0", filter: .all).first)
        #expect(!store.items.contains { $0.id == oldest.id })

        _ = try store.updateText("renamed oldest", of: oldest)

        #expect(store.search("entry 0", filter: .all).isEmpty)
        #expect(store.search("renamed", filter: .all).map(\.id) == [oldest.id])
    }

    @Test func retentionSparesOlderPinsInMemoryAndOnReopen() throws {
        let history = try History()
        let store = history.store
        let old = Date().addingTimeInterval(-2 * 86_400)
        store.importEntries([
            textEntry("ancient-pinned", at: old), textEntry("ancient-loose", at: old + 1),
            textEntry("fresh", at: .now)
        ])
        try history.pin("ancient-pinned")

        store.maxAge = 86_400
        store.enforceLimits()

        #expect(Set(texts(in: store)) == ["ancient-pinned", "fresh"])
        let reopened = ClipboardStore(directory: history.directory)
        reopened.maxAge = 86_400
        reopened.load()
        #expect(Set(texts(in: reopened)) == ["ancient-pinned", "fresh"])
    }

    @Test func aPinnedMatchLeadsEvenWhenTheFullTextLimitWouldMissIt() throws {
        let history = try History()
        let store = history.store
        let base = Date().addingTimeInterval(-10_000)
        store.importEntries(
            [textEntry("needle in the haystack", at: base)]
                + (1...259).map {
                    textEntry("haystack filler \($0)", at: base + Double($0))
                })
        try history.pin("needle in the haystack")

        let results = store.search("haystack", filter: .all)
        #expect(results.count > 200)
        #expect(results.first?.text == "needle in the haystack")
        #expect(results.filter(\.isPinned).count == 1)
        #expect(store.search("ne", filter: .all).first?.text == "needle in the haystack")
    }

    @Test(arguments: [
        (0, "", ClipboardFilter.all, "alpha one" as String?), (2, "", .all, "beta three"),
        (3, "", .all, nil), (0, "beta", .all, "beta two"), (1, "beta", .all, "beta three"),
        (2, "beta", .all, nil), (0, "", .link, nil)
    ])
    func pinnedSlotsCountOnlyVisiblePins(
        _ index: Int, _ query: String, _ filter: ClipboardFilter, _ text: String?
    )
        throws
    {
        let history = try History()
        history.add("alpha one", "beta two", "beta three", "plain text")
        try history.pin("alpha one", "beta two", "beta three")

        let row = history.store.pinnedItem(at: index, in: query, filter: filter)
        #expect(row?.text == text)
        #expect((row == nil) == (text == nil))
    }

    @Test(arguments: [
        (false, "", ClipboardFilter.all, 0), (true, "", .all, 2), (true, "  ", .all, 2),
        (true, "beta", .all, 0), (true, "", .text, 2), (true, "", .link, 0)
    ])
    func landingSkipsVisiblePinsForAnEmptyQuery(
        _ hasPins: Bool, _ query: String, _ filter: ClipboardFilter, _ expected: Int
    ) throws {
        let history = try History()
        history.add("alpha one", "beta two", "https://example.com", "beta three")
        if hasPins { try history.pin("alpha one", "beta two") }

        let index = history.store.landingIndex(in: query, filter: filter)
        #expect(index == expected)
        if hasPins, query.isEmpty, filter == .all {
            let row = try #require(history.store.search(query, filter: filter).dropFirst(index).first)
            #expect(row.text == "beta three")
        }
    }

    @Test func anAllPinnedHistoryLandsOnItsFirstRow() throws {
        let history = try History()
        history.add("alpha one", "beta two", "https://example.com", "beta three")
        try history.pin("alpha one", "beta two", "https://example.com", "beta three")
        #expect(history.store.landingIndex(in: "", filter: .all) == 0)
    }

    @Test(arguments: [
        (
            ClipboardFilter.all,
            [
                "rgb(0 255 0 / 0.5)", "#FF5733", "second.link.dev",
                "hi@apple.com", "https://apple.com", "just some prose"
            ]
        ),
        (.text, ["just some prose"]), (.color, ["rgb(0 255 0 / 0.5)", "#FF5733"]),
        (.link, ["second.link.dev", "https://apple.com"]), (.email, ["hi@apple.com"]), (.image, [])
    ])
    func typeFiltersSeparateHistoryInRecencyOrder(_ filter: ClipboardFilter, _ expected: [String]) throws {
        let history = try typedHistory()
        #expect(texts(in: history.store, filter: filter) == expected)
    }

    @Test func aPinnedLinkLeadsItsFilteredSection() throws {
        let history = try typedHistory()
        try history.pin("https://apple.com")
        #expect(texts(in: history.store, filter: .link) == ["https://apple.com", "second.link.dev"])
    }

    @Test func searchMemoDistinguishesDifferentFiltersWithTheSameQuery() throws {
        let history = try History()
        let store = history.store
        history.add("shared token prose", "shared-token.com")

        #expect(store.search("shared", filter: .all).count == 2)
        #expect(store.search("shared", filter: .link).map(\.text) == ["shared-token.com"])
        #expect(store.search("shared", filter: .text).map(\.text) == ["shared token prose"])
        #expect(store.search("shared", filter: .all).count == 2)
    }

    @Test func pinOrderAndClearedRowsSurviveReopening() throws {
        let history = try History()
        history.add("first", "second", "third")
        try history.pin("third", "first")
        let reopened = ClipboardStore(directory: history.directory)
        reopened.load()
        #expect(texts(in: reopened) == ["third", "first", "second"])

        let third = try #require(reopened.items.first { $0.text == "third" })
        reopened.togglePinned(third)
        #expect(texts(in: reopened) == ["first", "third", "second"])

        reopened.clearAll()
        #expect(texts(in: reopened) == ["first"])
        let afterClear = ClipboardStore(directory: history.directory)
        afterClear.load()
        #expect(texts(in: afterClear) == ["first"])
    }

    @Test func syncInterleavesRowsByCaptureTimeAndCanPinAndRemoveExistingRows() async throws {
        let history = try History()
        let now = Date()
        history.store.importEntries([textEntry("old", at: now - 300), textEntry("new", at: now - 100)])

        _ = await history.store.applySynced(
            [textEntry("middle", at: now - 200), textEntry("newest", at: now)], images: [:], removing: [])

        let ordered = ["newest", "new", "middle", "old"]
        #expect(texts(in: history.store) == ordered)
        let reopened = ClipboardStore(directory: history.directory)
        reopened.load()
        #expect(texts(in: reopened) == ordered)
        reopened.addText("copied", sourceBundleID: nil)
        #expect(texts(in: reopened).first == "copied")

        let middle = try #require(reopened.items.first { $0.text == "middle" })
        let old = try #require(reopened.items.first { $0.text == "old" })
        _ = await reopened.applySynced([middle.with(pinnedAt: .now)], images: [:], removing: [old.id])
        #expect(reopened.items.count == 4)
        let updated = try #require(reopened.items.first { $0.text == "middle" })
        #expect(updated.isPinned)
    }

    @Test func anUnreadableDatabaseIsRebuiltAndFlaggedOnlyOnce() throws {
        let scratch = try ScratchDirectory("clipboard-corrupt")
        try Data("not a database".utf8).write(to: scratch.url.appending(path: "clipboard.sqlite3"))
        let rebuilt = ClipboardStore(directory: scratch.url)
        #expect(rebuilt.isOpen)
        #expect(rebuilt.wasRebuilt)
        #expect(!ClipboardStore(directory: scratch.url).wasRebuilt)
    }

    @Test func exportStreamsEveryRowExactlyOnceEvenOutsideTheResidentWindow() throws {
        let history = try History()
        let total = 1200
        history.store.importEntries(numberedEntries(count: total))
        #expect(history.store.items.count < total)

        var exported: [ClipboardItem] = []
        ClipboardStore.forEachStoredItem(inDatabaseAt: history.store.dbURL) { exported.append($0) }
        #expect(exported.count == total)
        #expect(Set(exported.compactMap(\.text)).count == total)
    }

    enum ImageRemoval: Sendable {
        case row, clearHistory, retention
    }

    @Test(.timeLimit(.minutes(1)), arguments: [ImageRemoval.row, .clearHistory, .retention])
    func removingAnOwnedBlobAlsoCleansUpEveryDerivative(_ removal: ImageRemoval) async throws {
        let history = try History()
        let store = history.store
        let staged = history.directory.appending(path: "blob.png")
        try Data("png".utf8).write(to: staged)
        let entry = ClipboardItem(
            imagePath: staged.path, createdAt: Date().addingTimeInterval(-2 * 86_400), sourceBundleID: nil)
        let count = ClipboardStore.importStoredItems(
            inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir, [entry])
        try #require(count == 1)
        store.load()
        let row = try #require(store.items.first)
        let blob = try #require(store.imageURL(for: row))
        #expect(store.ownsImage(of: row))
        let copies = try writeDerivatives(for: blob)
        let changes = try directoryChanges(at: ImageDerivative.folder(beside: blob))

        switch removal {
        case .row: store.remove(row)
        case .clearHistory: store.clearAll()
        case .retention:
            store.maxAge = 86_400
            store.enforceLimits()
        }

        for await _ in changes
        where !copies.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            break
        }
        try Task.checkCancellation()
        #expect(!copies.contains { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func loadingSweepsDerivativesOnlyWhenTheirBlobIsGone() async throws {
        let history = try History()
        let store = history.store
        let staged = history.directory.appending(path: "kept.png")
        try Data("png".utf8).write(to: staged)
        let count = ClipboardStore.importStoredItems(
            inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir,
            [ClipboardItem(imagePath: staged.path, sourceBundleID: nil)])
        try #require(count == 1)
        let kept = try writeDerivatives(for: store.imagesDir.appending(path: "kept.png"))
        let orphaned = try writeDerivatives(for: store.imagesDir.appending(path: "gone.png"))

        store.load()
        await derivativeQueueDrained()

        #expect(!orphaned.contains { FileManager.default.fileExists(atPath: $0.path) })
        #expect(kept.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func reimportingAnImageLeavesExactlyOneRowAndOneOwnedBlob() throws {
        let history = try History()
        let store = history.store
        let staging = history.directory.appending(path: "staged")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let blob = staging.appending(path: "blob.png")
        let staged = ClipboardItem(imagePath: blob.path, sourceBundleID: nil)
        let bytes = Data("png".utf8)

        try bytes.write(to: blob)
        let first = ClipboardStore.importStoredItems(
            inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir, [staged])
        #expect(first == 1)
        try bytes.write(to: blob)
        let repeated = ClipboardStore.importStoredItems(
            inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir, [staged])
        #expect(repeated == 0)
        store.load()

        #expect(store.items.count == 1)
        let images = try FileManager.default.contentsOfDirectory(atPath: store.imagesDir.path)
        #expect(images == ["blob.png"])
    }

    @Test func aMultiFileCopyCreatesOneRowPerPathAndDeduplicatesARepeatedLeadingFile() throws {
        let history = try History()
        let store = history.store

        store.addFiles(["/tmp/a.png", "/tmp/b.mov", "/tmp/c.pdf"], sourceBundleID: nil)

        #expect(store.items.count == 3)
        #expect(store.items.map(\.filePath) == ["/tmp/c.pdf", "/tmp/b.mov", "/tmp/a.png"])
        store.addFiles(["/tmp/c.pdf"], sourceBundleID: nil)
        #expect(store.items.count == 3)
    }

    @Test(arguments: 0..<3)
    func fileBatchesStayInRecencyOrderAndKeepTheOldestPin(_ lastBatch: Int) throws {
        let history = try History()
        let store = history.store
        for index in 0..<1000 { store.addText("entry \(index)", sourceBundleID: nil) }
        let oldest = try history.row("entry 0")
        store.togglePinned(oldest)
        var latest: [String] = []
        for batch in 0...lastBatch {
            latest = (0..<32).map { "/Users/me/batch-\(batch)-\($0).txt" }
            store.addFiles(latest, sourceBundleID: nil)
        }

        #expect(store.items.count == 1000)
        #expect(store.items.prefix(latest.count).compactMap(\.filePath) == Array(latest.reversed()))
        #expect(store.items.contains { $0.id == oldest.id && $0.isPinned })
        if lastBatch == 2 {
            #expect(store.items.last(where: { !$0.isPinned })?.text == "entry 97")
            #expect(store.search("entry 1", filter: .text).contains { $0.text == "entry 1" })
        }
    }

    @Test func droppingReferencedFileRowsNeverDeletesTheFile() throws {
        let history = try History()
        let store = history.store
        let external = history.directory.appending(path: "original.txt")
        try Data("keep me".utf8).write(to: external)
        store.addFiles([external.path], sourceBundleID: nil)
        store.remove(try #require(store.items.first))
        #expect(FileManager.default.fileExists(atPath: external.path))

        store.addFiles([external.path], sourceBundleID: nil)
        store.maxAge = -1
        store.enforceLimits()
        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: external.path))

        store.maxAge = 86_400
        store.addFiles([external.path], sourceBundleID: nil)
        store.clearAll()
        #expect(FileManager.default.fileExists(atPath: external.path))
    }

    @Test(arguments: ["report", "downloads", "re"])
    func fileSearchMatchesTheNameAndFolderAtEitherQueryLength(_ query: String) throws {
        let history = try History()
        history.store.addFiles(["/Users/me/Downloads/Quarterly Report.pdf"], sourceBundleID: nil)
        #expect(history.store.search(query, filter: .all).count == 1)
    }

    @Test func importingFilesDeduplicatesByPathAndDoesNotAdoptBlobs() throws {
        let history = try History()
        let first = ClipboardItem(filePath: "/tmp/one.pdf", sourceBundleID: nil)
        let second = ClipboardItem(filePath: "/tmp/two.pdf", sourceBundleID: nil)

        #expect(history.store.importEntries([first, second]) == 2)
        #expect(history.store.importEntries([first]) == 0)
        #expect(history.store.items.allSatisfy { $0.imagePath == nil })
    }

    private func typedHistory() throws -> History {
        let history = try History()
        history.add(
            "just some prose", "https://apple.com", "hi@apple.com", "second.link.dev",
            "#FF5733", "rgb(0 255 0 / 0.5)")
        return history
    }

    private func texts(in store: ClipboardStore, filter: ClipboardFilter = .all) -> [String] {
        store.search("", filter: filter).compactMap(\.text)
    }

    private func numberedEntries(count: Int) -> [ClipboardItem] {
        let now = Date()
        return (0..<count).map { textEntry("entry \($0)", at: now + Double($0 - count)) }
    }

    private func textEntry(_ text: String, at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: date, sourceBundleID: nil)
    }

    private func writeDerivatives(for blob: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: ImageDerivative.folder(beside: blob), withIntermediateDirectories: true)
        let copies = ImageDerivative.all(of: blob).map(\.url)
        for copy in copies { try Data("copy".utf8).write(to: copy) }
        return copies
    }
}
