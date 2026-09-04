import Foundation

@main
struct ScopesTest {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("tinycast-scopes-\(UUID().uuidString)")

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func makeDir(_ url: URL) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Two direct apps, a non-app file, a hidden app, one nested app, one two-deep nested app.
        let apps = root.appendingPathComponent("Apps")
        makeDir(apps.appendingPathComponent("Alpha.app"))
        makeDir(apps.appendingPathComponent("Beta.app"))
        makeDir(apps.appendingPathComponent("Notes.txt"))
        makeDir(apps.appendingPathComponent(".Hidden.app"))
        let vendor = apps.appendingPathComponent("Vendor")
        makeDir(vendor.appendingPathComponent("Nested.app"))
        let deep = vendor.appendingPathComponent("Deeper")
        makeDir(deep.appendingPathComponent("TooDeep.app"))

        let managedApps = root.appendingPathComponent("Managed Apps")
        makeDir(managedApps.appendingPathComponent("Managed.app"))
        let managedAppsLink = apps.appendingPathComponent("Home Manager Apps")
        try fm.createSymbolicLink(at: managedAppsLink, withDestinationURL: managedApps)
        let managedAppLink = root.appendingPathComponent("Managed Link.app")
        try fm.createSymbolicLink(
            at: managedAppLink,
            withDestinationURL: managedApps.appendingPathComponent("Managed.app"))
        let brokenAppLink = apps.appendingPathComponent("Broken.app")
        try fm.createSymbolicLink(
            at: brokenAppLink,
            withDestinationURL: root.appendingPathComponent("Missing.app"))

        let foundURLs = SearchScopes.appBundles(in: [apps.path])
        let found = foundURLs.map(\.lastPathComponent)
        check(
            "direct, nested, and symlinked .app children are indexed",
            Set(found) == ["Alpha.app", "Beta.app", "Managed.app", "Nested.app"])
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        check("bundles nested two levels deep are not indexed", !found.contains("TooDeep.app"))
        let logicalManagedApp = managedAppsLink.appendingPathComponent("Managed.app")
        let physicalManagedApp = managedApps.appendingPathComponent("Managed.app")
        check(
            "apps under a symlink keep their logical paths",
            foundURLs.contains(logicalManagedApp) && !foundURLs.contains(physicalManagedApp))
        check("broken .app symlinks are skipped", !foundURLs.contains(brokenAppLink))
        check(
            "a symlinked directory works as its own scope",
            SearchScopes.appBundles(in: [managedAppsLink.path]) == [logicalManagedApp])
        check(
            "an .app symlink works as its own scope",
            SearchScopes.appBundles(in: [managedAppLink.path]) == [managedAppLink])
        check(
            "a deeply nested folder works as its own scope",
            SearchScopes.appBundles(in: [deep.path]).map(\.lastPathComponent) == ["TooDeep.app"])

        // A scope may be a single bundle: that is how Finder ships as a default.
        check(
            "an .app scope is indexed directly",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Alpha.app").path])
                .map(\.lastPathComponent) == ["Alpha.app"])
        check(
            "a missing .app scope yields nothing",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Gone.app").path]).isEmpty)
        check(
            "a missing directory scope is skipped without failing the rest",
            SearchScopes.appBundles(in: [root.appendingPathComponent("Nope").path, deep.path])
                .map(\.lastPathComponent) == ["TooDeep.app"])

        check(
            "scopes are scanned in order",
            SearchScopes.appBundles(in: [deep.path, apps.path]).map(\.lastPathComponent).first
                == "TooDeep.app")

        let home = fm.homeDirectoryForCurrentUser.path
        check(
            "expand resolves a tilde",
            SearchScopes.expand("~/Applications") == home + "/Applications")
        check(
            "abbreviate restores the tilde",
            SearchScopes.abbreviate(home + "/Applications") == "~/Applications")
        check(
            "tilde survives a round trip",
            SearchScopes.abbreviate(SearchScopes.expand("~/Applications")) == "~/Applications")
        check(
            "expand leaves an absolute path alone",
            SearchScopes.expand("/Applications") == "/Applications")
        check(
            "a trailing slash is trimmed",
            SearchScopes.abbreviate("/Applications/") == "/Applications")
        check("root survives trimming", SearchScopes.abbreviate("/") == "/")

        check(
            "normalize dedups after abbreviating",
            SearchScopes.normalize([
                "/Applications", "/Applications/", home + "/Applications", "~/Applications"
            ])
                == ["/Applications", "~/Applications"])
        check("normalize preserves order", SearchScopes.normalize(["/B", "/A"]) == ["/B", "/A"])
        check("normalize drops blanks", SearchScopes.normalize(["  ", "/A"]) == ["/A"])
        check(
            "defaults are already normalized",
            SearchScopes.normalize(SearchScopes.defaults) == SearchScopes.defaults)

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
