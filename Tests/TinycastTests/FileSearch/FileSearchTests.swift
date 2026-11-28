import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Tinycast

struct FileSearchTests {
    private let home = URL(filePath: "/Users/test")

    @Test(arguments: [
        ("ab", false), ("abc", true), ("  ab \n", false), ("/", true), ("~", true), ("~/", true),
        ("/a", false)
    ])
    func launcherThresholdCountsTrimmedCharactersAndAdmitsBarePaths(_ query: String, _ expected: Bool) {
        #expect(FileSearchQuery.answersLauncher(query) == expected)
    }

    @Test func theLauncherListsTheExactRootForATermlessPath() {
        let file = row("Documents/Résumé Final.pdf")
        let root = FileSearchResult(url: URL(filePath: "/"), isDirectory: true, homeDirectory: home)
        #expect(FileSearchQuery.launcherResults("/", favorites: [file], indexed: [root]) == [root])
    }

    @Test(arguments: [("", false), ("ré", true)])
    func theLauncherSearchesOnlyFavoritesForShortNonblankQueries(_ query: String, _ searchesFavorites: Bool) {
        let favorites = [row("Documents/Résumé", directory: true), row("Documents/Résumé Final.pdf")]
        let indexed = [row("Downloads/Resume.txt")]
        let expected = searchesFavorites ? favorites : []
        #expect(FileSearchQuery.launcherResults(query, favorites: favorites, indexed: indexed) == expected)
    }

