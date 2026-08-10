import Foundation

@main
struct FileSearchTests {
    nonisolated(unsafe) static var failures = 0
    static let home = URL(fileURLWithPath: "/Users/test")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func result(_ path: String, folder: Bool = false) -> FileSearchResult {
        FileSearchResult(url: home.appending(path: path), isDirectory: folder, homeDirectory: home)
    }

    static func main() {
        queryGrammar()
        scopePolicy()
        pathPolicy()
        resultModel()
        ranking()

        print(failures == 0 ? "File search tests passed" : "\(failures) file search tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func queryGrammar() {
        expect(FileSearchQuery.terms(in: "  annual\treport  ") == ["annual", "report"],
            "terms split on whitespace")
        expect(FileSearchQuery.expression(for: " \n ") == nil, "empty input creates no query")
        expect(
            FileSearchQuery.expression(for: "annual report")
                == "kMDItemFSName == \"*annual*\"cd && kMDItemFSName == \"*report*\"cd",
            "every term must occur in the filename")
        let escaped = FileSearchQuery.expression(for: #"a\b\"c*d?e"#)
        let expected = "kMDItemFSName == \"*a" + String(repeating: "\\", count: 2) + "b"
            + String(repeating: "\\", count: 3) + "\"c\\*d\\?e*\"cd"
        expect(
            escaped == expected,
            "query metacharacters are escaped: \(String(reflecting: escaped)) != \(String(reflecting: expected))")
        expect(FileSearchQuery.candidateLimit == 1_000, "the Spotlight candidate cap is fixed")
        expect(FileSearchQuery.resultLimit == 200, "the displayed result cap is fixed")
        expect(
            FileSearchQuery.matches(filename: "Résumé Final.pdf", query: "resume final"),
            "home-root matching mirrors case- and diacritic-insensitive Spotlight terms")
        expect(
            !FileSearchQuery.matches(filename: "Annual Notes.pdf", query: "annual report"),
            "every term is required for a home-root match")
    }

    static func scopePolicy() {
        func candidate(
            _ name: String, directory: Bool, hidden: Bool = false, package: Bool = false,
            application: Bool = false
        ) -> FileSearchScope.Candidate {
            FileSearchScope.Candidate(
                url: home.appending(path: name), isDirectory: directory, isHidden: hidden,
                isPackage: package, isApplication: application)
        }
        let selection = FileSearchScope.select([
            candidate("Documents", directory: true),
            candidate("Developer", directory: true),
            candidate("Library", directory: true),
            candidate(".cache", directory: true, hidden: true),
            candidate("Project.xcodeproj", directory: true, package: true),
            candidate("Local.app", directory: true, package: true, application: true),
            candidate("Notes.txt", directory: false)
        ])
        expect(
            selection.directories.map(\.lastPathComponent) == ["Documents", "Developer"],
            "only visible non-package directories become recursive Spotlight scopes")
        expect(
            selection.rootItems.map(\.url.lastPathComponent)
                == ["Documents", "Developer", "Project.xcodeproj", "Notes.txt"],
            "visible root folders, files and document packages remain direct candidates")
    }

    static func pathPolicy() {
        for directory in FileSearchQuery.excludedDirectoryNames {
            expect(
                FileSearchQuery.isExcludedPath("/Users/test/Documents/App/\(directory)/file.txt"),
                "\(directory) descendants are excluded")
        }
        expect(
            FileSearchQuery.isExcludedPath("/Users/test/Documents/App/.git/config"),
            "hidden ancestor paths are excluded")
        expect(
            FileSearchQuery.isExcludedPath("/Users/test/Applications/Example.app/Contents/Info.plist"),
            "application-bundle contents are excluded")
        expect(
            !FileSearchQuery.isExcludedPath("/Users/test/Documents/Building Plans/target-notes.txt"),
            "partial directory-name matches remain searchable")
        expect(
            !FileSearchQuery.isExcludedPath("/Users/test/Documents/Pods.txt"),
            "an excluded directory spelling is still valid as a filename")
    }

    static func resultModel() {
        let nested = result("Documents/Annual Report.pdf")
        expect(nested.id == "/Users/test/Documents/Annual Report.pdf", "identity is the full path")
        expect(nested.name == "Annual Report.pdf", "the full filename keeps its extension")
        expect(nested.parentPath == "~/Documents", "the parent path abbreviates home")
        expect(result("Notes.txt").parentPath == "~", "a home-root item has a bare tilde parent")
    }

    static func ranking() {
        let candidates = [
            result("Archive/Report Annual.txt"),
            result("Archive/My Annual Report.txt"),
            result("Archive/Annual Report", folder: true),
            result("Archive/Annual Reporting Notes.txt")
        ]
        let ranked = FileSearchQuery.rank(candidates, for: "annual report").map(\.name)
        expect(ranked.first == "Annual Report", "an exact filename ranks first")
        expect(
            ranked.firstIndex(of: "Annual Reporting Notes.txt")!
                < ranked.firstIndex(of: "My Annual Report.txt")!,
            "a prefix beats a later word-start match")
        expect(ranked.last == "Report Annual.txt", "reversed terms remain present but rank last")

        let ties = FileSearchQuery.rank(
            [result("zeta/report.txt"), result("alpha/Report.txt")], for: "report")
        expect(ties.map(\.parentPath) == ["~/alpha", "~/zeta"],
            "equal names have a deterministic path tie-break")

        let capped = (0..<205).map { result("Archive/Report \($0).txt") }
        expect(FileSearchQuery.rank(capped, for: "report").count == 200,
            "ranking publishes no more than the display cap")
    }
}
