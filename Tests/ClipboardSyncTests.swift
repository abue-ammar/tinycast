// Two clipboard stores trading entries through the shipped sync source, as two Macs would.
import Foundation

@main
@MainActor
struct ClipboardSyncTests {
    static var failures = 0
    static var passes = 0

    struct Mac {
        let store: ClipboardStore
        let text: ClipboardSyncSource
        let images: ClipboardSyncSource
    }

    static func main() async {
        await textTravelsByContent()
        await ownedImagesTravelWithTheirBlob()
        await deletionsTakeEveryDuplicate()
        await unavailableHistoryIsPaused()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    static func textTravelsByContent() async {
        await withMacs { a, b in
            a.store.addText("hello", sourceBundleID: nil)
            a.store.addText("other", sourceBundleID: nil)
            a.store.addText("hello", sourceBundleID: nil)
            a.store.addFiles(["/Users/someone/report.pdf"], sourceBundleID: nil)
            let sent = await a.text.snapshot() ?? [:]
            expect(sent.count == 2, "a repeated text is one key, and a copied file never travels")

            await send(from: a.text, to: b.text)
            expect(texts(b.store) == ["hello", "other"], "the other Mac shows the history in order")
            let held = await b.text.snapshot() ?? [:]
            expect(Set(held.keys) == Set(sent.keys), "and holds the same keys")

            a.store.togglePinned(item(a.store, "other"))
            await send(from: a.text, to: b.text)
            expect(b.store.items.count == 2, "a pin updates the row it reaches rather than adding one")
            expect(item(b.store, "other").isPinned, "and the pin arrives")
        }
    }

    static func ownedImagesTravelWithTheirBlob() async {
        await withMacs { a, b in
            let bytes = Data("png bytes".utf8)
            let owned = a.store.imagesDir.appendingPathComponent(UUID().uuidString + ".png")
            try? bytes.write(to: owned)
            a.store.importEntries([
                image(at: owned.path), image(at: "/Users/someone/Pictures/elsewhere.png")
            ])
            let sent = await a.images.snapshot() ?? [:]
            expect(sent.keys.sorted() == [owned.lastPathComponent], "only an owned image travels")

            await send(from: a.images, to: b.images)
            let path = b.store.items.first?.imagePath ?? ""
            expect(URL(fileURLWithPath: path).lastPathComponent == owned.lastPathComponent, "same name")
            expect(FileManager.default.contents(atPath: path) == bytes, "the blob arrives with it")
        }
    }

    static func deletionsTakeEveryDuplicate() async {
        await withMacs { a, b in
            a.store.addText("secret", sourceBundleID: nil)
            let key = await a.text.snapshot()?.keys.first ?? ""
            b.store.addText("secret", sourceBundleID: nil)
            b.store.addText("kept", sourceBundleID: nil)
            b.store.addText("secret", sourceBundleID: nil)
            _ = await b.text.apply(SyncChanges(deletions: [key]))
            expect(texts(b.store) == ["kept"], "a deletion removes every row holding that text")
        }
    }

    static func unavailableHistoryIsPaused() async {
        await withMacs { a, _ in
            let switchedOff = ClipboardSyncSource(.text, store: a.store, isActive: { false })
            let off = await switchedOff.snapshot()
            expect(off == nil, "a history that is switched off is paused, never empty")
            a.store.close()
            let closed = await a.text.snapshot()
            expect(closed == nil, "so is a closed one")
        }
    }

    // MARK: - Harness

    static func send(from source: ClipboardSyncSource, to target: ClipboardSyncSource) async {
        var changes = SyncChanges()
        for key in await source.snapshot()?.keys.sorted() ?? [] {
            changes.upserts[key] = await source.payload(for: key)
        }
        let deferred = await target.apply(changes)
        expect(deferred.isEmpty, "nothing is deferred")
    }

    static func withMacs(_ body: (Mac, Mac) async -> Void) async {
        let directories = [scratchDirectory(), scratchDirectory()]
        defer { directories.forEach { try? FileManager.default.removeItem(at: $0) } }
        let macs = directories.map { directory in
            let store = ClipboardStore(directory: directory)
            return Mac(
                store: store, text: ClipboardSyncSource(.text, store: store, isActive: { true }),
                images: ClipboardSyncSource(.image, store: store, isActive: { true }))
        }
        await body(macs[0], macs[1])
    }

    static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-clipboard-sync-\(UUID().uuidString)", isDirectory: true)
    }

    static func image(at path: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .image, text: nil, imagePath: path, createdAt: Date(),
            sourceBundleID: nil)
    }

    static func texts(_ store: ClipboardStore) -> [String] {
        store.search("", filter: .all).compactMap(\.text)
    }

    static func item(_ store: ClipboardStore, _ text: String) -> ClipboardItem {
        guard let match = store.items.first(where: { $0.text == text }) else {
            fail("no entry named \(text)")
            exit(1)
        }
        return match
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
