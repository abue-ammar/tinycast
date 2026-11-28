import Foundation
import Testing

@testable import Tinycast

@MainActor
struct ClipboardSyncTests {
    @Test func duplicateTextTravelsOnceAndPinsUpdateTheReceivingRow() async throws {
        let sender = try History()
        let receiver = try History()
        sender.store.addText("hello", sourceBundleID: nil)
        sender.store.addText("other", sourceBundleID: nil)
        sender.store.addText("hello", sourceBundleID: nil)
        sender.store.addFiles(["/Users/someone/report.pdf"], sourceBundleID: nil)

        let sent = try #require(await sender.text.snapshot())
        #expect(sent.count == 2)
        let firstRetry = await receiver.text.apply(upload(from: sender.text, keys: sent.keys.sorted()))
        #expect(firstRetry.isEmpty)
        #expect(receiver.store.search("", filter: .all).compactMap(\.text) == ["hello", "other"])
        let received = try #require(await receiver.text.snapshot())
        #expect(Set(received.keys) == Set(sent.keys))

        let other = try #require(sender.store.items.first { $0.text == "other" })
        sender.store.togglePinned(other)
        let updated = try #require(await sender.text.snapshot())
        let pinRetry = await receiver.text.apply(upload(from: sender.text, keys: updated.keys.sorted()))
        #expect(pinRetry.isEmpty)
        #expect(receiver.store.items.count == 2)
        let pinned = try #require(receiver.store.items.first { $0.text == "other" })
        #expect(pinned.isPinned)
    }

    @Test func onlyOwnedImagesTravelAndTheirBytesArriveWithTheRow() async throws {
        let sender = try History()
        let receiver = try History()
        let bytes = Data("png bytes".utf8)
        let owned = sender.store.imagesDir.appending(path: UUID().uuidString + ".png")
        try bytes.write(to: owned)
        sender.store.importEntries([
            ClipboardItem(imagePath: owned.path, sourceBundleID: nil),
            ClipboardItem(imagePath: "/Users/someone/Pictures/elsewhere.png", sourceBundleID: nil)
        ])

        let sent = try #require(await sender.images.snapshot())
        #expect(sent.keys.sorted() == [owned.lastPathComponent])
        let retry = await receiver.images.apply(upload(from: sender.images, keys: sent.keys.sorted()))
        #expect(retry.isEmpty)
        let path = try #require(receiver.store.items.first?.imagePath)
        let image = URL(filePath: path)
        #expect(image.lastPathComponent == owned.lastPathComponent)
        #expect(try Data(contentsOf: image) == bytes)
    }

    @Test func deletingAContentKeyRemovesEveryMatchingRow() async throws {
        let sender = try History()
        let receiver = try History()
        sender.store.addText("secret", sourceBundleID: nil)
        let key = try #require(await sender.text.snapshot()?.keys.first)
        receiver.store.addText("secret", sourceBundleID: nil)
        receiver.store.addText("kept", sourceBundleID: nil)
        receiver.store.addText("secret", sourceBundleID: nil)

        _ = await receiver.text.apply(SyncChanges(deletions: [key]))

        #expect(receiver.store.search("", filter: .all).compactMap(\.text) == ["kept"])
    }

    @Test func syncPausesWhenHistoryIsDisabledOrClosed() async throws {
        let history = try History()
        let disabled = ClipboardSyncSource(.text, store: history.store, isActive: { false })
        #expect(await disabled.snapshot() == nil)
        history.store.close()
        #expect(await history.text.snapshot() == nil)
    }

    @Test func anUnreadableHistoryPausesSync() async throws {
        let history = try History()
        history.store.addText("kept", sourceBundleID: nil)
        let path = history.store.dbURL.path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        #expect(await history.text.snapshot() == nil)
    }

    @Test func aFailedBlobWriteDefersTheKeyAndLeavesNoRow() async throws {
        let sender = try History()
        let receiver = try History()
        let owned = sender.store.imagesDir.appending(path: UUID().uuidString + ".png")
        try Data("png bytes".utf8).write(to: owned)
        sender.store.importEntries([ClipboardItem(imagePath: owned.path, sourceBundleID: nil)])
        let path = receiver.store.imagesDir.path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

        let sent = try #require(await sender.images.snapshot())
        let retry = await receiver.images.apply(upload(from: sender.images, keys: sent.keys.sorted()))

        #expect(retry == [owned.lastPathComponent])
        #expect(receiver.store.items.isEmpty)
    }

    @Test func pinningAnOlderDuplicateUpdatesTheReceiversContentKey() async throws {
        let sender = try History()
        let receiver = try History()
        sender.store.addText("A", sourceBundleID: nil)
        sender.store.addText("B", sourceBundleID: nil)
        sender.store.addText("A", sourceBundleID: nil)
        let sent = try #require(await sender.text.snapshot())
        let firstRetry = await receiver.text.apply(upload(from: sender.text, keys: sent.keys.sorted()))
        #expect(firstRetry.isEmpty)

        let older = try #require(sender.store.items.last { $0.text == "A" })
        sender.store.togglePinned(older)
        let updated = try #require(await sender.text.snapshot())
        let pinRetry = await receiver.text.apply(upload(from: sender.text, keys: updated.keys.sorted()))

        #expect(pinRetry.isEmpty)
        let received = try #require(receiver.store.items.first { $0.text == "A" })
        #expect(received.isPinned)
    }

    @Test func editsAndPinsNeedANewSnapshotBeforeUpload() async throws {
        let sender = try History()
        let receiver = try History()
        sender.store.addText("before", sourceBundleID: nil)
        let oldKey = try #require(await sender.text.snapshot()?.keys.first)
        let original = try #require(sender.store.items.first { $0.text == "before" })
        let edited = try #require(try sender.store.updateText("after", of: original))

        #expect(await sender.text.payload(for: oldKey) == nil)
        let newKey = try #require(await sender.text.snapshot()?.keys.first)
        #expect(newKey != oldKey)
        sender.store.togglePinned(edited)
        #expect(await sender.text.payload(for: newKey) == nil)

        let updated = try #require(await sender.text.snapshot())
        let retry = await receiver.text.apply(upload(from: sender.text, keys: updated.keys.sorted()))
        #expect(retry.isEmpty)
        let received = try #require(receiver.store.items.first { $0.text == "after" })
        #expect(received.isPinned)
    }

    private func upload(from source: ClipboardSyncSource, keys: [String]) async -> SyncChanges {
        var changes = SyncChanges()
        for key in keys { changes.upserts[key] = await source.payload(for: key) }
        return changes
    }

    @MainActor
    private struct History {
        private let scratch: ScratchDirectory
        let store: ClipboardStore
        let text: ClipboardSyncSource
        let images: ClipboardSyncSource

        init() throws {
            scratch = try ScratchDirectory("clipboard-sync")
            store = ClipboardStore(directory: scratch.url)
            text = ClipboardSyncSource(.text, store: store, isActive: { true })
            images = ClipboardSyncSource(.image, store: store, isActive: { true })
        }
    }
}
