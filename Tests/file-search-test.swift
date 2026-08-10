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
        ignoreRules()
        policyResolution()
        resultModel()
        ranking()

        print(failures == 0 ? "File search tests passed" : "\(failures) file search tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func queryGrammar() {
        expect(
            FileSearchQuery.terms(in: "  annual\treport  ") == ["annual", "report"],
            "terms split on whitespace")
        expect(FileSearchQuery.expression(for: " \n ") == nil, "empty input creates no query")
        expect(
            FileSearchQuery.expression(for: "annual report")
                == "kMDItemFSName == \"*annual*\"cd && kMDItemFSName == \"*report*\"cd",
            "every term must occur in the filename")
        let escaped = FileSearchQuery.expression(for: #"a\b\"c*d?e"#)
        let expected =
            "kMDItemFSName == \"*a" + String(repeating: "\\", count: 2) + "b"
            + String(repeating: "\\", count: 3) + "\"c\\*d\\?e*\"cd"
        expect(
            escaped == expected,
            "query metacharacters are escaped: \(String(reflecting: escaped)) != \(String(reflecting: expected))"
        )
        expect(
            FileSearchQuery.expression(for: "report", excluding: ["*.tmp", "*.log"])
                == "kMDItemFSName == \"*report*\"cd && kMDItemFSName != \"*.tmp\"cd"
                + " && kMDItemFSName != \"*.log\"cd",
            "ignored name globs keep their wildcards and join the expression as exclusions")
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
        let shipped = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults)
        for directory in FileSearchIgnoreList.defaults {
            expect(
                FileSearchQuery.isExcludedPath(
                    "/Users/test/Documents/App/\(directory)/file.txt", ignoring: shipped),
                "\(directory) descendants are excluded")
        }
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/App/.git/config", ignoring: shipped),
            "hidden ancestor paths are excluded")
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/Applications/Example.app/Contents/Info.plist", ignoring: shipped),
            "application-bundle contents are excluded")
        expect(
            !FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/Building Plans/target-notes.txt", ignoring: shipped),
            "partial directory-name matches remain searchable")
        expect(
            !FileSearchQuery.isExcludedPath("/Users/test/Documents/Pods.txt", ignoring: shipped),
            "an excluded directory spelling is still valid as a filename")
        expect(
            !FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "an empty list still leaves the structural rules in place")
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/.hidden/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "hidden paths are structural, not a pattern the user can drop")
    }

    static func ignoreRules() {
        let list = FileSearchIgnoreList(patterns: [
            "*.tmp", "**/[Cc]ache/**", "**/build-output/**", "Archive", "  ", "with\0nul"
        ])
        expect(list.excludes(path: "/Users/test/Documents/notes.TMP"), "a name glob folds case")
        expect(
            list.excludes(path: "/Users/test/Documents/scratch.tmp/keep.txt"),
            "a name glob matches at any depth, not only the last component")
        expect(
            list.excludes(path: "/Users/test/Developer/Cache/blob"),
            "a path glob matches a bracketed alternative")
        expect(
            list.excludes(path: "/Users/test/Developer/cache/blob"),
            "a path glob folds case too")
        expect(
            list.excludes(path: "/Users/test/Developer/app/build-output/index.js"),
            "a path glob matches an interior segment")
        expect(list.excludes(path: "/Users/test/archive/old.txt"), "a literal name folds case")
        expect(
            !list.excludes(path: "/Users/test/Documents/tmp-notes.txt"),
            "a name glob is anchored to the whole component, not a substring")
        expect(
            !list.excludes(path: "/Users/test/Documents/Archived/old.txt"),
            "a literal name never matches a longer component")
        expect(
            !FileSearchIgnoreList(patterns: []).excludes(path: "/Users/test/Documents/node_modules/a"),
            "the shipped rules are supplied by the policy, not baked into the matcher")

        expect(
            list.spotlightNameExclusions == ["*.tmp"],
            "only bare `*` name globs are pushed into the Spotlight expression")
        expect(
            FileSearchIgnoreList(patterns: ["?.log", "a[bc].txt", "say\"hi\"", "back\\slash"])
                .spotlightNameExclusions.isEmpty,
            "Spotlight reads `?`, brackets and quotes literally, so those stay local")
    }

    static func policyResolution() {
        let policy = FileSearchPolicy(
            scopes: ["~", "~/Developer", "/Volumes/Work", "~/Developer"],
            ignorePatterns: ["*.log"], homeDirectory: home)
        expect(policy.includesHome, "a configured home root is held apart for expansion")
        expect(
            policy.directRoots.map(\.path) == ["/Users/test/Developer", "/Volumes/Work"],
            "every other root passes through verbatim, deduplicated in order")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/run.log"),
            "a user pattern applies outside home as well")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/node_modules/a.js"),
            "the shipped rules always apply on top of the user's")

        let away = FileSearchPolicy(
            scopes: ["~/Developer"], ignorePatterns: [], homeDirectory: home)
        expect(!away.includesHome, "dropping home drops the expansion with it")
        expect(
            FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: home).directRoots.isEmpty,
            "a cleared list resolves to no roots at all")
        expect(
            FileSearchScope.normalize(
                ["/Users/test/Developer", "~/Developer", "/etc"],
                homeDirectory: home) == ["~/Developer", "/etc"],
            "normalizing abbreviates home and drops the duplicate it creates")
        expect(
            FileSearchScope.expand("~", homeDirectory: home).path == "/Users/test",
            "a bare tilde expands to home itself")
    }

    static func resultModel() {
        let nested = result("Documents/Annual Report.pdf")
        expect(nested.id == "/Users/test/Documents/Annual Report.pdf", "identity is the full path")
        expect(nested.name == "Annual Report.pdf", "the full filename keeps its extension")
        expect(nested.parentPath == "~/Documents", "the parent path abbreviates home")
        expect(result("Notes.txt").parentPath == "~", "a home-root item has a bare tilde parent")
    }

    static func ranking() {
        let shipped = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults)
        let candidates = [
            result("Archive/Report Annual.txt"),
            result("Archive/My Annual Report.txt"),
            result("Archive/Annual Report", folder: true),
            result("Archive/Annual Reporting Notes.txt")
        ]
        let ranked = FileSearchQuery.rank(candidates, for: "annual report", ignoring: shipped)
            .map(\.name)
        expect(ranked.first == "Annual Report", "an exact filename ranks first")
        expect(
            ranked.firstIndex(of: "Annual Reporting Notes.txt")!
                < ranked.firstIndex(of: "My Annual Report.txt")!,
            "a prefix beats a later word-start match")
        expect(ranked.last == "Report Annual.txt", "reversed terms remain present but rank last")

        let ties = FileSearchQuery.rank(
            [result("zeta/report.txt"), result("alpha/Report.txt")], for: "report",
            ignoring: shipped)
        expect(
            ties.map(\.parentPath) == ["~/alpha", "~/zeta"],
            "equal names have a deterministic path tie-break")

        let capped = (0..<205).map { result("Archive/Report \($0).txt") }
        expect(
            FileSearchQuery.rank(capped, for: "report", ignoring: shipped).count == 200,
            "ranking publishes no more than the display cap")

        expect(
            FileSearchQuery.rank(
                [result("Archive/report.txt")], for: "report",
                ignoring: FileSearchIgnoreList(patterns: ["Archive"])
            ).isEmpty,
            "ranking drops what the user's own patterns exclude")
    }
}
