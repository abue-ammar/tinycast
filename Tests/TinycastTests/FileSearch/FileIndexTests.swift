import Foundation
import Testing

@testable import Tinycast

struct FileIndexTests {
    @Test func mappedSnapshotKeepsTheTreeAndInternsSharedNames() throws {
        let fixture = try IndexedHome()
        let snapshot = fixture.snapshot
        let root = fixture.root.path
        #expect(snapshot.eventID == 42)
        #expect(snapshot.roots == [root])
        #expect(snapshot.entryCount - snapshot.rootCount == 15)
        #expect(snapshot.nameCount == snapshot.entryCount - 1)

        let mainPath = root + "/Developer/app/src/main.swift"
        let main = try #require(snapshot.lookup(mainPath))
        let developer = try #require(snapshot.lookup(root + "/Developer"))
        #expect(snapshot.path(of: main) == mainPath)
        #expect(snapshot.subtree(of: developer).contains(main))
        #expect(snapshot.lookup(root + "/Developer/app/.git/config") != nil)
        #expect(snapshot.lookup(root + "/Developer/app/node_modules") == nil)
        #expect(snapshot.lookup(root + "/Movies") == nil)

        let todoPath = root + "/Pictures/todo.md"
        let todo = try #require(snapshot.lookup(todoPath))
        #expect(snapshot.path(of: todo) == todoPath)
        let notes = try #require(snapshot.lookup(root + "/Documents/notes.txt"))
        #expect(snapshot.children(of: notes).isEmpty)
    }

    @Test(arguments: [
        ("resume", FileSearchFilter.all, ["Résumé.pdf"]),
        ("todo", .all, ["todo.md", "todo.md"]),
        ("annual report", .all, ["Annual Report.pdf"]),
        ("report", .images, []),
        ("beach", .images, ["beach.png"]),
        ("app", .folders, ["app"])
    ])
    func searchesTheMappedIndex(_ query: String, _ filter: FileSearchFilter, _ expected: [String]) throws {
        let fixture = try IndexedHome()
        let results = try results(in: fixture.index, matching: query, filter: filter)
        #expect(results.map(\.name) == expected)
    }

    @Test func aFilenameMatchLeadsTheResults() throws {
        let fixture = try IndexedHome()
        let row = try #require(try results(in: fixture.index, matching: "main").first)
        #expect(row.name == "main.swift")
    }

