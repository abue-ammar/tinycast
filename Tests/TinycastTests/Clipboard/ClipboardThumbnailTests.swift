import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Tinycast

// A paused helper holds the shared derivative queue while the test changes the history.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClipboardThumbnailTests {
    private let scratch: ScratchDirectory
    private let store: ClipboardStore

    init() throws {
        scratch = try ScratchDirectory("clipboard-thumbnails")
        store = ClipboardStore(directory: scratch.url.appending(path: "store"))
    }

    enum Removal: Sendable {
        case entry, history
    }

    @Test(arguments: [Removal.entry, .history])
    func deletingAnImageDuringACopyLeavesNeitherFile(_ removal: Removal) async throws {
        let item = try adoptImage("shot.png", color: .systemRed)
        let original = try #require(store.imageURL(for: item))
        let copy = try #require(ImageDerivative.covering(original, maxPixel: 64))
        let helper = try PausedHelper(in: scratch.url)
        let making = Task { await ImageThumbnail.makeCopy(copy, of: original, helper: helper.executable) }
        defer { making.cancel() }
        try await helper.waitUntilStarted()

        switch removal {
        case .entry:
            store.remove(item)
            #expect(!FileManager.default.fileExists(atPath: original.path))
        case .history:
            store.clearAll()
        }
        try helper.release()
        _ = await making.value

        let changes = try directoryChanges(at: copy.url.deletingLastPathComponent())
        for await _ in changes where !FileManager.default.fileExists(atPath: copy.url.path) { break }
        try Task.checkCancellation()
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: copy.url.path))
    }

    @Test func sameNamedJPEGAndPNGKeepSeparateCopiesAndDeleteIndependently() async throws {
        let jpeg = try adoptImage("shot.jpg", color: .systemRed)
        let png = try adoptImage("shot.png", color: .systemBlue)
        let jpegURL = try #require(store.imageURL(for: jpeg))
        let pngURL = try #require(store.imageURL(for: png))
        let jpegCopy = try #require(ImageDerivative.covering(jpegURL, maxPixel: 64))
        let pngCopy = try #require(ImageDerivative.covering(pngURL, maxPixel: 64))
        let helper = try installHelper(in: scratch.url.appending(path: "copy"))

        #expect(await ImageThumbnail.makeCopy(jpegCopy, of: jpegURL, helper: helper))
        #expect(await ImageThumbnail.makeCopy(pngCopy, of: pngURL, helper: helper))
        #expect(jpegCopy.url != pngCopy.url)
        let jpegPixel = try pixel(in: jpegCopy.url)
        let pngPixel = try pixel(in: pngCopy.url)
        #expect(jpegPixel.redComponent > jpegPixel.blueComponent)
        #expect(pngPixel.redComponent <= pngPixel.blueComponent)

        store.remove(jpeg)
        await derivativeQueueDrained()
        #expect(!FileManager.default.fileExists(atPath: jpegCopy.url.path))
        #expect(FileManager.default.fileExists(atPath: pngCopy.url.path))
    }

    @Test func timingOutAStuckHelperReleasesTheQueue() async throws {
        let stuck = try writeImage("a.png", color: .systemRed, in: scratch.url)
        let next = try writeImage("b.png", color: .systemBlue, in: scratch.url)
        let firstCopy = try #require(ImageDerivative.covering(stuck, maxPixel: 64))
        let nextCopy = try #require(ImageDerivative.covering(next, maxPixel: 64))
        let helper = try PausedHelper(in: scratch.url)
        let nextHelper = try installHelper(in: scratch.url.appending(path: "next"))

        let started = ContinuousClock.now
        let made = await ImageThumbnail.makeCopy(
            firstCopy, of: stuck, helper: helper.executable, timeout: .milliseconds(300))
        #expect(!made)
        #expect(started.duration(to: .now) < .seconds(5))
        #expect(await ImageThumbnail.makeCopy(nextCopy, of: next, helper: nextHelper))
    }

    @Test func cancellingARunningHelperReleasesTheQueue() async throws {
        let stuck = try writeImage("a.png", color: .systemRed, in: scratch.url)
        let next = try writeImage("b.png", color: .systemBlue, in: scratch.url)
        let firstCopy = try #require(ImageDerivative.covering(stuck, maxPixel: 64))
        let nextCopy = try #require(ImageDerivative.covering(next, maxPixel: 64))
        let helper = try PausedHelper(in: scratch.url)
        let nextHelper = try installHelper(in: scratch.url.appending(path: "next"))
        let making = Task { await ImageThumbnail.makeCopy(firstCopy, of: stuck, helper: helper.executable) }
        defer { making.cancel() }
        try await helper.waitUntilStarted()

        let started = ContinuousClock.now
        making.cancel()
        let made = await making.value
        #expect(!made)
        #expect(started.duration(to: .now) < .seconds(5))
        #expect(await ImageThumbnail.makeCopy(nextCopy, of: next, helper: nextHelper))
    }

    @Test func failedCopyDecodesTheOriginal() async throws {
        let original = try writeImage("a.png", color: .systemRed, in: scratch.url)
        let missing = scratch.url.appending(path: "missing-helper")
        let image = await ImageThumbnail.loadAsync(original, maxPixel: 64, copyingWith: missing)
        #expect(image != nil)
    }

    @Test func cancelledLoadSkipsDecodingTheOriginal() async throws {
        let original = try writeImage("b.png", color: .systemBlue, in: scratch.url)
        let missing = scratch.url.appending(path: "missing-helper")
        let load = Task {
            let image = await ImageThumbnail.loadAsync(original, maxPixel: 64, copyingWith: missing)
            return image != nil
        }
        load.cancel()
        #expect(await load.value == false)
    }

    @Test func unreadableCopyIsDiscardedAndTheOriginalStillDecodes() async throws {
        let original = try writeImage("a.png", color: .systemRed, in: scratch.url)
        let copy = try #require(ImageDerivative.covering(original, maxPixel: 64))
        try FileManager.default.createDirectory(
            at: ImageDerivative.folder(beside: original), withIntermediateDirectories: true)
        try Data("not a png".utf8).write(to: copy.url)

        let image = await ImageThumbnail.loadAsync(
            original, maxPixel: 64, copyingWith: scratch.url.appending(path: "missing-helper"))
        await derivativeQueueDrained()
        #expect(image != nil)
        #expect(!FileManager.default.fileExists(atPath: copy.url.path))
    }

    private func adoptImage(_ name: String, color: NSColor) throws -> ClipboardItem {
        let staging = scratch.url.appending(path: "staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let file = try writeImage(name, color: color, in: staging)
        let count = ClipboardStore.importStoredItems(
            inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir,
            [ClipboardItem(imagePath: file.path, sourceBundleID: nil)])
        try #require(count == 1)
        store.load()
        return try #require(store.items.first { $0.imagePath?.hasSuffix("/" + name) == true })
    }

    private func writeImage(_ name: String, color: NSColor, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let type = url.pathExtension == "jpg" ? UTType.jpeg : .png
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        let image = try #require(context.makeImage())
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixel(in url: URL) throws -> NSColor {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(NSBitmapImageRep(cgImage: image).colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB))
    }

    private struct PausedHelper {
        let executable: URL
        let started: URL
        private let gate: FileHandle

        init(in root: URL) throws {
            let directory = root.appending(path: "paused")
            executable = try installHelper(in: directory)
            started = directory.appending(path: "started")
            let release = directory.appending(path: "release")
            guard mkfifo(release.path, 0o600) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let descriptor = open(release.path, O_RDWR | O_CLOEXEC)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            gate = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        }

        func waitUntilStarted() async throws {
            let changes = try directoryChanges(at: started.deletingLastPathComponent())
            for await _ in changes where FileManager.default.fileExists(atPath: started.path) { return }
            throw CancellationError()
        }

        func release() throws {
            try gate.write(contentsOf: Data("continue\n".utf8))
        }
    }
}

private func installHelper(in directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appending(path: "thumbnail-helper.sh")
    try FileManager.default.copyItem(at: Fixture.url("Clipboard/thumbnail-helper.sh"), to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    return script
}
