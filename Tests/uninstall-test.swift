// Standalone test for uninstall attribution, search roots, rules, protection and planning.
import Foundation

@main
@MainActor
struct UninstallTests {
    static var failures = 0
    static var passes = 0

    static let home = "/Users/tester"
    static let ownBundleID = "com.tinycast.app"
    static let ownBundleURL = URL(fileURLWithPath: "/Applications/Tinycast.app")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    // MARK: - Fixtures

    static func identity(
        bundleID: String?, name: String = "Test App", bundleName: String? = nil,
        otherAppNames: [String] = [], otherBundleIDs: [String] = [],
        path: String = "/Applications/Test App.app"
    ) -> UninstallIdentity {
        let target = UninstallTarget(
            bundleURL: URL(fileURLWithPath: path), bundleID: bundleID, displayName: name,
            bundleName: bundleName)
        guard
            let identity = UninstallIdentity.make(
                target: target, otherAppNames: otherAppNames, otherBundleIDs: otherBundleIDs,
                ownBundleID: ownBundleID, ownBundleURL: ownBundleURL)
        else {
            fatalError("fixture identity was refused: \(name)")
        }
        return identity
    }

    static func root(_ relativePath: String) -> UninstallSearchRoot {
        guard
            let root = UninstallSearchRoot.all.first(where: {
                $0.base == .userLibrary && $0.relativePath == relativePath
            })
        else { fatalError("no such root: \(relativePath)") }
        return root
    }

    static func evidence(
        _ name: String, _ relativePath: String, _ identity: UninstallIdentity
    )
        -> UninstallEvidence?
    {
        UninstallRules.evidence(for: name, in: root(relativePath), identity: identity)
    }

    // MARK: - Bundle ID matching

    static func testBundleIDMatching() {
        let books = identity(bundleID: "com.apple.iBooksX", name: "Books")
        expect(
            UninstallRules.matchesBundleID("com.apple.iBooksX", identity: books),
            "a bundle ID matches itself")
        expect(
            UninstallRules.matchesBundleID("com.apple.iBooksX.CacheDelete", identity: books),
            "a dot-namespaced child matches — the case prefix matching exists for")
        expect(
            !UninstallRules.matchesBundleID("com.apple.iBooks", identity: books),
            "a shorter sibling ID does not match")
        expect(
            !UninstallRules.matchesBundleID("com.apple.iBooksXtra", identity: books),
            "a longer ID without the dot boundary does not match")
        expect(
            UninstallRules.matchesBundleID("COM.Apple.IBOOKSX", identity: books),
            "matching is case-folded")

        let safari = identity(bundleID: "com.apple.Safari", name: "Safari")
        expect(
            !UninstallRules.matchesBundleID("com.apple.SafariTechnologyPreview", identity: safari),
            "Safari Technology Preview is never claimed by Safari — the trailing-dot rule")
        expect(
            !UninstallRules.matchesBundleID("com.apple.Safari2", identity: safari),
            "a digit-suffixed ID does not match")

        // Sibling release channels share a namespace but are separate products.
        let channels = ["com.example.app", "com.example.app.beta", "com.example.app.dev"]
        let stable = identity(
            bundleID: "com.example.app", name: "Example", otherBundleIDs: channels)
        expect(
            UninstallRules.matchesBundleID("com.example.app", identity: stable),
            "a channel still matches its own artifacts")
        expect(
            !UninstallRules.matchesBundleID("com.example.app.dev", identity: stable),
            "an installed sibling channel owns its own data — stable never claims Dev's")
        expect(
            !UninstallRules.matchesBundleID("com.example.app.beta.plist", identity: stable),
            "the sibling rule survives extension stripping")
        expect(
            UninstallRules.matchesBundleID("com.example.app.helper", identity: stable),
            "a namespace child that is not an installed app is still ours")
        let devChannel = identity(
            bundleID: "com.example.app.dev", name: "Example Dev", otherBundleIDs: channels)
        expect(
            UninstallRules.matchesBundleID("com.example.app.dev", identity: devChannel),
            "and the sibling itself still matches its own ID")
        expect(
            !UninstallRules.matchesBundleID("com.example.app", identity: devChannel),
            "a longer-ID sibling never claims the shorter parent's artifacts either")

        let vendor = identity(bundleID: "com.adobe", name: "Vendor App")
        expect(
            UninstallRules.matchesBundleID("com.adobe", identity: vendor),
            "a two-component ID still matches itself exactly")
        expect(
            !UninstallRules.matchesBundleID("com.adobe.Photoshop", identity: vendor),
            "a two-component ID names a vendor, so it never prefix-matches its products")
    }

