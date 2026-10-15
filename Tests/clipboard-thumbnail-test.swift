import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
@MainActor
struct ClipboardThumbnailTests {
    static var failures = 0
    static var passes = 0

    static func main() async {
        await removalDuringGenerationLeavesNoCopy()
        await clearDuringGenerationLeavesNoCopy()
        await sameNameDifferentExtensionsStayApart()
        await timeoutReleasesTheQueue()
        await cancellationReleasesTheQueue()
        await fallbackReadsTheOriginalUnlessCancelled()
        await unreadableCopyFallsBackAndIsDropped()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    static func removalDuringGenerationLeavesNoCopy() async {
        await deletingDuringGeneration("removing") { store, item in store.remove(item) }
    }

    static func clearDuringGenerationLeavesNoCopy() async {
        await deletingDuringGeneration("clearing history") { store, _ in store.clearAll() }
    }

    static func deletingDuringGeneration(
        _ way: String, delete: (ClipboardStore, ClipboardItem) -> Void
    ) async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir.appendingPathComponent("store"))
        let item = adopt("shot.png", color: .systemRed, into: store, from: dir)
        guard let url = store.imageURL(for: item), let copy = ImageDerivative.covering(url, maxPixel: 64)
        else { return fail("\(way): the adopted image has a row copy") }
        let helper = script(in: dir, sleeping: 0.6)

