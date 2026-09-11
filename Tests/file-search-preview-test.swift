import Foundation

@main
struct FileSearchPreviewTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    @MainActor
    static func main() {
        missingFile()
        fileProbe()
        directoryProbe()
        byteFormatting()
        dateFormatters()
        previewSizes()
        actionOptions()
        resetTimeouts()

        print(failures == 0 ? "File search preview tests passed" : "\(failures) file search preview tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func previewSizes() {
        expect(FileSearchPreviewSize.allCases.count == 4, "4 preview sizes defined")
        expect(FileSearchPreviewSize.medium.maxHeight == 180, "medium preview size is 180pt")
        expect(FileSearchPreviewSize.small.maxHeight < FileSearchPreviewSize.large.maxHeight, "small is shorter than large")
        for size in FileSearchPreviewSize.allCases {
            expect(!size.title.isEmpty, "size title non-empty")
            expect(size.maxHeight > 0, "size height positive")
            expect(size.placeholderIconSize > 0, "placeholder icon size positive")
        }
    }

    static func actionOptions() {
        expect(FileSearchActionOption.allCases.count == 9, "9 action options defined")
        expect(FileSearchActionOption.open.defaultShortcut == "↵", "open shortcut is return")
        expect(FileSearchActionOption.quickLook.defaultShortcut == "⌘Y", "quickLook shortcut is ⌘Y")
        for action in FileSearchActionOption.allCases {
            expect(!action.title.isEmpty, "action title non-empty")
            expect(!action.systemImage.isEmpty, "action system image non-empty")
        }
    }

    static func resetTimeouts() {
        expect(FileSearchResetTimeout.allCases.count == 6, "6 reset timeouts defined")
        expect(FileSearchResetTimeout.immediately.interval == 0, "immediately interval is 0")
        expect(FileSearchResetTimeout.afterThreeMinutes.interval == 180, "afterThreeMinutes interval is 180")
        expect(FileSearchResetTimeout.never.interval == .infinity, "never interval is infinity")
    }

    static func missingFile() {
        let missingURL = URL(fileURLWithPath: "/tmp/tinycast-nonexistent-\(UUID().uuidString)")
        let probe = FileMetadataProbe.probe(url: missingURL)
        expect(!probe.exists, "missing file probe reports exists = false")
        expect(!probe.isDirectory, "missing file probe reports isDirectory = false")
        expect(probe.fileBytes == nil, "missing file probe has nil bytes")
    }

    static func fileProbe() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tinycast-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("test.txt")
        let text = "Hello Tinycast"
        try? text.write(to: testFile, atomically: true, encoding: .utf8)

        let probe = FileMetadataProbe.probe(url: testFile)
        expect(probe.exists, "temp file exists")
        expect(!probe.isDirectory, "temp file is not a directory")
        expect(probe.fileBytes == Int64(text.utf8.count), "file bytes match text byte count")
        expect(probe.typeName != nil, "type name is resolved")
        expect(probe.creationDate != nil, "creation date is present")
        expect(probe.modificationDate != nil, "modification date is present")
    }

    static func directoryProbe() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tinycast-test-dir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let probe = FileMetadataProbe.probe(url: tempDir)
        expect(probe.exists, "temp directory exists")
        expect(probe.isDirectory, "temp directory is marked as isDirectory")
        expect(probe.typeName?.lowercased() == "folder", "folder type name resolves to folder (got \(String(describing: probe.typeName)))")
    }

    static func byteFormatting() {
        let formattedZero = FileMetadataProbe.formatBytes(0)
        expect(!formattedZero.isEmpty, "formatBytes(0) produces non-empty string")
        let formattedKB = FileMetadataProbe.formatBytes(2048)
        expect(formattedKB.contains("2") || formattedKB.contains("KB"), "formatBytes(2048) contains KB/size")
    }

    @MainActor
    static func dateFormatters() {
        let now = Date()
        let formatted = FileMetadataProbe.formatDate(now)
        expect(!formatted.isEmpty, "formatDate produces non-empty string")
        let accessed = FileMetadataProbe.formatAccessedDate(now)
        expect(!accessed.isEmpty, "formatAccessedDate produces non-empty string")
    }
}