    // MARK: - Extension stripping

    static func testExtensionStripping() {
        let app = identity(bundleID: "com.foo.Bar")
        expect(evidence("com.foo.Bar.plist", "Preferences", app) == .bundleID, "a .plist strips")
        expect(
            evidence("com.foo.Bar.plist.lockfile", "Preferences", app) == .bundleID,
            "stripping repeats for a .plist.lockfile")
        expect(
            evidence("com.foo.Bar.savedState", "Saved Application State", app) == .bundleID,
            "a .savedState strips")
        expect(
            evidence("com.foo.Bar.binarycookies", "Cookies", app) == .bundleID,
            "a .binarycookies strips")
        expect(
            evidence("com.foo.Bar.8A1F2C3D-1111-2222-3333-444455556666.plist", "Preferences/ByHost", app)
                == .bundleID,
            "a ByHost UUID name strips then matches as a namespace child")
        expect(
            evidence("com.foo.BarHelper.plist", "Preferences", app) == nil,
            "a helper whose ID merely starts with the target's does not match")
        expect(
            UninstallRules.matchableForms("com.foo.Bar.app") == ["com.foo.Bar.app"],
            ".app is not a stripped extension")
    }

    // MARK: - Group containers

    static func testGroupContainers() {
        let app = identity(bundleID: "com.foo.Bar")
        expect(
            evidence("group.com.foo.Bar", "Group Containers", app) == .groupContainer,
            "a group. prefix is stripped")
        expect(
            evidence("ABCDE12345.com.foo.Bar", "Group Containers", app) == .groupContainer,
            "a Team ID prefix is stripped")
        expect(
            evidence("ABCDE12345.group.com.foo.Bar", "Group Containers", app) == .groupContainer,
            "both prefixes are stripped")
        expect(
            evidence("group.com.foo.BarExtra", "Group Containers", app) == nil,
            "a near-miss after stripping is still a miss")
        expect(
            evidence("notateamid.com.foo.Bar", "Group Containers", app) == nil,
            "an arbitrary prefix is not a Team ID")
        expect(
            evidence("group.com.foo.Bar", "Preferences", app) == nil,
            "group matching only applies in roots that enable it")
        expect(UninstallRules.isTeamID("ABCDE12345"), "a 10-char uppercase alphanumeric is a Team ID")
        expect(!UninstallRules.isTeamID("abcde12345"), "lowercase is not a Team ID")
        expect(!UninstallRules.isTeamID("ABCDE1234"), "9 characters is not a Team ID")
    }

    // MARK: - Display names

    static func testDisplayNames() {
        let cleaner = identity(
            bundleID: "net.freemacsoft.AppCleaner", name: "AppCleaner")
        expect(
            evidence("AppCleaner", "Application Support", cleaner) == .displayName,
            "a name-matched support folder is found, and flagged as name evidence")
        expect(
            evidence("AppCleaner", "Preferences", cleaner) == nil,
            "name matching never applies in a bundle-ID-only root")

        let books = identity(bundleID: "com.apple.iBooksX", name: "Books")
        expect(
            evidence("Books Reader", "Application Support", books) == nil,
            "an exact-only rule stops Books claiming Books Reader")
        let reader = identity(bundleID: "com.other.BooksReader", name: "Books Reader")
        expect(
            evidence("Books", "Application Support", reader) == nil,
            "and stops Books Reader claiming Books — exactness cuts both ways")

        let mail = identity(
            bundleID: "com.third.Mailer", name: "Mail", otherAppNames: ["Mail", "Notes"])
        expect(
            evidence("Mail", "Application Support", mail) == nil,
            "a name shared with another installed app is dropped entirely")
        expect(
            evidence("Mail", "Application Support", identity(bundleID: "com.third.Mailer", name: "Mail"))
                == .displayName,
            "the same name is usable when no other installed app claims it")

        let short = identity(bundleID: "com.foo.Go", name: "Go")
        expect(
            evidence("Go", "Application Support", short) == nil,
            "a two-character name is under the minimum and never matches")
        let zed = identity(bundleID: "dev.zed.Zed", name: "Zed")
        expect(
            evidence("Zed", "Application Support", zed) == .displayName,
            "three characters is enough — Zed names its own support folder")
        expect(
            evidence("Zed", "Logs", zed) == .displayName, "and its logs folder")
        expect(
            evidence("dev.zed.Zed-Preview.plist", "Preferences", zed) == .bundleID,
            "a hyphenated release variant belongs to the product it varies")
        expect(
            evidence(
                "dev.zed.Zed-Preview.plist", "Preferences",
                identity(
                    bundleID: "dev.zed.Zed", name: "Zed",
                    otherBundleIDs: ["dev.zed.Zed", "dev.zed.Zed-Preview"])) == nil,
            "unless that variant is itself installed, in which case it owns its own preferences")

        let reserved = identity(bundleID: "com.foo.Prefs", name: "Preferences")
        expect(
            evidence("Preferences", "Application Support", reserved) == nil,
            "a macOS-owned Library folder name is never claimable")

        expect(
            UninstallIdentity.safeNames(
                displayName: "AppCleaner", bundleName: "AppCleaner", otherAppNames: [])
                == ["appcleaner"],
            "a bundle name identical to the display name is deduped")
    }

