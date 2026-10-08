import CoreServices
import Foundation

@main
struct FileIndexTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        walk(fixture)
        try refresh(fixture)
        entryLimit(fixture)
        batching()
        try await liveEvents(fixture)

        print(failures == 0 ? "File index tests passed" : "\(failures) file index tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// A home folder in miniature, resolved through `/private` the way the walk resolves it.
    struct Fixture {
        let home: URL
        let path: String

        init() throws {
            let made = FileManager.default.temporaryDirectory
                .appending(path: "file-index-test-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            path = FileIndexScanner.realPath(made) ?? made.path
            home = URL(fileURLWithPath: path, isDirectory: true)
            for file in [
                "Documents/Report.pdf", "Documents/.secret.txt", "Documents/node_modules/pkg/index.js",
                "Documents/Thing.app/Contents/Info.plist", "Documents/Kit.bundle/inner.txt",
                "Library/Caches/cache.txt", "Projects/Library/kept.txt", "Projects/app/main.swift",
                "Notes.txt", "Concealed/visible-inside.txt"
            ] {
                try write(file)
            }
            try FileManager.default.createSymbolicLink(
                atPath: path + "/Shortcut", withDestinationPath: path + "/Documents")
            var hidden = home.appending(path: "Concealed", directoryHint: .isDirectory)
            var values = URLResourceValues()
            values.isHidden = true
            try hidden.setResourceValues(values)
        }

        func write(_ relative: String) throws {
            let url = home.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(relative.utf8).write(to: url)
        }

        func remove(_ relative: String) { try? FileManager.default.removeItem(at: home.appending(path: relative)) }
        func remove() { try? FileManager.default.removeItem(at: home) }

        var plan: FileIndexScanner.Plan { plan(entryLimit: FileIndexScanner.entryLimit) }

        func plan(entryLimit: Int) -> FileIndexScanner.Plan {
            FileIndexScanner.plan(
                for: FileSearchPolicy(scopes: ["~"], ignorePatterns: [], homeDirectory: home),
                entryLimit: entryLimit)
        }

        func names(_ index: FileNameIndex, _ raw: String) -> [String] {
            index.search(
                FileNameQuery(raw, homeDirectory: home, now: Date()), filter: .all,
                now: UInt32(Date().timeIntervalSince1970), limit: 200, homeDirectory: home
            ).map { $0.id.components(separatedBy: home.lastPathComponent + "/").last! }
        }
    }

    static func walk(_ fixture: Fixture) {
        let plan = fixture.plan
        expect(plan.roots == [fixture.path], "missing cloud roots are dropped: \(plan.roots)")
        expect(plan.homePath == fixture.path, "home is resolved through symlinks")
        let index = FileIndexScanner.build(plan)
        let all = Set(fixture.names(index, "t"))
        expect(fixture.names(index, "report") == ["Documents/Report.pdf"], "a file is indexed")
        expect(fixture.names(index, "notes") == ["Notes.txt"], "a home-root file is indexed")
        expect(fixture.names(index, "secret").isEmpty, "a dot-name is never indexed")
        expect(fixture.names(index, "index.js").isEmpty, "an ignored folder is never walked")
        expect(fixture.names(index, "node_modules").isEmpty, "nor listed")
        expect(fixture.names(index, "thing").isEmpty && fixture.names(index, "info").isEmpty,
               "an app bundle is neither listed nor walked")
        expect(fixture.names(index, "kit") == ["Documents/Kit.bundle"], "a package is one item")
        expect(fixture.names(index, "inner").isEmpty, "and its contents are never walked")
        expect(fixture.names(index, "cache").isEmpty, "home's own Library is left out")
        expect(fixture.names(index, "kept") == ["Projects/Library/kept.txt"],
               "a Library folder anywhere else is ordinary")
        expect(fixture.names(index, "shortcut") == ["Shortcut"], "a symlink is listed")
        expect(!all.contains("Shortcut/Report.pdf"), "but never followed")
        expect(fixture.names(index, "visible-inside").isEmpty, "a UF_HIDDEN folder is left out")
    }

    static func refresh(_ fixture: Fixture) throws {
        let plan = fixture.plan
        var index = FileIndexScanner.build(plan)
        let before = index.entryCount

        try fixture.write("Documents/Fresh Ideas.md")
        var outcome = FileIndexScanner.refresh(
            &index, changes: [.init(path: fixture.path + "/Documents", isRecursive: false)], plan: plan)
        expect(outcome == .applied, "a changed folder is relisted in place")
        expect(fixture.names(index, "fresh") == ["Documents/Fresh Ideas.md"], "a new file appears")
        expect(fixture.names(index, "main") == ["Projects/app/main.swift"],
               "a sibling folder untouched by the event keeps its contents")

        fixture.remove("Projects/app")
        _ = FileIndexScanner.refresh(
            &index, changes: [.init(path: fixture.path + "/Projects", isRecursive: false)], plan: plan)
        expect(fixture.names(index, "main").isEmpty, "a removed folder takes its subtree with it")
        expect(index.entryCount == before - 1, "entries are counted back down: \(index.entryCount)")

        try fixture.write("Projects/deep/er/still.txt")
        _ = FileIndexScanner.refresh(
            &index, changes: [.init(path: fixture.path + "/Projects", isRecursive: true)], plan: plan)
        expect(fixture.names(index, "still") == ["Projects/deep/er/still.txt"],
               "a recursive change walks everything below it")

        let untouched = index.entryCount
        outcome = FileIndexScanner.refresh(
            &index, changes: [.init(path: fixture.path + "/Library/Caches", isRecursive: true)],
            plan: plan)
        expect(outcome == .applied && index.entryCount == untouched,
               "an event in an excluded area changes nothing")
        outcome = FileIndexScanner.refresh(
            &index,
            changes: [.init(path: (fixture.path as NSString).deletingLastPathComponent, isRecursive: true)],
            plan: plan)
        expect(outcome == .needsRebuild, "lost history above a root asks for a full walk")
    }

    static func entryLimit(_ fixture: Fixture) {
        let index = FileIndexScanner.build(fixture.plan(entryLimit: 3))
        expect(index.entryCount <= 3, "the walk stops at the entry cap: \(index.entryCount)")
    }

    static func batching() {
        let none = FSEventStreamEventFlags(kFSEventStreamEventFlagNone)
        let deep = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        let batch = FileEventMonitor.batch(
            paths: ["/a/b/", "/a/c", "/a/b", "/"], flags: [none, none, deep, none])
        expect(
            batch == .changes([
                .init(path: "/a/b", isRecursive: true), .init(path: "/a/c", isRecursive: false),
                .init(path: "/", isRecursive: false)
            ]),
            "paths are trimmed and coalesced, keeping the strongest flag: \(batch)")
        expect(
            FileEventMonitor.batch(
                paths: ["/a", "/b"],
                flags: [none, FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)])
                == .rebuild,
            "a dropped event means the history can no longer be trusted")
    }

    static func liveEvents(_ fixture: Fixture) async throws {
        let events = FileEventMonitor.batches(for: [fixture.path], latency: 0.05)
        let watcher = Task { () -> Bool in
            for await batch in events {
                if case .changes(let changes) = batch,
                    changes.contains(where: { $0.path == fixture.path + "/Projects" })
                {
                    return true
                }
            }
            return false
        }
        try? await Task.sleep(for: .milliseconds(300))
        try fixture.write("Projects/live.txt")
        let timeout = Task {
            try? await Task.sleep(for: .seconds(10))
            watcher.cancel()
        }
        let delivered = await watcher.value
        timeout.cancel()
        expect(delivered, "FSEvents reports the folder a new file landed in")
    }
}
