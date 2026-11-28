import Foundation

/// The Store index decisions, the version rules, command entry IDs and screen rows.
@main
@MainActor
struct ExtensionModelTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() throws {
        runsItsOwnMajorUpToItsOwnMinor()
        comparesVersionsAsNumbers()
        installsOnlyWhatThisBuildRuns()
        offersAnUpdateOrHoldsAPinnedOne()
        revokedBeatsEverything()
        needsANewerTinycastWhenMissingOrNewer()
        updatesSkipPinnedAndNewer()
        try dropsAnEntryItCannotRead()
        spellsAndReadsCommandEntryIDs()
        rowsFollowTheTree()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static let host = ExtensionAPIVersion(major: 1, minor: 2)

    private static func entry(
        _ id: String, _ version: String, api: ExtensionAPIVersion = ExtensionAPIVersion(major: 1, minor: 0)
    ) -> ExtensionIndexFile.Entry {
        ExtensionIndexFile.Entry(
            id: id, name: id, version: version, api: api, description: "A test extension.",
            author: ExtensionManifest.Author(name: "Test", github: "test"), categories: ["test"],
            permissions: [], commands: [ExtensionManifest.Command(name: "run", title: "Run", mode: .view)],
            archive: ExtensionIndexFile.Archive(path: "\(id)/\(version)/\(id).zip", sha256: "", size: 1),
            icon: "\(id)/media/icon.png", screenshots: [], readme: "\(id)/media/readme.md",
            changelog: "\(id)/media/changelog.md")
    }

    private static func index(
        _ entries: [ExtensionIndexFile.Entry], revoked: [ExtensionIndexFile.Revocation] = []
    ) -> ExtensionIndex {
        ExtensionIndex(ExtensionIndexFile(extensions: entries, revoked: revoked), host: host)
    }

    private static func installed(
        _ id: String, _ version: String, pinned: Bool = false
    ) -> ExtensionIndex.Installed {
        ExtensionIndex.Installed(id: id, version: version, isPinned: pinned)
    }

    static func runsItsOwnMajorUpToItsOwnMinor() {
        expect(host.canRun(ExtensionAPIVersion(major: 1, minor: 0)), "an older minor runs")
        expect(host.canRun(ExtensionAPIVersion(major: 1, minor: 2)), "its own minor runs")
        expect(!host.canRun(ExtensionAPIVersion(major: 1, minor: 3)), "a newer minor does not run")
        expect(!host.canRun(ExtensionAPIVersion(major: 2, minor: 0)), "a newer major does not run")
        expect(!host.canRun(ExtensionAPIVersion(major: 0, minor: 9)), "an older major does not run")
    }

    static func comparesVersionsAsNumbers() {
        expect(ExtensionIndex.isVersion("1.10.0", newerThan: "1.9.0"), "1.10.0 is newer than 1.9.0")
        expect(ExtensionIndex.isVersion("2.0.0", newerThan: "1.99.99"), "a major outranks a minor")
        expect(!ExtensionIndex.isVersion("1.2.0", newerThan: "1.2.0"), "a version is not newer than itself")
        expect(!ExtensionIndex.isVersion("1.1.9", newerThan: "1.2.0"), "an older version is not newer")
    }

    static func installsOnlyWhatThisBuildRuns() {
        let runnable = entry("weather", "1.0.0")
        let newer = entry("notes", "1.0.0", api: ExtensionAPIVersion(major: 1, minor: 3))
        let pulled = entry("clock", "1.0.0")
        let index = index(
            [runnable, newer, pulled],
            revoked: [ExtensionIndexFile.Revocation(id: "clock", versions: ["1.0.0"])])
        expect(index.canInstall(runnable), "a runnable entry installs")
        expect(!index.canInstall(newer), "an entry for a newer api does not install")
        expect(!index.canInstall(pulled), "a revoked version does not install")
    }

    static func offersAnUpdateOrHoldsAPinnedOne() {
        let update = entry("weather", "1.3.0")
        let index = index([update])
        expect(
            index.status(of: installed("weather", "1.2.0")) == .update(update), "a newer version is offered")
        expect(
            index.status(of: installed("weather", "1.2.0", pinned: true)) == .pinned(update),
            "a pinned extension holds, the newer version still listed")
        expect(
            index.status(of: installed("weather", "1.3.0")) == .current, "the published version is current")
        expect(
            index.status(of: installed("weather", "1.4.0")) == .current,
            "a version ahead of the index is current")
    }

