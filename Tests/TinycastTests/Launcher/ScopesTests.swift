import Foundation
import Testing

@testable import Tinycast

struct ScopesTests {
    @Test func scanningKeepsVisibleAppsAtTheAllowedDepth() throws {
        let fixture = try AppFolders()
        let found = SearchScopes.appBundles(in: [fixture.apps.path]).map(\.lastPathComponent)
        #expect(Set(found) == ["Alpha.app", "Beta.app", "Nested.app"])
        #expect(!found.contains("Notes.txt"))
        #expect(!found.contains(".Hidden.app"))
        #expect(!found.contains("TooDeep.app"))
        #expect(SearchScopes.appBundles(in: [fixture.deep.path]).map(\.lastPathComponent) == ["TooDeep.app"])
    }

    @Test func linkedScopesKeepLogicalPathsAndSeparateAliases() throws {
        let fixture = try AppFolders()
        let link = fixture.root.appending(path: "LinkedApps")
        let chain = fixture.root.appending(path: "LinkedAgain")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.apps)
        try FileManager.default.createSymbolicLink(at: chain, withDestinationURL: link)

        let aliases = ["LinkedApps/Alpha.app", "LinkedApps/Beta.app", "LinkedApps/Vendor/Nested.app"]
        #expect(fixture.paths(in: [link.path]) == aliases)
        #expect(
            SearchScopes.appBundles(in: [fixture.apps.path]).allSatisfy {
                $0.path.hasPrefix(fixture.apps.path + "/")
            })
        #expect(
            fixture.paths(in: [chain.path]) == [
                "LinkedAgain/Alpha.app", "LinkedAgain/Beta.app", "LinkedAgain/Vendor/Nested.app"
            ])
        #expect(
            fixture.paths(in: [link.path, fixture.apps.path]) == aliases
                + fixture.paths(in: [fixture.apps.path]))

        let replacement = fixture.root.appending(path: "Replacement")
        try Self.directory(replacement.appending(path: "Updated.app"))
        try FileManager.default.removeItem(at: chain)
        try FileManager.default.createSymbolicLink(at: chain, withDestinationURL: replacement)
        #expect(fixture.paths(in: [chain.path]) == ["LinkedAgain/Updated.app"])
    }

    @Test func appLinksStayLeavesAndDirectoryAliasesKeepDepthAndVisibilityRules() throws {
        let fixture = try AppFolders()
        let linked = fixture.root.appending(path: "Links")
        try Self.directory(linked)
        let app = linked.appending(path: "Renamed.app")
        try FileManager.default.createSymbolicLink(
            at: app, withDestinationURL: fixture.apps.appending(path: "Alpha.app"))
        #expect(fixture.paths(in: [linked.path]) == ["Links/Renamed.app"])
        #expect(fixture.paths(in: [app.path]) == ["Links/Renamed.app"])

        try FileManager.default.createSymbolicLink(
            at: linked.appending(path: "Vendor"), withDestinationURL: fixture.vendor)
        try FileManager.default.createSymbolicLink(
            at: linked.appending(path: ".HiddenVendor"), withDestinationURL: fixture.vendor)
        try FileManager.default.createSymbolicLink(
            at: linked.appending(path: "Missing"), withDestinationURL: fixture.root.appending(path: "Nope"))
        #expect(fixture.paths(in: [linked.path]) == ["Links/Renamed.app", "Links/Vendor/Nested.app"])

        try FileManager.default.createSymbolicLink(
            at: linked.appending(path: "Back"), withDestinationURL: linked)
        let cycle = linked.appending(path: "Cycle")
        try FileManager.default.createSymbolicLink(at: cycle, withDestinationURL: cycle)
        #expect(SearchScopes.appBundles(in: [cycle.path]).isEmpty)
        #expect(SearchScopes.appBundles(in: [linked.path]).count == 2)

        try FileManager.default.createSymbolicLink(
            at: linked.appending(path: "OtherVendor"), withDestinationURL: fixture.vendor)
        #expect(
            fixture.paths(in: [linked.path]) == [
                "Links/OtherVendor/Nested.app", "Links/Renamed.app", "Links/Vendor/Nested.app"
            ])
    }

    @Test func oneBundleCanBeAScopeAndMissingScopesAreSkipped() throws {
        let fixture = try AppFolders()
        let alpha = fixture.apps.appending(path: "Alpha.app")
        #expect(SearchScopes.appBundles(in: [alpha.path]).map(\.lastPathComponent) == ["Alpha.app"])
        #expect(SearchScopes.appBundles(in: [fixture.apps.appending(path: "Gone.app").path]).isEmpty)
        let missing = fixture.root.appending(path: "Nope")
        #expect(
            SearchScopes.appBundles(in: [missing.path, fixture.deep.path]).map(\.lastPathComponent) == [
                "TooDeep.app"
            ])
    }

    @Test func applicationSubfoldersOfABundleSupplyEmbeddedApps() throws {
        let fixture = try AppFolders()
        let xcode = try xcodeFixture(in: fixture.root)
        let tools = xcode.deletingLastPathComponent()
        let expected: Set = ["Xcode.app", "Instruments.app", "Simulator.app"]
        #expect(Set(SearchScopes.appBundles(in: [tools.path]).map(\.lastPathComponent)) == expected)
        #expect(Set(SearchScopes.appBundles(in: [xcode.path]).map(\.lastPathComponent)) == expected)

        let host = fixture.root.appending(path: "LinkedHost.app")
        try Self.directory(host.appending(path: "Contents"))
        try FileManager.default.createSymbolicLink(
            at: host.appending(path: "Contents/Applications"), withDestinationURL: tools)
        #expect(fixture.paths(in: [host.path]).contains("LinkedHost.app/Contents/Applications/Xcode.app"))
    }

    @Test func embeddedAppCyclesStopAtAnAncestor() throws {
        let scratch = try ScratchDirectory("embedded-app-cycle")
        let host = scratch.url.appending(path: "LoopHost.app")
        let folder = host.appending(path: "Contents/Applications")
        try Self.directory(folder)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "Back.app"), withDestinationURL: host)
        #expect(
            SearchScopes.appBundles(in: [host.path]).map(\.lastPathComponent) == ["LoopHost.app", "Back.app"])
    }

    @Test(arguments: [
        ("Rising", ["A.app": "9.4", "B.app": "26.6", "C.app": "27.0"], ["C.app", "B.app", "A.app"]),
        ("Falling", ["A.app": "27.0", "B.app": "26.6", "C.app": "9.4"], ["A.app", "B.app", "C.app"]),
        ("Ties", ["Xcode-beta.app": "26.0", "Xcode.app": "26.0"], ["Xcode.app", "Xcode-beta.app"])
    ])
    func appsSortByNumericVersionThenByFinderName(
        _ folder: String, _ versions: [String: String], _ expected: [String]
    ) throws {
        let scratch = try ScratchDirectory("app-versions")
        let scope = try versionedApps(versions, in: scratch.url.appending(path: folder))
        #expect(SearchScopes.appBundles(in: [scope.path]).map(\.lastPathComponent) == expected)
    }

    @Test func bundleVersionIsReadThroughTheScopeLink() throws {
        let fixture = try AppFolders()
        let rising = try versionedApps(
            ["A.app": "9.4", "B.app": "26.6", "C.app": "27.0"], in: fixture.root.appending(path: "Rising"))
        let link = fixture.root.appending(path: "Versions")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: rising)
        #expect(fixture.paths(in: [link.path]) == ["Versions/C.app", "Versions/B.app", "Versions/A.app"])

        let a = rising.appending(path: "A.app")
        let first = try #require(SearchScopes.appBundles(in: [a.path, rising.path]).first)
        #expect(first.lastPathComponent == "A.app")
    }

    @Test func bundlesWithAVersionLeadThoseWithoutOne() throws {
        let scratch = try ScratchDirectory("missing-app-version")
        let scope = scratch.url.appending(path: "Unreadable")
        try Self.directory(scope.appending(path: "Aardvark.app"))
        _ = try versionedApps(["Zebra.app": "1.0"], in: scope)
        #expect(
            SearchScopes.appBundles(in: [scope.path]).map(\.lastPathComponent) == [
                "Zebra.app", "Aardvark.app"
            ])
    }

    @Test func overlappingScopesKeepEachBundleInItsFirstScope() throws {
        let fixture = try AppFolders()
        let xcode = try xcodeFixture(in: fixture.root)
        let first = try #require(SearchScopes.appBundles(in: [fixture.deep.path, fixture.apps.path]).first)
        #expect(first.lastPathComponent == "TooDeep.app")

        let scopes = [xcode, xcode.deletingLastPathComponent(), fixture.deep, fixture.vendor]
        #expect(
            SearchScopes.appBundles(in: scopes.map(\.path)).map(\.lastPathComponent) == [
                "Xcode.app", "Instruments.app", "Simulator.app", "TooDeep.app", "Nested.app"
            ])
    }

    @Test func choosingAnApplicationFolderUnderHomeRoundTripsTheTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(SearchScopes.expand("~/Applications") == home + "/Applications")
        #expect(SearchScopes.abbreviate(home + "/Applications") == "~/Applications")
        #expect(SearchScopes.abbreviate(SearchScopes.expand("~/Applications")) == "~/Applications")
        #expect(SearchScopes.expand("/Applications") == "/Applications")
    }

    @Test(arguments: [("/Applications/", "/Applications"), ("/", "/")])
    func storedPathsRemoveTrailingSlashesExceptAtTheRoot(_ path: String, _ expected: String) {
        #expect(SearchScopes.abbreviate(path) == expected)
    }

    @Test func normalizingDeduplicatesAfterAbbreviating() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(
            SearchScopes.normalize([
                "/Applications", "/Applications/", home + "/Applications", "~/Applications"
            ]) == ["/Applications", "~/Applications"])
    }

    @Test(arguments: [(["/B", "/A"], ["/B", "/A"]), (["  ", "/A"], ["/A"])])
    func normalizingKeepsOrderAndDropsBlanks(_ paths: [String], _ expected: [String]) {
        #expect(SearchScopes.normalize(paths) == expected)
    }

    @Test func defaultsAreAlreadyNormalized() {
        #expect(SearchScopes.normalize(SearchScopes.defaults) == SearchScopes.defaults)
    }

    private func xcodeFixture(in root: URL) throws -> URL {
        let xcode = root.appending(path: "Tools/Xcode.app")
        try Self.directory(xcode.appending(path: "Contents/Applications/Instruments.app"))
        try Self.directory(xcode.appending(path: "Contents/Developer/Applications/Simulator.app"))
        try Self.directory(xcode.appending(path: "Contents/Frameworks/Helper.app"))
        return xcode
    }

    private func versionedApps(_ versions: [String: String], in scope: URL) throws -> URL {
        for (name, version) in versions {
            let contents = scope.appending(path: name).appending(path: "Contents")
            try Self.directory(contents)
            let plist = ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": version]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appending(path: "Info.plist"))
        }
        return scope
    }

    private static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private struct AppFolders {
        let scratch: ScratchDirectory
        var root: URL { scratch.url }
        var apps: URL { root.appending(path: "Apps") }
        var vendor: URL { apps.appending(path: "Vendor") }
        var deep: URL { vendor.appending(path: "Deeper") }

        init() throws {
            scratch = try ScratchDirectory("app-scopes")
            for path in [
                "Alpha.app", "Beta.app", "Notes.txt", ".Hidden.app", "Vendor/Nested.app",
                "Vendor/Deeper/TooDeep.app"
            ] {
                try ScopesTests.directory(apps.appending(path: path))
            }
        }

        func paths(in scopes: [String]) -> [String] {
            SearchScopes.appBundles(in: scopes).map { bundle in
                bundle.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            }
        }
    }
}
