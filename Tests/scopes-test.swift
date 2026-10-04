import Foundation

@main
struct ScopesTest {
    static func main() {
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

        func makeApp(_ url: URL, version: String) {
            let contents = url.appendingPathComponent("Contents")
            makeDir(contents)
            let plist = ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": version]
            let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: contents.appendingPathComponent("Info.plist"))
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

        let found = SearchScopes.appBundles(in: [apps.path]).map(\.lastPathComponent)
        check(
            "direct and one-level-nested .app children are indexed",
            Set(found) == ["Alpha.app", "Beta.app", "Nested.app"])
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        check("bundles nested two levels deep are not indexed", !found.contains("TooDeep.app"))
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

        // Xcode ships Instruments and Simulator inside its own bundle.
        let tools = root.appendingPathComponent("Tools")
        let xcode = tools.appendingPathComponent("Xcode.app")
        makeDir(xcode.appendingPathComponent("Contents/Applications/Instruments.app"))
        makeDir(xcode.appendingPathComponent("Contents/Developer/Applications/Simulator.app"))
        makeDir(xcode.appendingPathComponent("Contents/Frameworks/Helper.app"))
        let embedded = Set(SearchScopes.appBundles(in: [tools.path]).map(\.lastPathComponent))
        check(
            "apps embedded in a bundle's application folders are indexed",
            embedded == ["Xcode.app", "Instruments.app", "Simulator.app"])
        check(
            "an .app scope also yields its embedded apps",
            Set(SearchScopes.appBundles(in: [xcode.path]).map(\.lastPathComponent)) == embedded)

        func listing(_ folder: String, versions: [String: String]) -> [String] {
            let url = root.appendingPathComponent(folder)
            for (name, version) in versions {
                makeApp(url.appendingPathComponent(name), version: version)
            }
            return SearchScopes.appBundles(in: [url.path]).map(\.lastPathComponent)
        }

        // Mirrored names, so no fixed filesystem order can pass both checks by luck.
        check(
            "a folder lists its newest version first, compared as numbers",
            listing("Rising", versions: ["A.app": "9.4", "B.app": "26.6", "C.app": "27.0"])
                == ["C.app", "B.app", "A.app"])
        check(
            "the newest version leads whatever its name",
            listing("Falling", versions: ["A.app": "27.0", "B.app": "26.6", "C.app": "9.4"])
                == ["A.app", "B.app", "C.app"])

        check(
            "equal versions fall back to Finder's name order",
            listing("Ties", versions: ["Xcode-beta.app": "26.0", "Xcode.app": "26.0"])
                == ["Xcode.app", "Xcode-beta.app"])

        let unreadable = root.appendingPathComponent("Unreadable")
        makeDir(unreadable.appendingPathComponent("Aardvark.app"))
        makeApp(unreadable.appendingPathComponent("Zebra.app"), version: "1.0")
        check(
            "a bundle with no version sorts after one that has a version",
            SearchScopes.appBundles(in: [unreadable.path]).map(\.lastPathComponent)
                == ["Zebra.app", "Aardvark.app"])

        check(
            "an earlier scope still wins over a newer version in a later one",
            SearchScopes.appBundles(in: [
                root.appendingPathComponent("Rising/A.app").path,
                root.appendingPathComponent("Rising").path
            ]).map(\.lastPathComponent).first == "A.app")

        check(
            "scopes are scanned in order",
            SearchScopes.appBundles(in: [deep.path, apps.path]).map(\.lastPathComponent).first
                == "TooDeep.app")
        check(
            "overlapping scopes yield each app once, at its first scope's position",
            SearchScopes.appBundles(in: [xcode.path, tools.path, deep.path, vendor.path])
                .map(\.lastPathComponent)
                == ["Xcode.app", "Instruments.app", "Simulator.app", "TooDeep.app", "Nested.app"])

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