    @Test func pathSearchCoversAbsoluteHomeRelativeAndFileURLs() throws {
        let fixture = try IndexedHome()
        let index = fixture.index
        let root = fixture.root.path
        #expect(try displayedPaths(in: index, matching: root + "/Documents/") == ["~/Documents"])
        #expect(try displayedPaths(in: index, matching: "~/Documents/notes.txt") == ["~/Documents/notes.txt"])
        #expect(try displayedPaths(in: index, matching: "file://" + root + "/Movies") == ["~/Movies"])
        #expect(try displayedPaths(in: index, matching: root + "/Missing").isEmpty)
        #expect(try results(in: index, matching: root + "/Pictures/beach.png", filter: .documents).isEmpty)
        #expect(
            try displayedPaths(in: index, matching: "Documents/Archive/todo") == [
                "~/Documents/Archive/todo.md"
            ])
    }

    @Test func exactRootAndHomePathsAreResults() throws {
        let fixture = try IndexedHome()
        #expect(try results(in: fixture.index, matching: "/").map(\.id) == ["/"])
        #expect(try results(in: fixture.index, matching: "~/").map(\.id) == [fixture.root.path])
    }

    @Test(.enabled(if: caseInsensitiveScratchVolume, "Temporary volume uses case-insensitive names"))
    func exactMatchUsesTheSpellingOnDiskAndDeduplicatesTheIndexHit() throws {
        let fixture = try IndexedHome()
        let alternate = fixture.root.appending(path: "documents/NOTES.TXT")
        #expect(FileManager.default.fileExists(atPath: alternate.path))
        #expect(
            try displayedPaths(in: fixture.index, matching: "~/documents/NOTES.TXT") == [
                "~/Documents/notes.txt"
            ])
    }

    @Test func exactPathsFollowSymlinksBeforeParentTraversal() throws {
        let fixture = try IndexedHome()
        let paths = try PathFixture(in: fixture.directory)
        let index = fixture.index
        #expect(
            try results(in: index, matching: paths.link.path + "/../Report.txt").map(\.id) == [
                paths.report.path
            ])
        #expect(try results(in: index, matching: paths.link.path).map(\.id) == [paths.link.path])
        #expect(try results(in: index, matching: fixture.directory.path + "/Missing/../Report.txt").isEmpty)
    }

    @Test func exactPathsRejectFileSlashesNULsAndRemoteURLs() throws {
        let fixture = try IndexedHome()
        let paths = try PathFixture(in: fixture.directory)
        let index = fixture.index
        #expect(try results(in: index, matching: paths.otherReport.path + "/").isEmpty)
        #expect(try results(in: index, matching: paths.otherReport.absoluteString + "%00extra").isEmpty)
        #expect(try results(in: index, matching: "file://other-mac.example" + paths.otherReport.path).isEmpty)
    }

    @Test func exactLookupBeforeTheFirstCrawlRequiresAnActivePolicy() throws {
        let fixture = try IndexedHome()
        let paths = try PathFixture(in: fixture.directory)
        let index = FileIndex()
        index.replace(with: nil, policy: fixture.policy)
        #expect(
            try results(in: index, matching: paths.otherReport.path).map(\.id) == [paths.otherReport.path])
        #expect(try results(in: index, matching: "Report").isEmpty)

        index.replace(with: nil, policy: nil)
        #expect(try results(in: index, matching: paths.otherReport.path).isEmpty)
    }

    @Test func recentListsVisibleHomeFilesAndCountMatchesTheSnapshot() throws {
        let fixture = try IndexedHome()
        let recent = fixture.index.recent(filter: .all).map(\.name)
        #expect(recent.contains("notes.txt"))
        #expect(!recent.contains("config"))
        #expect(fixture.index.itemCount == 15)
    }

    @Test func aNewFileChangesRecentOnceAndADeletedFileDisappears() throws {
        let fixture = try IndexedHome()
        let index = fixture.index
        let documents = fixture.root.appending(path: "Documents")
        let before = index.recentRevision

        try Self.write(documents.appending(path: "new-plan.md"))
        index.apply(folder: documents.path)
        #expect(try results(in: index, matching: "new-plan").map(\.name) == ["new-plan.md"])
        let added = index.recentRevision
        #expect(added != before)

        index.apply(folder: documents.path)
        #expect(index.itemCount == 16)
        #expect(index.recentRevision == added)

        try FileManager.default.removeItem(at: documents.appending(path: "notes.txt"))
        index.apply(folder: documents.path)
        #expect(try results(in: index, matching: "notes").isEmpty)
    }

    @Test func aFolderRenameMovesItsSubtreeAndAnUnchangedRescanDoesNoWork() throws {
        let fixture = try IndexedHome()
        let index = fixture.index
        let folder = fixture.root.appending(path: "Developer")
        try FileManager.default.moveItem(
            at: folder.appending(path: "app"), to: folder.appending(path: "application"))
        index.apply(folder: folder.path)
        #expect(
            try results(in: index, matching: "main.swift").map(\.parentPath) == [
                "~/Developer/application/src"
            ])

        let count = index.itemCount
        index.apply(folder: folder.path, recursive: true)
        #expect(index.itemCount == count)
        #expect(!index.apply(folder: folder.path + "/application/node_modules"))
    }

    @Test func onlyVisibleHomeFileEditsMoveRecent() throws {
        let fixture = try IndexedHome()
        let index = fixture.index
        let documents = fixture.root.appending(path: "Documents")
        let before = index.recentRevision
        let report = documents.appending(path: "Annual Report.pdf")
        try FileManager.default.setAttributes(
            [.modificationDate: Self.stamp + 3_600], ofItemAtPath: report.path)
        index.apply(folder: documents.path)

        let recent = try #require(index.recent(filter: .all).first)
        #expect(recent.name == "Annual Report.pdf")
        let dated = index.recentRevision
        #expect(dated != before)

        let developer = fixture.root.appending(path: "Developer")
        try FileManager.default.moveItem(
            at: developer.appending(path: "app"), to: developer.appending(path: "application"))
        index.apply(folder: developer.path)
        let git = developer.appending(path: "application/.git")
        try FileManager.default.setAttributes(
            [.modificationDate: Self.stamp + 7_200], ofItemAtPath: git.appending(path: "config").path)
        let churn = index.itemCount
        let renamed = index.recentRevision
        #expect(!index.apply(folder: git.path))
        #expect(index.itemCount == churn)
        #expect(index.recentRevision == renamed)

        try Self.write(git.appending(path: "HEAD"))
        index.apply(folder: git.path)
        #expect(index.itemCount == churn + 1)
        #expect(index.recentRevision == renamed)
    }

    @Test func liveFolderChangesAddAndRemoveTheirDescendants() throws {
        let fixture = try IndexedHome()
        let index = fixture.index
        let documents = fixture.root.appending(path: "Documents")
        try Self.write(documents.appending(path: "Trip/Photos/sunset.jpg"))
        index.apply(folder: documents.path)
        #expect(try results(in: index, matching: "sunset").map(\.name) == ["sunset.jpg"])

        try FileManager.default.removeItem(at: documents.appending(path: "Trip"))
        index.apply(folder: documents.path)
        #expect(try results(in: index, matching: "sunset").isEmpty)
        #expect(try results(in: index, matching: "trip").isEmpty)
    }

    @Test func hiddenFilesAreExcludedFromTheInitialCrawlAndLiveUpdates() throws {
        let fixture = try AgentFolders()
        let index = try fixture.index(includesHidden: false)
        #expect(index.itemCount == 3)
        #expect(try displayedPaths(in: index, matching: "claude surge skill").isEmpty)

        let root = fixture.root
        try Self.write(root.appending(path: ".bashrc"))
        index.apply(folder: root.path)
        try Self.write(root.appending(path: ".claude/skills/surge/notes.md"))
        #expect(!index.apply(folder: root.appending(path: ".claude/skills/surge").path))
        #expect(index.itemCount == 3)
    }

    @Test func ancestorWordsCompleteMultiTermMatchesAndNameMatchesRankFirst() throws {
        let fixture = try AgentFolders()
        try Self.write(fixture.root.appending(path: ".bashrc"))
        try Self.write(fixture.root.appending(path: ".claude/skills/surge/notes.md"))
        let index = try fixture.index(includesHidden: true)

        #expect(
            try displayedPaths(in: index, matching: "claude surge skill") == [
                "~/.claude/skills/surge", "~/.claude/skills/surge/SKILL.md"
            ])
        #expect(try displayedPaths(in: index, matching: "laude surge skill").isEmpty)
        #expect(try displayedPaths(in: index, matching: "worktrees skill").isEmpty)
        let surge = try displayedPaths(in: index, matching: "surge skill")
        let first = try #require(surge.first)
        #expect(first == "~/Projects/surge-skill.md")
        #expect(
            Set(surge.dropFirst()) == [
                "~/.claude/skills/surge", "~/.codex/skills/surge", "~/.claude/skills/surge/SKILL.md",
                "~/.codex/skills/surge/SKILL.md"
            ])
        let skill = try displayedPaths(in: index, matching: "skill")
        #expect(skill.allSatisfy { $0.lowercased().contains("skill") })

        try Self.write(fixture.root.appending(path: ".claude/skills/forge/SKILL.md"))
        index.apply(folder: fixture.root.appending(path: ".claude/skills").path)
        #expect(
            try displayedPaths(in: index, matching: "claude forge skill") == [
                "~/.claude/skills/forge", "~/.claude/skills/forge/SKILL.md"
            ])
    }

    private static let caseInsensitiveScratchVolume =
        (try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [
            .volumeSupportsCaseSensitiveNamesKey
        ]))?
        .volumeSupportsCaseSensitiveNames == false

    private static let stamp = Date(timeIntervalSince1970: 2_000_000_000)

    private static func canonicalDirectory(_ scratch: ScratchDirectory) throws -> URL {
        let values = try scratch.url.resourceValues(forKeys: [.canonicalPathKey])
        let path = try #require(values.canonicalPath)
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    private func results(
        in index: FileIndex, matching query: String, filter: FileSearchFilter = .all
    ) throws -> [FileSearchResult] {
        let prepared = try #require(FileSearchQuery.prepare(query))
        return index.search(prepared, filter: filter)
    }

    private func displayedPaths(in index: FileIndex, matching query: String) throws -> [String] {
        try results(in: index, matching: query).map { "\($0.parentPath)/\($0.name)" }
    }

    private static func write(_ file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
    }

    private static func snapshot(for policy: FileSearchPolicy, at file: URL) throws -> FileIndexSnapshot {
        let roots = FileIndexCrawler.roots(of: policy)
        let listings = FileIndexCrawler.Crawl(roots: roots, policy: policy).run(workers: 4)
        try FileIndexSnapshot.write(
            listings, roots: roots, eventID: 42, fingerprint: policy.fingerprint, to: file)
        return try #require(FileIndexSnapshot(contentsOf: file))
    }

    private struct IndexedHome {
        let scratch: ScratchDirectory
        let index = FileIndex()
        let root: URL
        let policy: FileSearchPolicy
        let snapshot: FileIndexSnapshot
        let directory: URL

        init() throws {
            let scratch = try ScratchDirectory("index")
            self.scratch = scratch
            directory = try FileIndexTests.canonicalDirectory(scratch)
            root = directory.appending(path: "home")
            for path in [
                "Documents/Annual Report.pdf", "Documents/notes.txt", "Documents/Résumé.pdf",
                "Developer/app/src/main.swift", "Developer/app/node_modules/pkg/index.js",
                "Developer/app/.git/config", "Movies/clip.mov", "Pictures/beach.png",
                "Documents/Archive/todo.md", "Pictures/todo.md"
            ] {
                try FileIndexTests.write(root.appending(path: path))
            }
            policy = FileSearchPolicy(
                scopes: [root.path], ignorePatterns: ["node_modules", "~/Movies"], includesHiddenFiles: true,
                homeDirectory: root)
            snapshot = try FileIndexTests.snapshot(for: policy, at: directory.appending(path: "index.bin"))
            index.replace(with: snapshot, policy: policy)
        }
    }

    private struct PathFixture {
        let link: URL
        let report: URL
        let otherReport: URL

        init(in directory: URL) throws {
            link = directory.appending(path: "Link")
            report = directory.appending(path: "Actual/Report.txt")
            otherReport = directory.appending(path: "Report.txt")
            let nested = directory.appending(path: "Actual/Nested")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try FileIndexTests.write(report)
            try FileIndexTests.write(otherReport)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: nested)
        }
    }

    private struct AgentFolders {
        let scratch: ScratchDirectory
        let root: URL

        init() throws {
            let scratch = try ScratchDirectory("index-agents")
            self.scratch = scratch
            root = try FileIndexTests.canonicalDirectory(scratch).appending(path: "agents")
            for path in [
                ".claude/skills/surge/SKILL.md", ".claude/skills/review/SKILL.md",
                ".codex/skills/surge/SKILL.md", "Projects/surge-skill.md",
                "Projects/app/.claude/worktrees/copy/skills/surge/SKILL.md", ".zshrc"
            ] {
                try FileIndexTests.write(root.appending(path: path))
            }
        }

        func index(includesHidden: Bool) throws -> FileIndex {
            let policy = FileSearchPolicy(
                scopes: [root.path], ignorePatterns: FileSearchIgnoreList.defaults,
                includesHiddenFiles: includesHidden, homeDirectory: root)
            let file = scratch.url.appending(path: includesHidden ? "hidden.bin" : "visible.bin")
            let index = FileIndex()
            index.replace(with: try FileIndexTests.snapshot(for: policy, at: file), policy: policy)
            return index
        }
    }
}