    static func testPlugInsAndSymlinks() {
        let app = identity(bundleID: "com.foo.Bar", name: "Barista")
        expect(
            evidence("com.foo.Bar.qlgenerator", "QuickLook", app) == .bundleID,
            "a QuickLook generator is stripped to its bundle ID")
        expect(
            evidence("Barista.saver", "Screen Savers", app) == .displayName,
            "a screen saver is stripped to its product name")
        expect(
            evidence("Barista.prefPane", "PreferencePanes", app) == .displayName,
            "so is a preference pane")
        expect(
            evidence("Unrelated.qlgenerator", "QuickLook", app) == nil,
            "another product's plug-in is left alone")
        expect(
            !UninstallRules.matchableForms("Barista.app").contains("Barista"),
            ".app is never stripped — an app bundle is not a plug-in wrapper")

        let bundle = "/Applications/Zed.app"
        expect(
            UninstallRules.isBundleSymlink(
                target: "/Applications/Zed.app/Contents/MacOS/cli", bundlePath: bundle),
            "a launcher resolving inside the bundle belongs to the app")
        expect(
            UninstallRules.isBundleSymlink(target: bundle, bundlePath: bundle),
            "a link straight at the bundle counts too")
        expect(
            !UninstallRules.isBundleSymlink(
                target: "/Applications/Zed2.app/Contents/MacOS/cli", bundlePath: bundle),
            "a sibling bundle sharing a path prefix does not")
        expect(
            !UninstallRules.isBundleSymlink(target: "/opt/homebrew/bin/zed", bundlePath: bundle),
            "and neither does an unrelated target — attribution is by link target, never by name")
        expect(
            UninstallSearchRoot.binDirectories.allSatisfy {
                $0.hasPrefix("/") || $0.hasPrefix("~/")
            },
            "every bin directory is absolute or home-relative")
    }