    @Test func theLauncherMergesIndexedRowsWithoutRepeatingFavoritePaths() {
        let folder = row("Documents/Résumé", directory: true)
        let file = row("Documents/Résumé Final.pdf")
        let downloaded = row("Downloads/Resume.txt")
        #expect(
            FileSearchQuery.launcherResults("resume", favorites: [folder, file], indexed: [file, downloaded])
                == [folder, file, downloaded])
    }

    @Test func everyTermMustMatchTheFavoriteFilenameAndTheSectionIsCapped() {
        let file = row("Documents/Résumé Final.pdf")
        let favorites = [row("Documents/Résumé", directory: true), file]
        #expect(FileSearchQuery.launcherResults("resume final", favorites: favorites, indexed: []) == [file])
        #expect(FileSearchQuery.launcherResults("documents", favorites: favorites, indexed: []).isEmpty)

        let notes = (0..<10).map { row("Note \($0).txt") }
        #expect(
            FileSearchQuery.launcherResults("note", favorites: notes, indexed: []).count
                == FileSearchQuery.launcherLimit)
    }

    @Test(arguments: [
        ("  annual\treport  ", ["annual", "report"]), ("Dev/tinycast/App", ["Dev", "tinycast", "App"]),
        ("~/.claude/skills", [".claude", "skills"]), ("~", [])
    ])
    func queryTermsSplitAtWhitespaceAndSlashesAndSkipTheHomePrefix(_ query: String, _ expected: [String]) {
        #expect(FileSearchQuery.terms(in: query) == expected)
    }

    @Test func wholeQueryFoldsCaseAndCollapsesWhitespace() throws {
        #expect(FileSearchQuery.prepare(" \n ") == nil)
        let prepared = try #require(FileSearchQuery.prepare("Annual  Report"))
        #expect(prepared.whole == Array("annual report".utf8))
    }

    @Test(arguments: [
        ("annual report", "My Annual Report.pdf", true), ("annual report", "Annual Notes.pdf", false),
        ("readme", "README.md", true), ("resume final", "Résumé Final.pdf", true),
        ("RÉSUMÉ", "resume.txt", true), ("report", "rep-ort.txt", false)
    ])
    func everyFoldedTermMustBeAContiguousSubstring(_ query: String, _ name: String, _ expected: Bool) throws {
        #expect((try score(query, name) != nil) == expected)
    }

    @Test func theNameMaskIncludesFoldedLettersAndFlagsNonASCII() throws {
        var name = "Résumé"
        let mask = name.withUTF8(FileSearchQuery.nameMask)
        let query = try #require(FileSearchQuery.prepare("resume"))
        #expect(mask & query.mask == query.mask)
        #expect(mask & FileSearchQuery.nonASCIIBit != 0)
    }

    @Test func literalByteSearchFindsTheFirstCaseInsensitiveOccurrence() {
        var name = "xxABCabc"
        let offset = name.withUTF8 { FileSearchQuery.find(Array("abc".utf8), in: $0) }
        #expect(offset == 2)
    }

    @Test(arguments: [
        (" ~/.claude \n", "~/.claude"), ("~", "~"), ("/Users/test/My Notes", "/Users/test/My Notes"),
        ("file:///Users/test/My%20Notes/", "/Users/test/My Notes/"),
        ("FILE://LOCALHOST/Users/test", "/Users/test"),
        ("/private/tmp/../tmp/x", "/private/tmp/../tmp/x")
    ])
    func localPathsKeepDecodedNamesSlashesAndDotSegments(_ query: String, _ expected: String) throws {
        let prepared = try #require(FileSearchQuery.prepare(query))
        #expect(prepared.location == expected)
    }

    @Test(arguments: [
        "Dev/tinycast", "~report", "https://example.com/a", "file://other-mac.example/Users/test",
        "file://%FF/Users/test", "file:////other-mac/path", "file:///Users/test%2Ffoo",
        "file:///Users/test#other", "file:///Users/test?%FF"
    ])
    func relativeRemoteAndMalformedPathsDoNotNameALocation(_ query: String) {
        #expect(FileSearchQuery.prepare(query)?.location == nil)
    }

    @Test(arguments: ["/", "~/"])
    func rootPathsPrepareALocationWithoutTerms(_ path: String) throws {
        let prepared = try #require(FileSearchQuery.prepare(path))
        #expect(prepared.terms.isEmpty)
        #expect(prepared.location == path)
    }

    @Test(arguments: [
        ("claude surge skill", true), ("skill", false), ("a b c d e f g h i", false)
    ])
    func onlyRepresentableMultiTermQueriesReachFolders(_ query: String, _ reachesFolders: Bool) throws {
        let prepared = try #require(FileSearchQuery.prepare(query))
        #expect(prepared.reachesFolders == reachesFolders)
        if reachesFolders { #expect(prepared.everyTerm == 0b111) }
    }

    @Test(
        arguments: [
            ("claude surge skill", ".claude", 0b001, 0b001), ("claude surge skill", "skills", 0b100, 0b100),
            ("laude skill", ".claude", 0b01, 0), ("map", "bitmap-map", nil, 0b1),
            ("projects resume", "Résumé", 0b10, nil)
        ] as [(String, String, UInt8?, UInt8?)])
    func termMasksTrackAllOccurrencesAndWordStarts(
        _ query: String, _ name: String, _ held: UInt8?, _ starts: UInt8?
    ) throws {
        let prepared = try #require(FileSearchQuery.prepare(query))
        var name = name
        let hits = name.withUTF8 {
            FileSearchQuery.hits(prepared, name: $0, mask: FileSearchQuery.nameMask($0))
        }
        if let held { #expect(hits.held == held) }
        if let starts { #expect(hits.startingWords == starts) }
    }

    @Test func aNameThatCompletesAncestorTermsStillRanksByItsOwnWordBoundaries() throws {
        let exact = try #require(try score("claude skills", "skills", holding: 0b10))
        let word = try #require(try score("claude skill", "SKILL.md", holding: 0b10))
        let prefix = try #require(try score("claude skill", "skillful.md", holding: 0b10))
        #expect(exact > word)
        #expect(word > prefix)
        #expect(try score("claude skill", "notes.md", holding: 0b10) == nil)
    }

    @Test func exactNamesRankBeforePrefixesWordStartsAndInnerMatches() throws {
        let exact = try #require(try score("report", "report"))
        let prefix = try #require(try score("report", "report.pdf"))
        let boundary = try #require(try score("report", "Annual report.pdf"))
        let inner = try #require(try score("report", "misreported.txt"))
        #expect(exact > prefix)
        #expect(prefix > boundary)
        #expect(boundary > inner)
    }

    @Test(
        arguments: [
            ("report", "report.pdf", "reporting.pdf", 2),
            ("index", "fileIndex.swift", "reindexer.swift", 2),
            ("annual report", "Annual Report 2024.pdf", "Report Annual.pdf", 2),
            ("notes", "notes.txt", "my notes.txt", 0)
        ] as [(String, String, String, Int8)])
    func wordBoundariesTermOrderAndAlignmentBreakTies(
        _ query: String, _ higher: String, _ lower: String, _ prior: Int8
    ) throws {
        let first = try #require(try score(query, higher, prior: prior))
        let second = try #require(try score(query, lower, prior: prior))
        #expect(first > second)
    }

    @Test func aLocationPriorChangesTheNameScoreByItsWeight() throws {
        let preferred = try #require(try score("notes", "notes.txt", prior: 2))
        let ordinary = try #require(try score("notes", "notes.txt", prior: 0))
        #expect(preferred - ordinary == 3_000)
    }

    @Test(
        arguments: [
            (.all, nil, false, true), (.folders, .folder, true, true), (.folders, nil, true, true),
            (.folders, .png, false, false), (.images, .png, false, true), (.images, .mp3, false, false),
            (.documents, .swiftSource, false, true)
        ] as [(FileSearchFilter, UTType?, Bool, Bool)])
    func typeFiltersAdmitMatchingTypesAndUnresolvedFolders(
        _ filter: FileSearchFilter, _ type: UTType?, _ directory: Bool, _ expected: Bool
    ) {
        #expect(filter.accepts(contentType: type, isDirectory: directory) == expected)
    }

    @Test func filesUseTheirExtensionAndPlainDirectoriesKeepTheirFolderType() throws {
        let png = try #require(FileSearchFilter.contentType(extension: "png", isDirectory: false))
        #expect(png.conforms(to: .image))
        #expect(FileSearchFilter.contentType(extension: "", isDirectory: true) == .folder)
        #expect(FileSearchFilter.contentType(extension: "v2", isDirectory: true) == .folder)
    }

    @Test func documentPackagesFilterAsDocuments() throws {
        let rtfd = try #require(FileSearchFilter.contentType(extension: "rtfd", isDirectory: true))
        #expect(FileSearchFilter.documents.accepts(contentType: rtfd, isDirectory: true))
        #expect(!FileSearchFilter.folders.accepts(contentType: rtfd, isDirectory: true))
    }

    @Test(arguments: [
        ("notes.TMP", "/Users/test/notes.TMP", true), ("archive", "/x/archive", true),
        ("Archived", "/x/Archived", false), ("tmp-notes.txt", "/x/tmp-notes.txt", false),
        ("blob", "/Users/test/Developer/Cache/blob", true), ("Movies", "/Users/test/Movies", true),
        ("Movies", "/Users/test/Documents/Movies", false)
    ])
    func ignoreRulesFoldCaseAndMatchWholeNamesOrScopedPaths(_ name: String, _ path: String, _ expected: Bool)
    {
        let ignore = FileSearchIgnoreList(
            patterns: ["*.tmp", "**/[Cc]ache/**", "Archive", "~/Movies", "  ", "with\0nul"],
            homeDirectory: home)
        #expect(ignore.excludes(name: name, path: path) == expected)
    }

    @Test(arguments: FileSearchIgnoreList.defaults.filter { !$0.contains("/") })
    func shippedNameRulesExcludeTheirNamedEntries(_ name: String) {
        let ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults, homeDirectory: home)
        #expect(ignore.excludes(name: name, path: "/x/\(name)"))
    }

    @Test(arguments: [
        ("/Users/test/.Trash", true), ("/Users/test/Library/Caches", true),
        ("/Users/test/Library/Containers", true),
        ("/Users/test/Library/Application Support", true), ("/Library/Caches", true),
        ("/private/var/folders", true),
        ("/Users/test/Developer/Caches", false), ("/Users/test/.config", false),
        ("/Users/test/Library/Preferences", false), ("/Users/test/Developer/app/.claude/worktrees", true),
        ("/Users/test/conductor/workspaces", true)
    ])
    func shippedPathRulesLeaveOrdinaryLibraryAndProjectFoldersSearchable(_ path: String, _ expected: Bool) {
        let ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults, homeDirectory: home)
        #expect(ignore.excludes(name: URL(filePath: path).lastPathComponent, path: path) == expected)
    }

    @Test func editsAddUniquePatternsAfterDefaultsAndAllowRemovingADefault() {
        let edited = FileSearchIgnoreList.patterns(
            added: ["*.log", "node_modules", "*.log"], removedDefaults: [".git", "*.log"])
        #expect(!edited.contains(".git"))
        #expect(edited.filter { $0 == "node_modules" }.count == 1)
        #expect(edited.last == "*.log")
        #expect(
            FileSearchIgnoreList.patterns(added: [], removedDefaults: []) == FileSearchIgnoreList.defaults)
    }

    @Test(arguments: [
        (FileSearchIgnoreList.defaults, "notes.txt", "/Users/test/notes.txt", false, 0),
        (FileSearchIgnoreList.defaults, "CACHES", "/users/TEST/library/CACHES", true, 1),
        (FileSearchIgnoreList.defaults, "Caches", "/Users/test/Developer/Caches", false, 1),
        (["Archive", "/x/Caches"], "Archive", "/x/Archive", true, 0),
        (["*.tmp", "/x/Caches"], "scratch.tmp", "/x/scratch.tmp", true, 0),
        (["/Users/*/Library/Caches"], "Caches", "/Users/test/Library/Caches", true, 1),
        (["**/Cache/*.bin"], "blob.bin", "/x/Cache/nested/blob.bin", true, 1),
        (["**/.claude/worktrees"], "WorkTrees", "/x/repo/.claude/WorkTrees", true, 1),
        (["**/.claude/worktrees"], "worktrees", "/x/repo/worktrees", false, 1),
        (["**/.claude/worktrees"], "notes.txt", "/x/repo/notes.txt", false, 0),
        (["/x/[a/b]"], "a", "/x/a", true, 1), (["/x/cache\\?"], "cache?", "/x/cache?", true, 1),
        (["/x/\\*/cache"], "cache", "/x/*/cache", true, 1),
        (["/x/Reports/"], "Reports", "/x/Reports", false, 1)
    ])
    func theFastIgnorePathBuildsAFullPathOnlyWhenAPathRuleCouldMatch(
        _ patterns: [String], _ name: String, _ path: String, _ expected: Bool, _ expectedBuilds: Int
    ) {
        let ignore = FileSearchIgnoreList(patterns: patterns, homeDirectory: home)
        var builds = 0
        let excluded = name.withCString { bytes in
            ignore.excludes(name: bytes, length: name.utf8.count) {
                builds += 1
                return path
            }
        }
        #expect(excluded == expected)
        #expect(builds == expectedBuilds)
    }

    @Test func crawlRootsDeduplicateAndDropNestedScopes() {
        #expect(policy().roots == ["/Users/test", "/Volumes/Work"])
        #expect(
            FileSearchPolicy(
                scopes: ["/", "~"], ignorePatterns: [], includesHiddenFiles: false,
                homeDirectory: home
            ).roots == ["/"])
        #expect(
            FileSearchPolicy(
                scopes: [], ignorePatterns: [], includesHiddenFiles: false,
                homeDirectory: home
            ).roots.isEmpty)
    }

    @Test func policyFingerprintTracksTheSettingsUsedByTheCrawl() {
        let first = policy()
        let same = policy()
        let other = FileSearchPolicy(
            scopes: ["~"], ignorePatterns: ["*.txt"], includesHiddenFiles: false,
            homeDirectory: home)
        let hidden = policy(hidden: true)
        #expect(first.ignore.excludes(name: "run.log", path: "/Volumes/Work/run.log"))
        #expect(!first.ignore.excludes(name: "node_modules", path: "/Volumes/Work/node_modules"))
        #expect(first == same)
        #expect(first.fingerprint == same.fingerprint)
        #expect(first.fingerprint != other.fingerprint)
        #expect(first != hidden)
        #expect(first.fingerprint != hidden.fingerprint)
    }

    @Test(
        arguments: [
            ("/Users/test", 2), ("/Users/test/Documents/Work", 2), ("/Users/test/.config", 1),
            ("/Users/test/.config/Tool.app/Contents", 0),
            ("/Users/test/Library/CloudStorage/Dropbox/.cache", 1),
            ("/Users/test/Library/Caches", 0), ("/Users/test/Library/CloudStorage/Dropbox/Team", 2),
            ("/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Notes", 2),
            ("/Users/test/Developer/Tool.app/Contents", 0), ("/Applications", 1),
            ("/Applications/Xcode.app", 0),
            ("/Users/Shared", 1), ("/System/Library", 0), ("/private/var", 0)
        ] as [(String, Int8)])
    func locationPriorsFavorPersonalFilesOverBundlesAndCaches(_ path: String, _ expected: Int8) {
        #expect(policy().prior(of: path) == expected)
    }

    @Test(arguments: [
        (["/Users/test/Developer", "~/Developer", "/etc"], ["~/Developer", "/etc"]),
        (["~/a", "/", "~", "/Users/test/a"], ["~/a", "/", "~"])
    ])
    func storedScopesDeduplicateWithoutFoldingNestedScopes(_ scopes: [String], _ expected: [String]) {
        #expect(FileSearchScope.normalize(scopes, homeDirectory: home) == expected)
    }

    @Test func scopeExpansionAndContainmentRespectPathComponents() {
        #expect(FileSearchScope.expand("~", homeDirectory: home).path == "/Users/test")
        #expect(FileSearchScope.contains("/", "/Users"))
        #expect(!FileSearchScope.contains("/Users/a", "/Users/ab"))
    }

    @Test func displayedRowsKeepTheirFullFilenameAndAbbreviateTheirParent() {
        let report = row("Documents/Annual Report.pdf")
        let notes = row("Notes.txt")
        #expect(report.id == "/Users/test/Documents/Annual Report.pdf")
        #expect(report.name == "Annual Report.pdf")
        #expect(report.parentPath == "~/Documents")
        #expect(report.parentName == "Documents")
        #expect(notes.parentPath == "~")
        #expect(notes.parentName == "test")
    }

    @Test(arguments: ["/Applications", "/"])
    func aFolderAtTheRootHasNoParentNameToPrefix(_ path: String) {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        #expect(FileSearchResult(url: url, isDirectory: true, homeDirectory: home).parentName.isEmpty)
    }

    @Test(arguments: [
        ("Documents/Annual Report.pdf", false), ("Documents/Résumé #1? 100%.txt", false), ("Projects", true)
    ])
    func favoriteKeysPreserveTheCompletePathAndDirectoryHint(_ path: String, _ directory: Bool) throws {
        let original = row(path, directory: directory)
        let restored = try #require(FileSearchResult(favoriteKey: original.favoriteKey, homeDirectory: home))
        #expect(restored.id == original.id)
        #expect(restored.isDirectory == original.isDirectory)
        #expect(restored.favoriteKey == original.favoriteKey)
        #expect(restored.parentPath == original.parentPath)
    }

    @Test(arguments: [
        "com.apple.finder", "/Users/test/Documents/Annual Report.pdf", "https://example.com/file",
        "file:///tmp/file?query=1"
    ])
    func otherIdentifiersCannotRestoreAFileFavorite(_ key: String) {
        #expect(FileSearchResult(favoriteKey: key, homeDirectory: home) == nil)
    }

    @Test(
        arguments: [
            ("swift", .quickLook), ("pdf", .pdf), ("mov", .media), ("jsx", nil), ("ts", nil)
        ] as [(String, FileSearchPreviewKind?)])
    func unambiguousExtensionsDeterminePreviewKind(
        _ pathExtension: String, _ expected: FileSearchPreviewKind?
    ) {
        #expect(FileSearchPreviewKind(pathExtension: pathExtension) == expected)
    }

    @Test(
        arguments: [
            ("ts", Data("export const x = () => <div>é</div>\n".utf8), true, .text),
            ("ts", Data([0x47, 0x40, 0x00, 0x10]), false, .media),
            ("jsx", Data([0xFF, 0x00]), true, .quickLook)
        ] as [(String, Data, Bool, FileSearchPreviewKind)])
    func previewInspectionDistinguishesTextFromMediaAndOtherBinaryFiles(
        _ pathExtension: String, _ head: Data, _ whole: Bool, _ expected: FileSearchPreviewKind
    ) {
        #expect(
            FileSearchPreviewKind(pathExtension: pathExtension, head: head, isWholeFile: whole) == expected)
    }

    @Test(arguments: [
        (Data("café".utf8).dropLast(), false, true), (Data("café".utf8).dropLast(), true, false),
        (Data("abc".utf8) + [0xFF], false, false)
    ])
    func onlyPartialReadsMayEndInATruncatedUTF8Character(_ bytes: Data, _ whole: Bool, _ expected: Bool) {
        #expect(FileSearchPreviewKind.isText(bytes, isWholeFile: whole) == expected)
    }

    private func score(_ query: String, _ name: String, holding: UInt8? = nil, prior: Int8 = 2) throws -> Int?
    {
        let prepared = try #require(FileSearchQuery.prepare(query))
        var name = name
        return name.withUTF8 { bytes in
            let mask = FileSearchQuery.nameMask(bytes)
            if let holding {
                return FileSearchQuery.score(
                    prepared, name: bytes, mask: mask, holding: holding, prior: prior)
            }
            return FileSearchQuery.score(prepared, name: bytes, mask: mask, prior: prior)
        }
    }

    private func policy(hidden: Bool = false) -> FileSearchPolicy {
        FileSearchPolicy(
            scopes: ["~/Developer", "~", "/Volumes/Work", "~/Developer"],
            ignorePatterns: ["*.log"], includesHiddenFiles: hidden, homeDirectory: home)
    }

    private func row(_ path: String, directory: Bool = false) -> FileSearchResult {
        FileSearchResult(url: home.appending(path: path), isDirectory: directory, homeDirectory: home)
    }
}
