import CoreText
import Foundation
import ImageIO
import SQLite3
import PDFKit

@main
@MainActor
struct ClipboardTextTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ocr-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("scan.png")
        let image = makeImage()
        let destination = CGImageDestinationCreateWithURL(
            imageURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        expect(CGImageDestinationFinalize(destination), "write image fixture")

        let imageText = try await Task.detached {
            try await ClipboardTextExtractor.extract(at: imageURL, isPDF: false)
        }.value
        expect(imageText.localizedCaseInsensitiveContains("ALPINE RECEIPT 7391"), "Vision recognizes image")
        let fileText = try await Task.detached {
            try await ClipboardTextExtractor.extract(at: imageURL, isPDF: false)
        }.value
        expect(fileText.contains("7391"), "referenced image is recognized")

        let pdfURL = directory.appendingPathComponent("mixed.pdf")
        makePDF(at: pdfURL, scan: image)
        let pdfText = try await Task.detached {
            try await ClipboardTextExtractor.extract(at: pdfURL, isPDF: true)
        }.value
        expect(pdfText.contains("EMBEDDED INVOICE 4826"), "PDF embedded text is extracted")
        expect(pdfText.contains("7391"), "PDF scanned page is recognized")
        expect(pdfText.utf8.count <= ClipboardTextExtractor.maximumTextBytes, "text is bounded")

        let tallURL = directory.appendingPathComponent("tall.png")
        let tall = CGContext(
            data: nil, width: 2000, height: 5000, bitsPerComponent: 8,
            bytesPerRow: 8000, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        tall.setFillColor(CGColor(gray: 1, alpha: 1))
        tall.fill(CGRect(x: 0, y: 0, width: 2000, height: 5000))
        draw("ALPINE RECEIPT 7391", in: tall)
        let tallDestination = CGImageDestinationCreateWithURL(
            tallURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(tallDestination, tall.makeImage()!, nil)
        expect(CGImageDestinationFinalize(tallDestination), "write tall screenshot fixture")
        let tallText = try await Task.detached {
            try await ClipboardTextExtractor.extract(at: tallURL, isPDF: false)
        }.value
        expect(tallText.contains("7391"), "small relative text survives tall screenshot downsampling")

        let missing = ClipboardItem(
            filePath: directory.appendingPathComponent("missing.pdf").path,
            sourceBundleID: nil)
        do {
            _ = try await ClipboardTextExtractor.extract(
                at: URL(fileURLWithPath: missing.filePath!), isPDF: true)
            expect(false, "missing file throws")
        } catch { expect(true, "missing file throws") }
        let cancelled = Task.detached {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
            return try await ClipboardTextExtractor.extract(at: imageURL, isPDF: false)
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            expect(false, "cancelled extraction throws")
        } catch is CancellationError { expect(true, "cancelled extraction throws") }

        try await searchAndLifetime(in: directory)
        try await scheduling(in: directory)
        try await retryFailures(in: directory)
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func searchAndLifetime(in directory: URL) async throws {
        let store = ClipboardStore(directory: directory.appendingPathComponent("search"))
        store.maxAge = ClipboardRetention.forever.maxAge
        store.addFiles(["/tmp/invoice.pdf"], sourceBundleID: nil)
        let original = store.items[0]
        expect(!store.textSearchEnabled, "text recognition defaults to off")
        expect(store.nextExtractionItem() == nil, "disabled store has no extraction work")
        expect(!hasExtractionTable(store.dbURL), "disabled store never creates OCR schema")
        expect(
            store.search("invoice", filter: .all).first?.id == original.id, "ordinary search works while off")
        expect(store.setTextSearchEnabled(true), "enable extraction")
        expect(store.nextExtractionItem()?.id == original.id, "existing history is backfilled")
        expect(
            store.setExtractedText(
                "Receipt ZX https://example.com", for: original,
                generation: store.extractionGeneration), "persist extraction")
        expect(store.search("Receipt", filter: .all).isEmpty, "first search returns without awaiting OCR")
        try await waitUntil { store.search("Receipt", filter: .all).contains { $0.id == original.id } }
        expect(store.items[0].text == original.text, "pasted content stays original")
        expect(store.search("Receipt", filter: .link).isEmpty, "recognized URL cannot change item type")
        expect(store.search("Receipt", filter: .text).isEmpty, "PDF never becomes a text clip")
        try await waitUntil { store.search("zx", filter: .file).contains { $0.id == original.id } }
        try await waitUntil { store.search("Receipt", filter: .all).first?.id == original.id }
        store.togglePinned(original)
        expect(
            store.search("Receipt", filter: .all).first?.isPinned == true,
            "pinning keeps the selected OCR match synchronously")
        try await waitUntil { store.search("Receipt", filter: .all).first?.isPinned == true }
        store.togglePinned(store.items[0])
        expect(
            store.search("Receipt", filter: .all).first?.id == original.id,
            "unpinning keeps the OCR match synchronously")
        store.addText("newest", sourceBundleID: nil)
        store.promote(original)
        try await waitUntil { store.search("Receipt", filter: .all).first?.id == original.id }
        store.setTextSearchEnabled(false)
        expect(store.search("Receipt", filter: .all).isEmpty, "off excludes cached OCR results immediately")
        expect(store.search("invoice", filter: .all).first?.id == original.id, "off retains ordinary search")
        store.addText("new while off", sourceBundleID: nil)
        store.promote(store.items.first { $0.id == original.id }!)
        store.close()
        store.open()
        store.load()
        expect(!store.textSearchEnabled, "reopen does not opt in")
        expect(store.nextExtractionItem() == nil, "reopen does not initialize worker")
        store.setTextSearchEnabled(true)
        expect(store.nextExtractionItem() == nil, "reenable reuses disk results")
        try await waitUntil { store.search("Receipt", filter: .all).first?.id == original.id }
        store.remove(original)
        expect(store.search("Receipt", filter: .all).isEmpty, "delete invalidates cached matches")
        expect(
            !store.setExtractedText("late", for: original, generation: store.extractionGeneration),
            "deleted entry cannot be resurrected")
        let old = ClipboardItem(
            imagePath: "/tmp/old.png",
            createdAt: Date().addingTimeInterval(-86_400 * 7), sourceBundleID: nil)
        store.importEntries([old] + (0..<1005).map { ClipboardItem(text: "new \($0)", sourceBundleID: nil) })
        expect(!store.items.contains { $0.id == old.id }, "fixture is beyond resident window")
        store.setExtractedText("archive document", for: old, generation: store.extractionGeneration)
        try await waitUntil { store.search("archive", filter: .image).first?.id == old.id }
        store.maxAge = 86_400
        store.enforceLimits()
        expect(
            store.search("archive", filter: .image).isEmpty,
            "retention invalidates a cached OCR hit outside the resident window")
        let generation = store.extractionGeneration
        store.clearAll()
        expect(
            !store.setExtractedText("late", for: old, generation: generation),
            "clear discards late extraction")
        try await Task.sleep(for: .milliseconds(20))
        expect(store.search("archive", filter: .image).isEmpty, "clear discards late search")
    }

    static func hasExtractionTable(_ url: URL) -> Bool {
        var db: OpaquePointer?
        precondition(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE name = 'item_text'", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    static func scheduling(in directory: URL) async throws {
        let store = ClipboardStore(directory: directory.appendingPathComponent("store"))
        expect(store.setTextSearchEnabled(true), "enable extraction for scheduling fixture")
        var idle = false
        var calls = 0
        let indexer = ClipboardTextIndexer(
            store: store, delay: .milliseconds(10), canRun: { idle },
            extract: { _ in
                await MainActor.run { calls += 1 }
                try await Task.sleep(for: .milliseconds(80))
                return "scheduled result"
            })
        store.onItemsChanged = { [weak indexer] in indexer?.schedule() }
        store.addFiles(["/tmp/fixture.pdf"], sourceBundleID: nil)
        indexer.start()
        try await Task.sleep(for: .milliseconds(50))
        expect(calls == 0, "busy input defers extraction")
        idle = true
        try await waitUntil { calls == 1 }
        indexer.stop()
        await indexer.waitUntilStopped()
        try await Task.sleep(for: .milliseconds(120))
        expect(store.nextExtractionItem() != nil, "disable cancels in-flight result")
        indexer.start()
        try await waitUntil { store.nextExtractionItem() == nil }
        expect(calls == 2, "reenable resumes cancelled work")
        try await Task.sleep(for: .milliseconds(50))
        expect(calls == 2, "completed item is processed once")
        store.addFiles(["/tmp/second.pdf"], sourceBundleID: nil)
        try await waitUntil { calls == 3 }
        // `applyClipboardTextSearch` never waits between the two, so a cancelled run must requeue.
        store.addFiles(["/tmp/third.pdf"], sourceBundleID: nil)
        let restarted = calls
        indexer.stop()
        indexer.start()
        try await waitUntil { store.nextExtractionItem() == nil }
        expect(calls > restarted, "stop immediately followed by start drains the queue")
        store.clearAll()
        try await Task.sleep(for: .milliseconds(120))
        expect(store.search("scheduled", filter: .all).isEmpty, "clear discards in-flight result")
        indexer.stop()
    }

    static func retryFailures(in directory: URL) async throws {
        enum Failure: Error { case temporary }
        let store = ClipboardStore(directory: directory.appendingPathComponent("failures"))
        store.setTextSearchEnabled(true)
        store.addFiles(["/tmp/failure.pdf"], sourceBundleID: nil)
        let failed = store.items[0]
        var calls = 0
        var failing = true
        let indexer = ClipboardTextIndexer(
            store: store, delay: .milliseconds(10), retryDelay: 0.05, canRun: { true },
            extract: { _ in
                let shouldFail = await MainActor.run {
                    calls += 1; return failing
                }
                if shouldFail { throw Failure.temporary }
                return "RECOVERED 4826"
            })
        store.onItemsChanged = { [weak indexer] in indexer?.schedule() }
        indexer.start()
        try await waitUntil { calls == 3 && store.nextExtractionRetry == nil }
        try await Task.sleep(for: .milliseconds(100))
        expect(calls == 3, "persistent failures stop after three attempts")
        expect(store.nextExtractionItem() == nil, "exhausted failure does not spin in queue")
        indexer.stop()
        await indexer.waitUntilStopped()
        store.setTextSearchEnabled(false)
        store.setTextSearchEnabled(true)
        expect(store.nextExtractionItem()?.id == failed.id, "reenabling offers failed item again")
        failing = false
        indexer.start()
        try await waitUntil { calls == 4 && store.nextExtractionItem() == nil }
        try await waitUntil { store.search("RECOVERED", filter: .file).count == 1 }
        expect(store.nextExtractionRetry == nil, "success removes retry state")
        indexer.stop()
        await indexer.waitUntilStopped()

        store.clearAll()
        store.addFiles(["/tmp/later.pdf"], sourceBundleID: nil)
        let item = store.items[0]
        let generation = store.extractionGeneration
        let now = Date()
        store.recordExtractionFailure(for: item, generation: generation, retryAt: now.addingTimeInterval(30))
        expect(store.nextExtractionItem(now: now) == nil, "backoff delays retries")
        expect(
            store.nextExtractionItem(now: now.addingTimeInterval(31))?.id == item.id, "retry becomes eligible"
        )
        indexer.start()
        try await Task.sleep(for: .milliseconds(30))
        store.addFiles(["/tmp/fresh.pdf"], sourceBundleID: nil)
        try await waitUntil { calls == 5 }
        expect(calls == 5, "fresh capture wakes retry sleep without waiting thirty seconds")
        indexer.stop()
        await indexer.waitUntilStopped()
        store.remove(item)
        expect(store.nextExtractionRetry == nil, "deletion removes retry state")
        store.recordExtractionFailure(for: item, generation: generation, retryAt: now)
        expect(store.nextExtractionRetry == nil, "late failure cannot recreate deleted row")
        store.clearAll()
        store.addFiles(["/tmp/empty.pdf"], sourceBundleID: nil)
        let empty = store.items[0]
        store.setExtractedText("", for: empty, generation: store.extractionGeneration)
        expect(store.nextExtractionItem() == nil, "empty successful recognition does not loop")
        store.setTextSearchEnabled(false)
        store.setTextSearchEnabled(true)
        expect(store.nextExtractionItem()?.id == empty.id, "reenabling retries earlier empty attempts")
        store.close()
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        expect(false, "scheduler completed before timeout")
    }

    static func makeImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 1000, height: 300, bitsPerComponent: 8,
            bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 300))
        draw("ALPINE RECEIPT 7391", in: context)
        return context.makeImage()!
    }

    static func makePDF(at url: URL, scan: CGImage) {
        var box = CGRect(x: 0, y: 0, width: 1000, height: 300)
        let consumer = CGDataConsumer(url: url as CFURL)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        draw("EMBEDDED INVOICE 4826", in: context)
        context.endPDFPage()
        context.beginPDFPage(nil)
        context.draw(scan, in: box)
        context.endPDFPage()
        context.closePDF()
    }

    static func draw(_ text: String, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica" as CFString, 48, nil)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 40, y: 150)
        CTLineDraw(line, context)
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