    static func revokedBeatsEverything() {
        let index = index(
            [entry("weather", "1.3.0")],
            revoked: [ExtensionIndexFile.Revocation(id: "weather", versions: ["1.2.0", "1.3.0"])])
        expect(index.status(of: installed("weather", "1.2.0")) == .revoked, "a revoked install stops")
        expect(
            index.status(of: installed("weather", "1.2.0", pinned: true)) == .revoked,
            "a pin does not keep a revoked version")
        let pulledUpdate = Self.index(
            [entry("weather", "1.3.0")],
            revoked: [ExtensionIndexFile.Revocation(id: "weather", versions: ["1.3.0"])])
        expect(
            pulledUpdate.status(of: installed("weather", "1.2.0")) == .current,
            "a revoked newer version is never offered")
    }

    static func needsANewerTinycastWhenMissingOrNewer() {
        let index = index([entry("weather", "2.0.0", api: ExtensionAPIVersion(major: 2, minor: 0))])
        expect(
            index.status(of: installed("weather", "1.0.0")) == .needsNewerTinycast,
            "an update for a newer api needs a newer Tinycast")
        expect(
            index.status(of: installed("notes", "1.0.0")) == .needsNewerTinycast,
            "an installed extension missing from the index needs a newer Tinycast, never removed")
    }

    static func updatesSkipPinnedAndNewer() {
        let weather = entry("weather", "1.3.0")
        let index = index([
            weather, entry("notes", "1.1.0"),
            entry("clock", "2.0.0", api: ExtensionAPIVersion(major: 2, minor: 0)), entry("todo", "1.0.0")
        ])
        let updates = index.updates(for: [
            installed("weather", "1.2.0"), installed("notes", "1.0.0", pinned: true),
            installed("clock", "1.0.0"), installed("todo", "1.0.0")
        ])
        expect(updates == [weather], "Update All installs only unpinned updates this build runs")
    }

    static func dropsAnEntryItCannotRead() throws {
        let json = """
            {
              "extensions": [
                \(String(bytes: try JSONEncoder().encode(entry("weather", "1.3.0")), encoding: .utf8) ?? ""),
                { "id": "notes", "name": "Notes", "version": "1.1.0", "permissions": ["camera"] }
              ],
              "revoked": []
            }
            """
        let file = try JSONDecoder().decode(ExtensionIndexFile.self, from: Data(json.utf8))
        expect(file.extensions.map(\.id) == ["weather"], "an unreadable entry is dropped, the rest kept")
        let index = ExtensionIndex(file, host: host)
        expect(
            index.status(of: installed("notes", "1.0.0")) == .needsNewerTinycast,
            "the dropped entry's install reads as needing a newer Tinycast")
    }

    static func spellsAndReadsCommandEntryIDs() {
        let id = ExtensionCommandID(extensionID: "hello", command: "copy-greeting")
        expect(
            id.entryID == "extension-command:hello/copy-greeting",
            "an entry ID names the extension, then the command")
        expect(ExtensionCommandID(entryID: id.entryID) == id, "an entry ID reads back as its command")
        let malformed = [
            "extension-command:hello", "extension-command:/greet", "extension-command:hello/",
            "extension-command:a/b/c", "hello/greet", "extension:hello/greet"
        ]
        for malformed in malformed {
            expect(ExtensionCommandID(entryID: malformed) == nil, "\(malformed) is not a command's entry ID")
        }
    }

    static func rowsFollowTheTree() {
        let wave = ExtensionUI.Action(id: "wave", title: "Wave")
        let list = ExtensionUI.list(
            ExtensionUI.List(
                sections: [
                    ExtensionUI.List.Section(items: [
                        ExtensionUI.List.Item(id: "a", title: "A", actions: [wave])
                    ]),
                    ExtensionUI.List.Section(
                        title: "More", items: [ExtensionUI.List.Item(id: "b", title: "B")])
                ], handlesSearch: true, searchPlaceholder: "Find…"))
        expect(list.rows.map(\.id) == ["a", "b"], "a list's rows run through its sections in order")
        expect(list.rows.first?.actions == [wave], "a row carries its item's actions")
        expect(list.handlesSearch && list.searchPlaceholder == "Find…", "a list states its own search")
        let grid = ExtensionUI.grid(
            ExtensionUI.Grid(
                sections: [
                    ExtensionUI.Grid.Section(items: [ExtensionUI.Grid.Item(id: "g", image: .symbol("star"))])
                ],
                columns: 4))
        expect(
            grid.rows.map(\.id) == ["g"] && !grid.handlesSearch,
            "a grid's items are rows, filtered by the host")
        let detail = ExtensionUI.detail(ExtensionUI.Detail(markdown: "# Hi", actions: [wave]))
        expect(
            detail.rows.count == 1 && detail.rows[0].actions == [wave], "a detail is one row with its actions"
        )
        let form = ExtensionUI.form(ExtensionUI.Form(fields: [], actions: [wave]))
        expect(form.rows.isEmpty && form.typeName == "form", "a form has no rows")
    }
}
