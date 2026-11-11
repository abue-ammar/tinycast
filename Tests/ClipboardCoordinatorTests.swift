import AppKit
import SQLite3

@main
@MainActor
struct ClipboardCoordinatorTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        await followsEditedEntry()
        try await writeFailureKeepsHistoryAndClipboard()
        await closedStoreIsNotDeletion()
        await deletedEntryBecomesANewCopy()
        await tooLongEditIsRefused()
        await changedScreenKeepsItsSelection()
        await cancelledAndEmptyEditsChangeNothing()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func followsEditedEntry() async {
        let cases: [(String, String, String, ClipboardFilter, String, ClipboardFilter)] = [
            ("draft selected", "final selected", "draft", .text, "", .text),
            ("draft selected", "draft revised", "draft", .text, "draft", .text),
            ("https://old.example", "https://new.example", "old", .link, "", .link),
            ("draft selected", "https://new.example", "", .text, "", .all),
            ("https://old.example", "plain final", "old", .link, "", .all),
            ("https://old.example", "old final", "old", .link, "old", .all)
        ]
        for pinned in [false, true] {
            for (original, replacement, query, filter, expectedQuery, expectedFilter) in cases {
                let fixture = Fixture(text: original, pinned: pinned)
                defer { fixture.cleanUp() }
                fixture.palette.query = query
                fixture.palette.clipboardFilter = filter
                fixture.core.editedText = replacement
                let follow = fixture.palette.followToken

                await fixture.coordinator.editClip(fixture.item)

                let rows = fixture.store.search(
                    fixture.palette.query, filter: fixture.palette.clipboardFilter)
                expect(
                    rows.indices.contains(fixture.palette.selection)
                        && rows[fixture.palette.selection].id == fixture.item.id,
                    "the edited entry stays selected, pinned=\(pinned), query=\(query), filter=\(filter)")
                expect(fixture.palette.query == expectedQuery, "only a hiding query is cleared")
                expect(
                    fixture.palette.clipboardFilter == expectedFilter, "only a hiding type filter is cleared")
                expect(
                    fixture.palette.restoredSelection == fixture.palette.selection,
                    "query and filter observers restore the edited row instead of landing on another")
                expect(fixture.palette.followToken != follow, "the selected row is scrolled into view")
                expect(
                    Paster.copies.count == 1 && Paster.copies.first?.text == replacement
                        && Paster.copies.first?.isPinned == pinned,
                    "the edited entry is copied with its pin intact")
                expect(Paster.plainCopies.isEmpty, "a successful edit never enters history as a new copy")
                expect(fixture.store.items.count == 3, "editing preserves the history count")
                expect(fixture.core.messages.isEmpty, "a saved edit reports no error")
            }
        }
    }

    static func writeFailureKeepsHistoryAndClipboard() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.palette.query = "draft"
        fixture.palette.clipboardFilter = .text
        fixture.palette.selection = 1
        let before = fixture.store.items
        let follow = fixture.palette.followToken
        var writer: OpaquePointer?
        guard sqlite3_open(fixture.store.dbURL.path, &writer) == SQLITE_OK else {
            sqlite3_close(writer)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(writer) }
        expect(
            sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK, "the fixture locks writes")

        await fixture.coordinator.editClip(fixture.item)

        expect(fixture.store.items == before, "a locked database leaves history unchanged")
        expect(
            Paster.copies.isEmpty && Paster.plainCopies.isEmpty, "a write failure leaves the clipboard alone")
        expect(
            fixture.core.messages == ["Couldn’t save the clipboard entry"],
            "a failed save is reported instead of being treated as deletion")
        expect(
            fixture.palette.query == "draft" && fixture.palette.clipboardFilter == .text
                && fixture.palette.selection == 1 && fixture.palette.followToken == follow,
            "a failed save leaves the search and selection alone")
        expect(sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) == SQLITE_OK, "the fixture releases the lock")
        fixture.store.load()
        expect(
            fixture.store.items.map(\.id) == before.map(\.id)
                && fixture.store.items.compactMap(\.text) == before.compactMap(\.text),
            "no second row reaches disk after a failed save")
        fixture.core.messages = []
        await fixture.coordinator.editClip(fixture.item)
        expect(Paster.copies.count == 1 && fixture.core.messages.isEmpty, "saving works once the lock clears")
    }

    static func closedStoreIsNotDeletion() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.core.onEdit = { fixture.store.close() }
        await fixture.coordinator.editClip(fixture.item)
        expect(
            Paster.plainCopies.isEmpty && Paster.copies.isEmpty,
            "a closed store never copies a supposed deletion")
        expect(fixture.core.messages.count == 1, "an unavailable database reports the save failure")
        fixture.store.open()
        fixture.store.load()
        expect(
            fixture.store.items.first(where: { $0.id == fixture.item.id })?.text == fixture.item.text,
            "a closed store retains the original entry on disk")
    }

    static func deletedEntryBecomesANewCopy() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.core.onEdit = { fixture.store.remove(fixture.item) }
        await fixture.coordinator.editClip(fixture.item)
        expect(Paster.plainCopies == ["final selected"], "only a confirmed deletion takes the new-copy path")
        expect(
            Paster.copies.isEmpty && fixture.core.messages.isEmpty,
            "a deleted row is not saved or reported as failure")
        expect(!fixture.store.items.contains { $0.id == fixture.item.id }, "the deleted entry stays deleted")
    }

    static func tooLongEditIsRefused() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let before = fixture.store.items
        fixture.core.editedText = String(repeating: "a", count: ClipboardStore.maxTextLength + 1)
        await fixture.coordinator.editClip(fixture.item)
        expect(fixture.store.items == before, "an edit past the limit leaves history unchanged")
        expect(Paster.copies.isEmpty && Paster.plainCopies.isEmpty, "an edit past the limit never copies")
        expect(fixture.core.messages.count == 1, "an edit past the limit is reported")
    }

    static func cancelledAndEmptyEditsChangeNothing() async {
        for text: String? in [nil, ""] {
            let fixture = Fixture()
            defer { fixture.cleanUp() }
            let before = fixture.store.items
            fixture.core.editedText = text
            await fixture.coordinator.editClip(fixture.item)
            expect(fixture.store.items == before, "cancel and empty save leave history unchanged")
            expect(Paster.copies.isEmpty && Paster.plainCopies.isEmpty, "cancel and empty save never copy")
        }
    }

    static func changedScreenKeepsItsSelection() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.core.onEdit = {
            fixture.palette.prepare(mode: .launcher)
            fixture.palette.query = "launcher query"
            fixture.palette.selection = 2
        }
        await fixture.coordinator.editClip(fixture.item)
        expect(Paster.copies.count == 1, "the confirmed edit is saved and copied")
        expect(
            fixture.palette.mode == .launcher && fixture.palette.query == "launcher query"
                && fixture.palette.selection == 2,
            "a screen opened during editing keeps its own query and selection")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    @MainActor
    final class Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-clipboard-coordinator-\(UUID().uuidString)")
        let store: ClipboardStore
        let palette = PaletteState()
        let core = AppCore()
        let item: ClipboardItem
        let coordinator: ClipboardCoordinator

        init(text: String = "draft selected", pinned: Bool = false) {
            Paster.copies = []
            Paster.plainCopies = []
            store = ClipboardStore(directory: directory)
            store.addText("other pin", sourceBundleID: nil)
            store.togglePinned(store.items[0])
            store.addText(text, sourceBundleID: "test.source")
            if pinned { store.togglePinned(store.items[0]) }
            item = store.items[0]
            store.addText("draft another row", sourceBundleID: nil)
            palette.prepare(mode: .clipboard)
            coordinator = ClipboardCoordinator(
                clipboardStore: store, clipboardManager: ClipboardManager(), settings: AppSettings(),
                appIndex: AppIndex(), palette: palette, windowController: PaletteWindowController(),
                paletteCoordinator: PaletteCoordinator(), core: core)
        }

        func cleanUp() {
            core.onEdit = nil
            store.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

// Platform effects are recorded so the shipped coordinator cannot write to the user's clipboard.
@MainActor
final class AppCore {
    var editedText: String? = "final selected"
    var onEdit: (() -> Void)?
    var messages: [String] = []
    func editClipboardText(_ text: String) async -> String? { onEdit?(); return editedText }
    func showMessage(_ text: String, tone: DialogTone = .neutral) { messages.append(text) }
    func showProgress(_ text: String) {}
    func applyClipboardTextSearch() {}
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
}

enum DialogTone { case neutral, danger }
enum CommandID { case clipboardHistory, pasteSequentially }

@MainActor
final class AppSettings {
    var clipboardEnabled = true
    var clipboardRetention = ClipboardRetention.forever
    var clipboardDefaultAction = ClipboardDefaultAction.paste
}

@MainActor
final class AppIndex {
    func setCommandsVisible(_ commands: [CommandID], _ visible: Bool) {}
}

@MainActor
final class ClipboardManager {
    func start() {}
    func stop() {}
    func prepareForTinycastPasteboardMutation() {}
}

@MainActor
final class PaletteWindowController {
    var previousApp: NSRunningApplication? { nil }
    func pasteKeepingWindowOpen(_ item: ClipboardItem, store: ClipboardStore) -> Bool { true }
}

@MainActor
final class PaletteCoordinator {
    var isVisible = true
    var targetApp: NSRunningApplication? { nil }
    func hidePalette(restoreFocus: Bool = true) {}
}

enum AppLauncher {
    static func showInFinder(_ url: URL) {}
    static func open(_ url: URL) {}
}

enum ClipboardTextWorker {
    static func extract(_ item: ClipboardItem) async throws -> String { "" }
}

@MainActor
enum Paster {
    static var copies: [ClipboardItem] = []
    static var plainCopies: [String] = []
    @discardableResult
    static func copy(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        copies.append(item)
        store.promote(item)
        return true
    }
    @discardableResult
    static func copyPlainText(_ text: String) -> Bool { plainCopies.append(text); return true }
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool { true }
    static func pastePlainText(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool { true }
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) -> Bool { true }
}
