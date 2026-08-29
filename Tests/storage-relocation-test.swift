// Drives the real `ClipboardStore` on both sides: a copied schema would drift.
import Foundation

@main
@MainActor
struct StorageRelocationTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        theRelocationWindowIsStillOpen()
        movesTheDurableStoresAndLeavesTheCaches()
        theWriteAheadLogTravelsWithTheDatabase()
        rewritesOwnedImagePathsAndLeavesExternalOnes()
        resumesAfterAPartialRun()
        aSecondRunChangesNothing()
        aCacheOnlyDirectoryIsLeftAlone()
        mergesImagesWhenTheDestinationAlreadyExists()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    /// The point of `Tinycast/Migration/`: it fails the suite rather than outliving its purpose.
    static func theRelocationWindowIsStillOpen() {
        expect(
            Date() < StorageRelocation.removeAfter,
            """
            the relocation window has closed — delete it now:
              rm -rf Tinycast/Migration Tests/storage-relocation-test.swift
              drop the `run storage-relocation-test` line from Scripts/run-tests.sh
              drop the `StorageRelocation.run()` call from Tinycast/App/TinycastApp.swift
              drop the `Tinycast/Migration/` row from AGENTS.md, then `xcodegen generate`
            """)
    }

    static func movesTheDurableStoresAndLeavesTheCaches() {
        withDirectories { caches, support in
            seed(caches, rows: [ClipboardItem(text: "hello", sourceBundleID: nil)])
            write("png", to: caches.appendingPathComponent("images"), "a.png")
            for name in [
                "calculator-history.json", "launcher-ranking.json", "emoji-frequency.json",
                "currency-rates.json"
            ] {
                write("[]", to: caches, name)
            }

            StorageRelocation.run(caches: caches, support: support)

            for name in [
                "clipboard.sqlite3", "calculator-history.json", "launcher-ranking.json",
                "emoji-frequency.json"
            ] {
                expect(exists(support, name), "\(name) moved to Application Support")
                expect(!exists(caches, name), "\(name) no longer sits in Caches")
            }
            expect(
                exists(support.appendingPathComponent("images"), "a.png"),
                "image blobs move with the database")
            expect(
                exists(caches, "currency-rates.json") && !exists(support, "currency-rates.json"),
                "a refetchable cache is not durable data, and stays put")
            expect(texts(in: support) == ["hello"], "and the history reopens where it landed")
        }
    }

    /// A force-quit leaves a hot `-wal` behind; stranding it in Caches loses the writes it holds.
    static func theWriteAheadLogTravelsWithTheDatabase() {
        withDirectories { caches, support in
            seed(caches, rows: [])
            for suffix in ["-wal", "-shm"] { write("x", to: caches, "clipboard.sqlite3" + suffix) }

            StorageRelocation.run(caches: caches, support: support)

            for suffix in ["-wal", "-shm"] {
                let name = "clipboard.sqlite3" + suffix
                expect(exists(support, name), "\(name) travels with the database")
                expect(!exists(caches, name), "and nothing of it is left behind")
            }
        }
    }

    static func rewritesOwnedImagePathsAndLeavesExternalOnes() {
        withDirectories { caches, support in
            let owned = caches.appendingPathComponent("images/kept.png").path
            // Imported from another app: real, outside our images directory, not ours to move.
            let outside = caches.deletingLastPathComponent()
            let external = outside.appendingPathComponent("elsewhere.png").path
            seed(
                caches,
                rows: [
                    ClipboardItem(text: "hello", sourceBundleID: nil),
                    ClipboardItem(imagePath: owned, sourceBundleID: nil),
                    ClipboardItem(imagePath: external, sourceBundleID: nil)
                ])
            write("png", to: caches.appendingPathComponent("images"), "kept.png")
            write("png", to: outside, "elsewhere.png")

            StorageRelocation.run(caches: caches, support: support)

            let paths = imagePaths(in: support)
            expect(
                paths.contains(support.appendingPathComponent("images/kept.png").path),
                "an owned blob's row follows it to Application Support")
            expect(paths.contains(external), "a reference we never owned is left byte-for-byte")
            expect(paths.count == 2, "and a text row keeps its null path")
            expect(
                resolvesEveryImage(in: support),
                "every image row resolves to a file that is actually there")
        }
    }

    /// The crash window: the database landed, the blobs did not. The next launch finishes it.
    static func resumesAfterAPartialRun() {
        withDirectories { caches, support in
            let owned = caches.appendingPathComponent("images/kept.png").path
            seed(caches, rows: [ClipboardItem(imagePath: owned, sourceBundleID: nil)])
            write("png", to: caches.appendingPathComponent("images"), "kept.png")
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.moveItem(
                    at: caches.appendingPathComponent("clipboard.sqlite3" + suffix),
                    to: support.appendingPathComponent("clipboard.sqlite3" + suffix))
            }

            StorageRelocation.run(caches: caches, support: support)

            expect(
                imagePaths(in: support)
                    == [support.appendingPathComponent("images/kept.png").path],
                "the blobs catch up with the database, and the rows follow them")
        }
    }

    static func aSecondRunChangesNothing() {
        withDirectories { caches, support in
            let owned = caches.appendingPathComponent("images/kept.png").path
            seed(caches, rows: [ClipboardItem(imagePath: owned, sourceBundleID: nil)])
            write("png", to: caches.appendingPathComponent("images"), "kept.png")

            StorageRelocation.run(caches: caches, support: support)
            let after = imagePaths(in: support)
            StorageRelocation.run(caches: caches, support: support)

            expect(
                imagePaths(in: support) == after,
                "re-running over a migrated layout rewrites nothing a second time")
            expect(resolvesEveryImage(in: support), "and leaves the blobs where the first run put them")
        }
    }

    static func aCacheOnlyDirectoryIsLeftAlone() {
        withDirectories { caches, support in
            write("{}", to: caches, "currency-rates.json")

            StorageRelocation.run(caches: caches, support: support)

            expect(
                (try? FileManager.default.contentsOfDirectory(atPath: support.path))?.isEmpty
                    == true,
                "nothing to move means nothing is created")
        }
    }

    static func mergesImagesWhenTheDestinationAlreadyExists() {
        withDirectories { caches, support in
            seed(caches, rows: [])
            write("old", to: caches.appendingPathComponent("images"), "old.png")
            write("new", to: support.appendingPathComponent("images"), "new.png")

            StorageRelocation.run(caches: caches, support: support)

            let images = support.appendingPathComponent("images")
            expect(
                exists(images, "old.png") && exists(images, "new.png"),
                "a rename that cannot merge falls back to moving the blobs one by one")
            expect(
                !FileManager.default.fileExists(
                    atPath: caches.appendingPathComponent("images").path),
                "and the emptied directory goes")
        }
    }

    // MARK: - Harness

    /// Runs `body` against a fresh Caches/Application Support pair, torn down afterwards.
    static func withDirectories(_ body: (URL, URL) -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-relocation-test-\(UUID().uuidString)")
        let caches = root.appendingPathComponent("Caches")
        let support = root.appendingPathComponent("Application Support")
        for url in [caches, support] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        body(caches, support)
    }

    /// The store closes with the scope, so the relocation never moves a database out from under it.
    static func seed(_ directory: URL, rows: [ClipboardItem]) {
        let store = ClipboardStore(directory: directory)
        if !rows.isEmpty { expect(store.importEntries(rows) == rows.count, "seeded \(rows.count)") }
    }

    static func texts(in directory: URL) -> [String] {
        reopened(directory).items.compactMap(\.text)
    }

    static func imagePaths(in directory: URL) -> [String] {
        reopened(directory).items.compactMap(\.imagePath).sorted()
    }

    static func resolvesEveryImage(in directory: URL) -> Bool {
        let store = reopened(directory)
        return store.items.filter { $0.kind == .image }
            .compactMap { store.imageURL(for: $0) }
            .allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func reopened(_ directory: URL) -> ClipboardStore {
        let store = ClipboardStore(directory: directory)
        store.load()
        return store
    }

    static func write(_ contents: String, to directory: URL, _ name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? contents.write(
            to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    static func exists(_ directory: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
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
