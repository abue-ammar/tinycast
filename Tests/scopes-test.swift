import Foundation

@main
struct ScopesTest {
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("tinycast-scopes-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

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

        // A scope directory with two apps, a non-app sibling, a hidden app, and a nested app.
        let apps = root.appendingPathComponent("Apps")
        makeDir(apps.appendingPathComponent("Alpha.app"))
        makeDir(apps.appendingPathComponent("Beta.app"))
        makeDir(apps.appendingPathComponent("Notes.txt"))
        makeDir(apps.appendingPathComponent(".Hidden.app"))
        let nested = apps.appendingPathComponent("Sub")
        makeDir(nested.appendingPathComponent("Deep.app"))

        let found = SearchScopes.appBundles(in: [apps.path]).map(\.lastPathComponent)
        check("direct .app children are indexed", Set(found) == ["Alpha.app", "Beta.app"])
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        // Flat by contract: a nested folder is indexed by adding it as its own scope.
        check("nested bundles are not indexed", !found.contains("Deep.app"))
        check(
            "a nested folder works as its own scope",
            SearchScopes.appBundles(in: [nested.path]).map(\.lastPathComponent) == ["Deep.app"])

        // A scope may be a single bundle rather than a directory — that's how Finder ships as a default.
        check(
            "an .app scope is indexed directly",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Alpha.app").path])
                .map(\.lastPathComponent) == ["Alpha.app"])
        check(
            "a missing .app scope yields nothing",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Gone.app").path]).isEmpty)
        check(
            "a missing directory scope is skipped without failing the rest",
            SearchScopes.appBundles(in: [root.appendingPathComponent("Nope").path, nested.path])
                .map(\.lastPathComponent) == ["Deep.app"])

        check(
            "scopes are scanned in order",
            SearchScopes.appBundles(in: [nested.path, apps.path]).map(\.lastPathComponent).first
                == "Deep.app")

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

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
