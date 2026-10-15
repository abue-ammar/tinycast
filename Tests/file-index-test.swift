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

    static func main() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appending(path: "file-index-test-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let root = URL(fileURLWithPath: realPath(scratch.path)).appending(path: "home")
        for file in [
            "Documents/Annual Report.pdf", "Documents/notes.txt", "Documents/Résumé.pdf",
            "Developer/app/src/main.swift", "Developer/app/node_modules/pkg/index.js",
            "Developer/app/.git/config", "Movies/clip.mov", "Pictures/beach.png",
            "Documents/Archive/todo.md", "Pictures/todo.md"
        ] {
            try write(root.appending(path: file))
        }

        let policy = FileSearchPolicy(
            scopes: [root.path], ignorePatterns: ["~/Movies"], homeDirectory: root)
        let index = FileIndex()
        let snapshot = try build(policy, at: scratch.appending(path: "index.bin"))
        index.replace(with: snapshot, policy: policy)

        layout(snapshot, root: root.path)
        search(index, root: root.path)
        try live(index, root: root, policy: policy)

        print(failures == 0 ? "File index tests passed" : "\(failures) file index tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func build(_ policy: FileSearchPolicy, at url: URL) throws -> FileIndexSnapshot {
        let roots = FileIndexCrawler.roots(of: policy)
        let listings = FileIndexCrawler.Crawl(roots: roots, policy: policy).run(workers: 4)
        try FileIndexSnapshot.write(
            listings, roots: roots, eventID: 42, fingerprint: policy.fingerprint, to: url)
        guard let snapshot = FileIndexSnapshot(contentsOf: url) else {
            expect(false, "the written index maps back")
            exit(1)
        }
        return snapshot
    }

    static func layout(_ snapshot: FileIndexSnapshot, root: String) {
        expect(snapshot.eventID == 42, "the header keeps the event id")
        expect(snapshot.roots == [root], "the root is stored as its full path")
        let main = snapshot.lookup(root + "/Developer/app/src/main.swift")
        expect(main != nil, "lookup walks the blocks")
        expect(
            main.map(snapshot.path(of:)) == root + "/Developer/app/src/main.swift",
            "a path round-trips")
        expect(snapshot.lookup(root + "/Developer/app/.git/config") != nil, "hidden files are indexed")
        expect(snapshot.lookup(root + "/Developer/app/node_modules") == nil, "a shipped rule skips")
        expect(snapshot.lookup(root + "/Movies") == nil, "a tilde path skips that folder")
        if let developer = snapshot.lookup(root + "/Developer"), let main {
            expect(snapshot.subtree(of: developer).contains(main), "a subtree is one range")
        }
        expect(snapshot.entryCount - snapshot.rootCount == 15, "every kept entry is written once")
        expect(snapshot.nameCount == snapshot.entryCount - 1, "a repeated name is stored once")
        let todo = snapshot.lookup(root + "/Pictures/todo.md")
        expect(todo.map(snapshot.path(of:)) == root + "/Pictures/todo.md", "a shared name keeps its path")
        expect(
            snapshot.children(of: snapshot.lookup(root + "/Documents/notes.txt")!).isEmpty,
            "a file has no children")
    }

    static func search(_ index: FileIndex, root: String) {
        expect(names(index, "main").first == "main.swift", "a name search finds the file")
        expect(names(index, "resume") == ["Résumé.pdf"], "accents fold")
        expect(names(index, "todo") == ["todo.md", "todo.md"], "every entry with a shared name is found")
        expect(names(index, "annual report") == ["Annual Report.pdf"], "terms combine")
        expect(names(index, "report", filter: .images).isEmpty, "the filter narrows")
        expect(names(index, "beach", filter: .images) == ["beach.png"], "an image is an image")
        expect(names(index, "app", filter: .folders) == ["app"], "Folders keeps folders only")
        let recent = index.recent(filter: .all).map(\.name)
        expect(recent.contains("notes.txt"), "recent lists files under home")
        expect(!recent.contains("config"), "recent leaves hidden files out")
        expect(index.itemCount == 15, "the count matches the snapshot")
    }

    static func live(_ index: FileIndex, root: URL, policy: FileSearchPolicy) throws {
        let documents = root.appending(path: "Documents")
        let revision = index.recentRevision
        try write(documents.appending(path: "new-plan.md"))
        index.apply(folder: documents.path)
        expect(names(index, "new-plan") == ["new-plan.md"], "a new file appears")
        let added = index.recentRevision
        expect(added != revision, "a new home file moves Recent")
        index.apply(folder: documents.path)
        expect(index.itemCount == 16 && index.recentRevision == added, "applying twice changes nothing")

        try FileManager.default.removeItem(at: documents.appending(path: "notes.txt"))
        index.apply(folder: documents.path)
        expect(names(index, "notes").isEmpty, "a deleted file goes")

        let developer = root.appending(path: "Developer")
        try FileManager.default.moveItem(
            at: developer.appending(path: "app"), to: developer.appending(path: "application"))
        index.apply(folder: developer.path)
        let main = index.search(FileSearchQuery.prepare("main.swift")!, filter: .all)
        expect(
            main.map(\.parentPath) == ["~/Developer/application/src"],
            "a renamed folder moves its whole subtree")

        let report = documents.appending(path: "Annual Report.pdf")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(3_600)], ofItemAtPath: report.path)
        let undated = index.recentRevision
        index.apply(folder: documents.path)
        expect(index.recent(filter: .all).first?.name == "Annual Report.pdf", "an edit dates a file")
        expect(index.recentRevision != undated, "and moves Recent")

        let git = root.appending(path: "Developer/application/.git")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(7_200)],
            ofItemAtPath: git.appending(path: "config").path)
        let churn = index.itemCount
        let dated = index.recentRevision
        expect(
            !index.apply(folder: git.path) && index.itemCount == churn && index.recentRevision == dated,
            "a new date outside Recent's reach changes nothing")
        try write(git.appending(path: "HEAD"))
        index.apply(folder: git.path)
        expect(
            index.itemCount == churn + 1 && index.recentRevision == dated,
            "a hidden file counts but leaves Recent alone")

        try write(documents.appending(path: "Trip/Photos/sunset.jpg"))
        index.apply(folder: documents.path)
        expect(names(index, "sunset") == ["sunset.jpg"], "a new folder is crawled whole")
        try FileManager.default.removeItem(at: documents.appending(path: "Trip"))
        index.apply(folder: documents.path)
        expect(names(index, "sunset").isEmpty && names(index, "trip").isEmpty, "and removed whole")

        let before = index.itemCount
        index.apply(folder: developer.path, recursive: true)
        expect(index.itemCount == before, "a recursive rescan of an unchanged tree changes nothing")
        expect(
            !index.apply(folder: developer.path + "/application/node_modules"),
            "an event in a skipped folder is ignored")
    }

    static func names(
        _ index: FileIndex, _ query: String, filter: FileSearchFilter = .all
    ) -> [String] {
        index.search(FileSearchQuery.prepare(query)!, filter: filter).map(\.name)
    }

    static func write(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
