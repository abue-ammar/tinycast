import Foundation

@main
@MainActor
struct ExtensionCommandMetadataTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    /// Scratch state of its own, never the machine's extension files.
    static func makeFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-metadata-test-\(UUID().uuidString).json")
    }

    // MARK: - Cases

    /// Writes round-trip through a second store over the same file.
    static func writesRoundTrip() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let first = ExtensionCommandMetadataStore(fileURL: file)
        first.setSubtitle("Tick 1", extension: "ticklab", command: "tick")
        first.setBackgroundEnabled(true, extension: "ticklab", command: "tick")
        first.flush()

        let second = ExtensionCommandMetadataStore(fileURL: file)
        let metadata = second.metadata(extension: "ticklab", command: "tick")
        expect(metadata.subtitle == "Tick 1", "the subtitle round-trips")
        expect(metadata.backgroundEnabled, "the flag round-trips")
        expect(
            second.metadata(extension: "ticklab", command: "other") == ExtensionCommandMetadata(),
            "an unwritten command reads as defaults")
    }

    /// A failure counts up so the policy can back off; a success retires the error with the count.
    static func resultsTrackTheFailureRun() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionCommandMetadataStore(fileURL: file)
        let now = Date()
        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: false, error: "Boom.", now: now)
        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: false, error: "Boom.", now: now)
        var metadata = store.metadata(extension: "ticklab", command: "tick")
        expect(metadata.consecutiveFailures == 2, "consecutive failures accumulate")
        expect(metadata.lastError == "Boom.", "the last error is kept")

        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: true, error: nil, now: now)
        metadata = store.metadata(extension: "ticklab", command: "tick")
        expect(metadata.consecutiveFailures == 0, "a success resets the count")
        expect(metadata.lastError == nil, "a success clears the error")
        expect(metadata.lastRun == now, "the run is stamped")
    }

    /// Disabling retires the warning, so it cannot outlive the schedule that caused it.
    static func clearingTheErrorRetiresTheBackoff() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionCommandMetadataStore(fileURL: file)
        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: false, error: "Boom.", now: Date())
        store.clearBackgroundError(extension: "ticklab", command: "tick")
        let metadata = store.metadata(extension: "ticklab", command: "tick")
        expect(metadata.lastError == nil, "the error is gone")
        expect(metadata.consecutiveFailures == 0, "the backoff is gone with it")
    }

    /// Uninstalling takes the extension's records with it, and only its own.
    static func removeAllDropsOneExtension() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionCommandMetadataStore(fileURL: file)
        store.activateBackgroundRefresh(extension: "ticklab", command: "tick", now: Date())
        store.activateBackgroundRefresh(extension: "coffee", command: "status", now: Date())
        store.removeAll(extension: "ticklab")
        store.flush()

        let reloaded = ExtensionCommandMetadataStore(fileURL: file)
        expect(
            !reloaded.metadata(extension: "ticklab", command: "tick").backgroundEnabled,
            "the uninstalled extension's record is gone")
        expect(
            reloaded.metadata(extension: "coffee", command: "status").backgroundEnabled,
            "the other extension keeps its own")
    }

    /// Garbage stays a fresh store rather than a crash; the next flush heals the file.
    static func garbageStaysSafe() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try? "not json at all".write(to: file, atomically: true, encoding: .utf8)

        let store = ExtensionCommandMetadataStore(fileURL: file)
        expect(
            store.metadata(extension: "broken", command: "x") == ExtensionCommandMetadata(),
            "a corrupt file reads as defaults")
    }

    static func main() {
        writesRoundTrip()
        resultsTrackTheFailureRun()
        clearingTheErrorRetiresTheBackoff()
        removeAllDropsOneExtension()
        garbageStaysSafe()

        print(failures == 0 ? "Extension command metadata tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
