import Foundation

@main
@MainActor
struct ExtensionVersionStoreTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        reconciling()
        forgetting()
        persisting()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func reconciling() {
        print("\n# reconciling")
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionVersionStore(fileURL: file)
        store.record("a1", for: "current")
        store.record("a1", for: "behind")
        store.record(nil, for: "imported")

        let latest = [
            listing("current", commit: "a1"), listing("behind", commit: "b2"),
            listing("imported", commit: "c3"), listing("untracked", commit: "d4"),
            listing("unversioned", commit: nil)
        ]
        let behind = store.reconcile(with: latest).map(\.name)
        check("a newer commit is behind", behind == ["behind"])
        check("an import adopts the store's version", store.reconcile(with: latest).map(\.name) == ["behind"])

        store.record(nil, for: "unversioned")
        check(
            "a listing without a commit never reads as behind",
            store.reconcile(with: [listing("unversioned", commit: nil)]).isEmpty)
        check(
            "an untracked install is never checked",
            !store.tracked.contains("untracked"))
    }

    static func forgetting() {
        print("\n# forgetting")
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionVersionStore(fileURL: file)
        store.record("a1", for: "github")
        store.forget("github")
        check("a forgotten install leaves tracking", !store.tracked.contains("github"))
        check(
            "and is never reported behind",
            store.reconcile(with: [listing("github", commit: "b2")]).isEmpty)
    }

    static func persisting() {
        print("\n# persisting")
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        ExtensionVersionStore(fileURL: file).record("a1", for: "coffee")
        let reopened = ExtensionVersionStore(fileURL: file)
        check("a recorded version survives a relaunch", reopened.tracked == ["coffee"])
        check(
            "and keeps its commit",
            reopened.reconcile(with: [listing("coffee", commit: "b2")]).map(\.name) == ["coffee"])
        check(
            "a missing file starts empty",
            ExtensionVersionStore(fileURL: makeFile()).tracked.isEmpty)
    }

    // MARK: - Helpers

    /// Scratch state of its own, never the machine's extension files.
    static func makeFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-version-test-\(UUID().uuidString).json")
    }

    static func listing(_ name: String, commit: String?) -> ExtensionListing {
        ExtensionListing(
            id: name, name: name, title: name, summary: "", author: "", lightIconURL: nil,
            darkIconURL: nil, commandCount: 1, downloadCount: nil,
            downloadURL: URL(fileURLWithPath: "/dev/null"), commitSHA: commit)
    }

    static func check(_ description: String, _ condition: Bool) {
        if condition {
            passes += 1
            print("PASS  \(description)")
        } else {
            failures += 1
            print("FAIL  \(description)")
        }
    }
}