    /// The home directory holds the user's own work, so nothing there is ever a candidate. Asserting
    /// the absence keeps a future root addition from quietly reopening it.
    static func testHomeIsOutOfScope() {
        expect(
            !UninstallSearchRoot.all.contains { $0.path(home: home) == home },
            "the home directory itself is never a search root")
        expect(
            UninstallSearchRoot.all.allSatisfy {
                let path = $0.path(home: home)
                return path.hasPrefix(home + "/Library/") || path.hasPrefix("/Library/")
            },
            "every root lives under a Library directory — never ~/Documents, ~/Dev or ~/Code")
        // VS Code's CFBundleName is literally "Code", so it *would* match `~/Code` on name alone —
        // the root table is the only thing standing between that and the user's source tree.
        let code = identity(
            bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", bundleName: "Code")
        expect(
            UninstallRules.matchesDisplayName("Code", identity: code),
            "the name rule alone would claim a folder called Code")
        expect(
            !UninstallSearchRoot.all.contains { $0.path(home: home) + "/Code" == home + "/Code" },
            "so it matters that no root ever puts ~/Code in reach")
    }

    // MARK: - Identity refusal

    static func testIdentityRefusal() {
        let byID = UninstallTarget(
            bundleURL: URL(fileURLWithPath: "/Applications/Somewhere Else.app"),
            bundleID: "com.tinycast.app", displayName: "Tinycast", bundleName: nil)
        expect(
            UninstallIdentity.make(
                target: byID, otherAppNames: [], ownBundleID: ownBundleID,
                ownBundleURL: ownBundleURL) == nil,
            "Tinycast refuses to plan its own uninstall by bundle ID")

        let dev = UninstallTarget(
            bundleURL: URL(fileURLWithPath: "/Applications/Tinycast Dev.app"),
            bundleID: "com.tinycast.app.dev", displayName: "Tinycast Dev", bundleName: nil)
        expect(
            UninstallIdentity.make(
                target: dev, otherAppNames: [], ownBundleID: "com.tinycast.app.dev",
                ownBundleURL: URL(fileURLWithPath: "/Applications/Tinycast Dev.app")) == nil,
            "the Dev channel refuses itself too — the check is against the running identity")
        expect(
            UninstallIdentity.make(
                target: dev, otherAppNames: [], ownBundleID: ownBundleID,
                ownBundleURL: ownBundleURL) != nil,
            "a stable build can still uninstall a Dev build, which is a different app")

        let byURL = UninstallTarget(
            bundleURL: ownBundleURL, bundleID: "com.impostor.app", displayName: "Impostor",
            bundleName: nil)
        expect(
            UninstallIdentity.make(
                target: byURL, otherAppNames: [], ownBundleID: ownBundleID,
                ownBundleURL: ownBundleURL) == nil,
            "the running bundle URL is refused even under a different ID")

        let anonymous = UninstallTarget(
            bundleURL: URL(fileURLWithPath: "/Applications/Go.app"), bundleID: nil,
            displayName: "Go", bundleName: nil)
        expect(
            UninstallIdentity.make(
                target: anonymous, otherAppNames: [], ownBundleID: ownBundleID,
                ownBundleURL: ownBundleURL) == nil,
            "no bundle ID and no safe name means nothing can be attributed")
    }

    // MARK: - Path safety

    static func testPathSafety() {
        let support = home + "/Library/Application Support"
        let bundle = "/Applications/Test App.app"
        func acceptable(_ path: String) -> Bool {
            UninstallRules.isAcceptableCandidate(
                path: path, rootPath: support, home: home, bundlePath: bundle)
        }
        expect(acceptable(support + "/TestApp"), "an immediate child of the root is acceptable")
        expect(!acceptable(support), "the root itself is never a candidate")
        expect(!acceptable(home), "the home directory is never a candidate")
        expect(!acceptable("/"), "the filesystem root is never a candidate")
        expect(!acceptable("/Applications"), "a path outside the root is rejected")
        expect(
            !acceptable(support + "/Nested/Deeper"),
            "only immediate children are accepted — the walk never descends")
        expect(
            !acceptable(support + "/../../../etc"),
            "relative components are rejected")
        expect(
            !UninstallRules.isAcceptableCandidate(
                path: bundle, rootPath: "/Applications", home: home, bundlePath: bundle),
            "the app bundle is emitted separately, never as a leftover")
        expect(
            !UninstallRules.isAcceptableCandidate(
                path: bundle + "/Contents", rootPath: bundle, home: home, bundlePath: bundle),
            "nothing inside the app bundle is a separate candidate")

        expect(
            UninstallRules.abbreviate(support, home: home) == "~/Library/Application Support",
            "a home path abbreviates to tilde form")
        expect(
            UninstallRules.abbreviate("/Library/Caches", home: home) == "/Library/Caches",
            "a path outside home is left alone")
    }

    // MARK: - Protection

    static func testProtection() {
        let environment = UninstallEnvironment(home: home, hasFullDiskAccess: false)
        let withFDA = UninstallEnvironment(home: home, hasFullDiskAccess: true)

        func classify(
            _ facts: PathFacts, _ env: UninstallEnvironment = environment
        )
            -> UninstallProtection
        {
            UninstallProtectionRules.classify(facts, environment: env)
        }

        expect(
            classify(PathFacts(path: "/Applications/Test App.app")) == .removable,
            "an ordinary user-owned app is removable")
        expect(
            classify(PathFacts(path: "/Applications/Gone.app", exists: false)) == .missing,
            "a vanished path reports as missing")
        expect(
            classify(
                PathFacts(path: "/System/Applications/Books.app", volumeIsReadOnly: true))
                == .systemProtected,
            "a read-only volume locks the row — the Books.app case")
        expect(
            classify(PathFacts(path: "/usr/bin/thing", isSystemRestricted: true)) == .systemProtected,
            "SF_RESTRICTED locks the row")
        expect(
            classify(PathFacts(path: "/Applications/Test App.app", isUserImmutable: true))
                == .userLocked,
            "Finder's Locked flag is its own case, because the user can clear it")
        expect(
            classify(PathFacts(path: "/Library/Caches/com.foo.Bar", isOwnedByCurrentUser: false))
                == .removable,
            "ownership alone never locks a row — POSIX unlink is governed by the parent directory")
        expect(
            classify(
                PathFacts(
                    path: "/tmp/com.foo.Bar", isOwnedByCurrentUser: false, parentIsSticky: true))
                == .notOwned,
            "except under a sticky parent, where only an owner may unlink")
        expect(
            classify(PathFacts(path: "/tmp/com.foo.Bar", parentIsSticky: true)) == .removable,
            "a sticky parent is fine for something you do own")
        expect(
            classify(
                PathFacts(
                    path: "/usr/local/bin/code", isOwnedByCurrentUser: false,
                    parentIsWritable: false)) == .parentNotWritable,
            "a root-owned CLI link in a root-owned bin directory reports the parent, not the owner")
        expect(
            classify(PathFacts(path: "/Library/Caches/com.foo.Bar", parentIsWritable: false))
                == .parentNotWritable,
            "trashing is a rename out of the parent, so an unwritable parent locks the row")

        let container = PathFacts(path: home + "/Library/Containers/com.foo.Bar")
        expect(
            classify(container) == .needsFullDiskAccess,
            "a container without Full Disk Access is locked, never attempted")
        expect(
            classify(container, withFDA) == .removable,
            "the same container is removable once Full Disk Access is granted")

        let everything = PathFacts(
            path: home + "/Library/Containers/com.foo.Bar", volumeIsReadOnly: true,
            isSystemRestricted: true, isUserImmutable: true, isOwnedByCurrentUser: false,
            parentIsWritable: false, parentIsSticky: true)
        expect(
            classify(everything) == .systemProtected,
            "precedence: a SIP path reports as system-protected, the most useful of its reasons")

        expect(
            UninstallProtection.allCases.allSatisfy { ($0.lockReason == nil) == $0.isRemovable },
            "every case except .removable carries a lock reason, and .removable carries none")

        expect(
            UninstallProtectionRules.isTCCProtected(
                path: home + "/Library/Group Containers/group.com.foo.Bar", home: home),
            "group containers are TCC-gated")
        expect(
            !UninstallProtectionRules.isTCCProtected(
                path: home + "/Library/Preferences/com.foo.Bar.plist", home: home),
            "preferences are not TCC-gated")
        expect(
            !UninstallProtectionRules.isTCCProtected(
                path: home + "/Library/Application Scripts/com.foo.Bar", home: home),
            "Application Scripts is NOT TCC-gated — measured, and it is why Books' scripts are removable")
        expect(
            classify(PathFacts(path: home + "/Library/Application Scripts/com.foo.Bar")) == .removable,
            "so those rows are checkable while the containers beside them stay locked")
    }

    // MARK: - Plan and selection

    /// A nil `bytes` is the unmeasured row a directory shows until its walk lands.
    static func candidate(
        _ path: String, evidence: UninstallEvidence = .bundleID,
        protection: UninstallProtection = .removable, bytes: Int64? = 100
    ) -> UninstallCandidate {
        UninstallCandidate(
            path: path, name: (path as NSString).lastPathComponent, locationLabel: "~/Library",
            evidence: evidence, isDirectory: false, size: bytes.map { MeasuredSize(bytes: $0) },
            protection: protection)
    }

    static func testSelection() {
        let target = UninstallTarget(
            bundleURL: URL(fileURLWithPath: "/Applications/Test App.app"),
            bundleID: "com.foo.Bar", displayName: "Test App", bundleName: nil)
        let free = candidate("/a", bytes: 10)
        let locked = candidate("/b", protection: .systemProtected, bytes: 20)
        let named = candidate("/c", evidence: .displayName, bytes: 40)
        let plan = UninstallPlan(
            target: target, candidates: [free, locked, named], isTargetRunning: false)

        expect(plan.removableIDs == ["/a", "/c"], "locked candidates are not removable")
        expect(plan.lockedCount == 1, "the locked count counts exactly the locked rows")
        expect(plan.totalBytes == 70, "total bytes covers every candidate")

        let everything = UninstallSelection(plan: plan, checked: ["/a", "/b", "/c", "/nope"])
        expect(
            everything.checked == ["/a", "/c"],
            "a locked or out-of-plan id can never enter the checked set")

        var selection = plan.defaultSelection
        expect(
            selection.checked == ["/a", "/c"],
            "the default checks every removable row, name matches included")
        expect(selection.bytes(in: plan) == 50, "selected bytes sums only checked rows")
        expect(
            !selection.checked.contains("/b"), "and never a locked one")

        selection.toggle("/b", in: plan)
        expect(selection.checked == ["/a", "/c"], "toggling a locked row is a no-op")
        selection.toggle("/b", in: plan)
        expect(selection.checked == ["/a", "/c"], "toggling a locked row twice is still a no-op")

        selection.toggle("/c", in: plan)
        expect(selection.checked == ["/a"], "toggling a checked row unchecks it")
        selection.toggle("/c", in: plan)
        expect(selection.checked == ["/a", "/c"], "toggling it again checks it back")

        let relocked = UninstallPlan(
            target: target,
            candidates: [candidate("/a", protection: .notOwned, bytes: 10), locked, named],
            isTargetRunning: false)
        expect(
            UninstallSelection(plan: relocked, checked: ["/a", "/c"]).checked == ["/c"],
            "re-scanning drops a row that has since become locked")

        expect(
            UninstallSelection(plan: plan).candidates(in: plan).isEmpty,
            "an empty selection resolves to no candidates")
    }

    // MARK: - Streamed sizes

    /// The list paints before any directory is walked, so a landing size must disturb nothing else.
    static func testStreamedSizes() {
        let target = UninstallTarget(
            bundleURL: URL(fileURLWithPath: "/Applications/Test App.app"),
            bundleID: "com.foo.Bar", displayName: "Test App", bundleName: nil)
        var plan = UninstallPlan(
            target: target,
            candidates: [
                candidate("/a", bytes: nil), candidate("/b", protection: .systemProtected, bytes: 20),
                candidate("/c", bytes: nil)
            ],
            isTargetRunning: false)

        expect(plan.totalBytes == 20, "an unmeasured row counts as zero rather than blocking a total")

        let selection = plan.defaultSelection
        expect(selection.checked == ["/a", "/c"], "selection is settled before any walk lands")
        expect(selection.bytes(in: plan) == 0, "and its bytes start at zero while both are pending")

        plan.setSize(MeasuredSize(bytes: 500), forPath: "/c")
        expect(plan.candidates.map(\.path) == ["/a", "/b", "/c"], "a landing size never reorders")
        expect(plan.candidates[2].size?.bytes == 500, "it lands on the row it measured")
        expect(plan.candidates[0].size == nil, "and leaves its neighbours pending")
        expect(plan.totalBytes == 520, "the total grows as each walk lands")
        expect(selection.bytes(in: plan) == 500, "and so does the selection's, checked set intact")

        plan.setSize(MeasuredSize(bytes: 9), forPath: "/nowhere")
        expect(plan.totalBytes == 520, "a path outside the plan is a no-op")

        plan.setSize(MeasuredSize(bytes: 7, isLowerBound: true), forPath: "/a")
        expect(
            plan.candidates[0].size?.isLowerBound == true,
            "a budget-capped walk keeps its lower-bound marker through the write")
        expect(
            UninstallSelection(plan: plan, checked: selection.checked).checked == ["/a", "/c"],
            "and a plan rebuilt after every size still locks out exactly what it did before")
    }

    // MARK: - Cross-identity sweep

    /// The one assertion about the matcher as a whole: no artifact belonging to one app may ever be
    /// produced for another. A rule that regresses in isolation still gets caught here.
    static func testCrossIdentitySweep() {
        let apps: [(id: String, name: String)] = [
            ("com.apple.iBooksX", "Books"),
            ("com.apple.Safari", "Safari"),
            ("net.freemacsoft.AppCleaner", "AppCleaner"),
            ("com.google.Chrome", "Google Chrome"),
            ("com.microsoft.VSCode", "Visual Studio Code"),
            ("org.mozilla.firefox", "Firefox"),
            ("com.spotify.client", "Spotify"),
            ("com.tinyspeck.slackmacgap", "Slack")
        ]
        let identities = apps.map { app in
            (app, identity(bundleID: app.id, name: app.name, path: "/Applications/\(app.name).app"))
        }
        // Every artifact shape the roots actually contain, instantiated for each app.
        let shapes: [(String) -> String] = [
            { $0 }, { $0 + ".plist" }, { $0 + ".savedState" }, { $0 + ".binarycookies" },
            { $0 + ".helper" }, { $0 + ".Renderer.plist" }, { "group." + $0 },
            { "ABCDE12345." + $0 }, { $0 + ".8A1F2C3D-1111-2222-3333-444455556666.plist" }
        ]

        var leaks: [String] = []
        for (owner, _) in identities {
            let artifacts =
                shapes.map { $0(owner.id) } + [owner.name, owner.name + ".plist"]
            for artifact in artifacts {
                for (other, otherIdentity) in identities where other.id != owner.id {
                    for root in UninstallSearchRoot.all
                    where UninstallRules.evidence(for: artifact, in: root, identity: otherIdentity)
                        != nil
                    {
                        leaks.append(
                            "\(artifact) (\(owner.name)) matched \(other.name) in \(root.relativePath)")
                    }
                }
            }
        }
        expect(leaks.isEmpty, "no app's artifacts are ever attributed to another app")
        for leak in leaks.prefix(10) { print("  leak: \(leak)") }
    }

    // MARK: - Table sanity

    static func testRootTable() {
        let roots = UninstallSearchRoot.all
        expect(!roots.isEmpty, "the root table is populated")
        expect(
            Set(roots.map { "\($0.base)/\($0.relativePath)" }).count == roots.count,
            "no root is listed twice")
        expect(roots.allSatisfy { !$0.relativePath.isEmpty }, "no root has an empty relative path")
        expect(
            !roots.contains { $0.relativePath == "." || $0.relativePath.hasPrefix("..") },
            "no root escapes its base")
        expect(roots.allSatisfy { !$0.styles.isEmpty }, "every root enables at least one match style")
        expect(
            roots.allSatisfy { !$0.relativePath.hasPrefix("/") && !$0.relativePath.hasSuffix("/") },
            "relative paths carry no leading or trailing slash")
        expect(
            roots.first { $0.base == .userLibrary && $0.relativePath == "Application Support" }?
                .path(home: home) == home + "/Library/Application Support",
            "a user root expands under the injected home directory")
        expect(
            roots.first { $0.base == .systemLibrary && $0.relativePath == "Caches" }?.path(home: home)
                == "/Library/Caches",
            "a system root ignores the home directory")
        // A child of these is a bundle ID by construction, so a name match there is a false positive
        // by definition. Asserting the exclusion rather than the inclusion keeps this honest as
        // plug-in wells are added.
        let bundleIDOnly: Set<String> = [
            "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
            "Application Scripts", "Saved Application State", "HTTPStorages", "WebKit", "Cookies",
            "Autosave Information", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools"
        ]
        expect(
            roots.filter { bundleIDOnly.contains($0.relativePath) }
                .allSatisfy { !$0.styles.contains(.displayName) },
            "display-name matching never applies where a child is a bundle ID by construction")
        expect(
            roots.contains { $0.relativePath == "Application Support" && $0.styles.contains(.displayName) },
            "but it does apply in the human-named roots")
        expect(
            !roots.contains { $0.relativePath.contains("receipts") || $0.relativePath == "Keychains" },
            "receipts and keychains stay out of scope")
    }

    static func main() {
        testBundleIDMatching()
        testExtensionStripping()
        testGroupContainers()
        testDisplayNames()
        testPlugInsAndSymlinks()
        testHomeIsOutOfScope()
        testIdentityRefusal()
        testPathSafety()
        testProtection()
        testSelection()
        testStreamedSizes()
        testCrossIdentitySweep()
        testRootTable()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
