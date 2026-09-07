import Foundation

@main
@MainActor
struct ExtensionStorageTests {
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
    static func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-storage-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ text: String, to directory: URL, name: String) {
        try? text.write(
            to: directory.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8)
    }

    // MARK: - Cases

    /// Files written before `metadata` existed must keep their data, not reset the extension.
    static func oldShapeKeepsItsData() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ExtensionStorage(directory: directory)
        writer.setLocalStorage(extension: "coffee", key: "k", value: .string("v"))
        writer.setPreference(extension: "coffee", key: "p", value: .bool(true))
        writer.flush()

        // Simulate a file from before `metadata` existed by stripping the key.
        let url = directory.appendingPathComponent("coffee.json")
        guard let data = try? Data(contentsOf: url),
            var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            expect(false, "the seeded file reads back as JSON")
            return
        }
        object.removeValue(forKey: "metadata")
        guard let stripped = try? JSONSerialization.data(withJSONObject: object) else {
            expect(false, "the stripped file re-encodes")
            return
        }
        try? stripped.write(to: url)

        let storage = ExtensionStorage(directory: directory)
        expect(
            storage.localStorageValue(extension: "coffee", key: "k") == .string("v"),
            "localStorage survives the missing metadata key")
        expect(
            storage.preference(extension: "coffee", key: "p") == .bool(true),
            "preferences survive the missing metadata key")
        expect(
            storage.commandMetadata(extension: "coffee", command: "status")
                == ExtensionStorage.CommandMetadata(),
            "the metadata starts at its defaults")
    }

    /// A partial record — the shape a hand-written seed has — keeps what it sets.
    static func partialMetadataKeepsItsFlag() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        write(
            """
            {"localStorage":{},"caches":{},"preferences":{},\
            "metadata":{"tick":{"backgroundEnabled":true}}}
            """, to: directory, name: "ticklab")

        let storage = ExtensionStorage(directory: directory)
        let metadata = storage.commandMetadata(extension: "ticklab", command: "tick")
        expect(metadata.backgroundEnabled, "a seeded flag reads back true")
        expect(metadata.consecutiveFailures == 0, "a missing counter defaults to zero")
    }

    /// Writes round-trip through a second instance over the same directory.
    static func writesRoundTrip() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ExtensionStorage(directory: directory)
        first.setSubtitle("Tick 1", extension: "ticklab", command: "tick")
        first.setBackgroundEnabled(true, extension: "ticklab", command: "tick")
        first.flush()

        let second = ExtensionStorage(directory: directory)
        let metadata = second.commandMetadata(extension: "ticklab", command: "tick")
        expect(metadata.subtitle == "Tick 1", "the subtitle round-trips")
        expect(metadata.backgroundEnabled, "the flag round-trips")
    }

    /// Garbage stays a fresh store rather than a crash; the next flush heals the file.
    static func garbageStaysSafe() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        write("not json at all", to: directory, name: "broken")

        let storage = ExtensionStorage(directory: directory)
        expect(
            storage.commandMetadata(extension: "broken", command: "x")
                == ExtensionStorage.CommandMetadata(),
            "a corrupt file reads as defaults")
    }

    static func main() {
        oldShapeKeepsItsData()
        partialMetadataKeepsItsFlag()
        writesRoundTrip()
        garbageStaysSafe()

        print(failures == 0 ? "Extension storage tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
