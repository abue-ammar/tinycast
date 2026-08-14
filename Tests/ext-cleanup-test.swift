import Foundation

@main
@MainActor
struct ExtensionCleanupTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    // MARK: - Fixtures

    /// Roots under one throwaway directory. Nothing here can reach the real install: `Roots` is
    /// injected, so `Bundle.main` is never consulted.
    static func makeRoots() -> (ExtensionCleanup.Roots, URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-cleanup-test-\(UUID().uuidString)", isDirectory: true)
        let roots = ExtensionCleanup.Roots(
            temp: base.appendingPathComponent("temp", isDirectory: true),
            support: base.appendingPathComponent("support", isDirectory: true),
            data: base.appendingPathComponent("data", isDirectory: true))
        for url in [roots.temp, roots.support, roots.data] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return (roots, base)
    }

    static func makeDirectory(_ parent: URL, _ name: String, bytes: Int = 1024) {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? Data(repeating: 0, count: bytes).write(to: url.appendingPathComponent("payload.bin"))
    }

    static func makeFile(_ parent: URL, _ name: String, bytes: Int = 512) {
        try? Data(repeating: 0, count: bytes).write(to: parent.appendingPathComponent(name))
    }

    static func exists(_ url: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
    }

    // MARK: - Cases

    /// A workspace is ours by name. Anything else in the temp root belongs to somebody else.
    static func sweepTakesOnlyOurWorkspaces() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.temp, "tinycast-install-ABC123")
        makeDirectory(roots.temp, "tinycast-install-DEF456")
        makeDirectory(roots.temp, "keep-me")
        makeFile(roots.temp, "unrelated.txt")

        ExtensionCleanup.sweepWorkspaces(in: roots.temp)

        expect(!exists(roots.temp, "tinycast-install-ABC123"), "a stale workspace is swept")
        expect(!exists(roots.temp, "tinycast-install-DEF456"), "every stale workspace is swept")
        expect(exists(roots.temp, "keep-me"), "another app's directory survives")
        expect(exists(roots.temp, "unrelated.txt"), "an unrelated file survives")
    }

    /// The installed set is the authority: what it names is kept, everything else is a leftover.
    static func cleanTakesOnlyOrphans() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.support, "kill-process")
        makeDirectory(roots.support, "speedtest")
        makeFile(roots.data, "kill-process.json")
        makeFile(roots.data, "speedtest.json")
        makeDirectory(roots.temp, "tinycast-install-STRAY")

        let report = ExtensionCleanup.clean(installed: ["kill-process"], in: roots)

        expect(exists(roots.support, "kill-process"), "an installed extension keeps its scratch dir")
        expect(exists(roots.data, "kill-process.json"), "an installed extension keeps its data")
        expect(!exists(roots.support, "speedtest"), "an orphaned scratch dir goes")
        expect(!exists(roots.data, "speedtest.json"), "an orphaned data file goes")
        expect(!exists(roots.temp, "tinycast-install-STRAY"), "a stray workspace goes")
        expect(report.items == 3, "the report counts every removal: \(report.items)")
        expect(report.bytes > 0, "the report measures what it freed: \(report.bytes)")
    }

    /// An npm-scoped name flattens the same way everywhere, or its files orphan themselves.
    static func scopedNamesMatchTheirDirectories() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.support, ExtensionCatalog.safeName("@scope/thing"))
        makeFile(roots.data, "\(ExtensionCatalog.safeName("@scope/thing")).json")

        let report = ExtensionCleanup.clean(installed: ["@scope/thing"], in: roots)

        expect(report.isEmpty, "a scoped name matches its own directory: \(report.items) removed")
        expect(exists(roots.support, "scope-thing"), "the scoped scratch dir survives")
    }

    /// What the button promises is what pressing it does.
    static func reclaimableMatchesClean() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.support, "gone-one")
        makeDirectory(roots.support, "gone-two")
        makeFile(roots.data, "gone-one.json")

        let predicted = ExtensionCleanup.reclaimable(installed: [], in: roots)
        let actual = ExtensionCleanup.clean(installed: [], in: roots)

        expect(predicted.items == 3, "reclaimable counts every stray: \(predicted.items)")
        expect(predicted == actual, "reclaimable predicts clean exactly")
    }

    /// Nothing to do is not a failure, and neither is a root that was never created.
    static func emptyAndMissingRootsAreSafe() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        expect(ExtensionCleanup.clean(installed: [], in: roots).isEmpty, "empty roots report nothing")

        let missing = ExtensionCleanup.Roots(
            temp: base.appendingPathComponent("nope-temp"),
            support: base.appendingPathComponent("nope-support"),
            data: base.appendingPathComponent("nope-data"))
        expect(ExtensionCleanup.clean(installed: [], in: missing).isEmpty, "missing roots report nothing")
        ExtensionCleanup.sweepWorkspaces(in: missing.temp)
    }

    /// The installer and the sweep have to agree on the name, which is why one type owns it.
    static func workspaceIsSweptByItsOwnPrefix() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        let workspace = ExtensionCleanup.workspace(in: roots.temp)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        ExtensionCleanup.sweepWorkspaces(in: roots.temp)

        expect(
            !FileManager.default.fileExists(atPath: workspace.path),
            "a workspace the installer would make is one the sweep finds")
    }

    /// Raycast Beta v2 keeps its extensions under `raycast-x`. Checking only `raycast` is why an
    /// install of the Beta reported that no Raycast was present at all.
    static func bothRaycastChannelsAreSearched() {
        let roots = ExtensionCatalog.raycastExtensionRoots().map(\.path)
        expect(roots.count == 2, "both channels are searched: \(roots.count)")
        expect(
            roots.contains { $0.hasSuffix("/.config/raycast/extensions") },
            "the stable channel is searched")
        expect(
            roots.contains { $0.hasSuffix("/.config/raycast-x/extensions") },
            "the beta channel is searched")
    }

    static func main() {
        bothRaycastChannelsAreSearched()
        sweepTakesOnlyOurWorkspaces()
        cleanTakesOnlyOrphans()
        scopedNamesMatchTheirDirectories()
        reclaimableMatchesClean()
        emptyAndMissingRootsAreSafe()
        workspaceIsSweptByItsOwnPrefix()

        print(failures == 0 ? "Extension cleanup tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