        let making = Task { await ImageThumbnail.makeCopy(copy, of: url, helper: helper) }
        try? await Task.sleep(for: .milliseconds(200))
        delete(store, item)
        if way == "removing" {
            let gone = !FileManager.default.fileExists(atPath: url.path)
            expect(gone, "the image is gone before any queued work")
        }
        _ = await making.value
        ImageDerivative.queue.sync {}
        expect(!FileManager.default.fileExists(atPath: url.path), "\(way) mid-copy deletes the image")
        expect(!FileManager.default.fileExists(atPath: copy.url.path), "\(way) mid-copy leaves no copy")
    }

    /// Adopted images keep their names, so `shot.jpg` and `shot.png` can share a stem.
    static func sameNameDifferentExtensionsStayApart() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir.appendingPathComponent("store"))
        let jpeg = adopt("shot.jpg", color: .systemRed, into: store, from: dir)
        let png = adopt("shot.png", color: .systemBlue, into: store, from: dir)
        let helper = script(in: dir, sleeping: 0)
        var copies: [URL] = []
        for item in [jpeg, png] {
            guard let url = store.imageURL(for: item), let copy = ImageDerivative.covering(url, maxPixel: 64),
                await ImageThumbnail.makeCopy(copy, of: url, helper: helper)
            else { return fail("each image gets its own copy") }
            copies.append(copy.url)
        }
        expect(copies[0] != copies[1], "shot.jpg and shot.png get different copies")
        expect(color(of: copies[0]) == "red", "shot.jpg's copy shows shot.jpg")
        expect(color(of: copies[1]) == "blue", "shot.png's copy shows shot.png")

        store.remove(jpeg)
        ImageDerivative.queue.sync {}
        expect(!FileManager.default.fileExists(atPath: copies[0].path), "removing shot.jpg drops its copy")
        expect(FileManager.default.fileExists(atPath: copies[1].path), "and keeps shot.png's")
    }

    static func timeoutReleasesTheQueue() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stuck = image("a.png", color: .systemRed, in: dir)
        let next = image("b.png", color: .systemBlue, in: dir)
        let start = ContinuousClock.now
        let made = await ImageThumbnail.makeCopy(
            ImageDerivative.covering(stuck, maxPixel: 64)!, of: stuck,
            helper: script(in: dir, sleeping: 30), timeout: .milliseconds(300))
        expect(!made && start.duration(to: .now) < .seconds(5), "a stuck helper times out")
        let after = await ImageThumbnail.makeCopy(
            ImageDerivative.covering(next, maxPixel: 64)!, of: next, helper: script(in: dir, sleeping: 0))
        expect(after, "the queue makes the next copy after a timeout")
    }

    static func cancellationReleasesTheQueue() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stuck = image("a.png", color: .systemRed, in: dir)
        let next = image("b.png", color: .systemBlue, in: dir)
        let helper = script(in: dir, sleeping: 30)
        let making = Task {
            await ImageThumbnail.makeCopy(
                ImageDerivative.covering(stuck, maxPixel: 64)!, of: stuck, helper: helper)
        }
        try? await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        making.cancel()
        let made = await making.value
        expect(!made && start.duration(to: .now) < .seconds(5), "cancelling ends the helper")
        let after = await ImageThumbnail.makeCopy(
            ImageDerivative.covering(next, maxPixel: 64)!, of: next, helper: script(in: dir, sleeping: 0))
        expect(after, "the queue makes the next copy after a cancel")
    }

    static func fallbackReadsTheOriginalUnlessCancelled() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let shown = image("a.png", color: .systemRed, in: dir)
        let scrolledAway = image("b.png", color: .systemBlue, in: dir)
        let missing = dir.appendingPathComponent("missing-helper")
        let fallback = await ImageThumbnail.loadAsync(shown, maxPixel: 64, copyingWith: missing)
        expect(fallback != nil, "a failed copy falls back to decoding the original")
        let cancelled = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return await ImageThumbnail.loadAsync(scrolledAway, maxPixel: 64, copyingWith: missing) != nil
        }
        expect(!(await cancelled.value), "a cancelled load skips the full-size fallback")
    }

    static func unreadableCopyFallsBackAndIsDropped() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = image("a.png", color: .systemRed, in: dir)
        guard let copy = ImageDerivative.covering(url, maxPixel: 64) else { return fail("a row copy is due") }
        try? FileManager.default.createDirectory(
            at: ImageDerivative.folder(beside: url), withIntermediateDirectories: true)
        try? Data("not a png".utf8).write(to: copy.url)
        let image = await ImageThumbnail.loadAsync(
            url, maxPixel: 64, copyingWith: dir.appendingPathComponent("missing-helper"))
        ImageDerivative.queue.sync {}
        expect(image != nil, "an unreadable copy falls back to the original")
        let dropped = !FileManager.default.fileExists(atPath: copy.url.path)
        expect(dropped, "and is dropped so the next draw remakes it")
    }

    // MARK: - Fixtures

    /// Stand-in helper: reads the source first and writes the copy last, as the real one does.
    static func script(in dir: URL, sleeping seconds: Double) -> URL {
        let url = dir.appendingPathComponent("helper-\(UUID().uuidString).sh")
        let body = """
            #!/bin/sh
            read=$(mktemp) && cp "$2" "$read" || exit 1
            sleep \(seconds)
            mkdir -p "$(dirname "$3")" && mv "$read" "$3"
            """
        try? body.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Wider than the row copy's edge, so a copy is due; JPEG or PNG by extension.
    static func image(_ name: String, color: NSColor, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        let context = CGContext(
            data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let type = url.pathExtension == "jpg" ? UTType.jpeg : UTType.png
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    static func adopt(
        _ name: String, color: NSColor, into store: ClipboardStore, from dir: URL
    ) -> ClipboardItem {
        let staged = dir.appendingPathComponent("staged-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let blob = image(name, color: color, in: staged)
        ClipboardStore.importStoredItems(
            inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir,
            [ClipboardItem(imagePath: blob.path, sourceBundleID: nil)])
        store.load()
        guard let item = store.items.first(where: { $0.imagePath?.hasSuffix("/" + name) == true }) else {
            fail("\(name) is adopted")
            exit(1)
        }
        return item
    }

    static func color(of url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let pixel = NSBitmapImageRep(cgImage: image).colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB)
        else { return "unreadable" }
        return pixel.redComponent > pixel.blueComponent ? "red" : "blue"
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "tinycast-clipboard-thumbnail-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
