import Foundation
import Observation
import Testing

@testable import Tinycast

@MainActor
struct MenuSearchTests {
    @Test(arguments: [
        ("Export", true, false, false, true, true),
        ("Export", false, false, false, true, false),
        ("Export", true, true, false, true, false),
        ("Export", true, false, true, true, false),
        ("Export", true, false, false, false, false),
        ("", true, false, false, true, false),
        ("   ", true, false, false, true, false)
    ])
    func onlyEnabledVisiblePressableNamedLeavesAreEligible(
        _ title: String, _ enabled: Bool, _ hidden: Bool, _ separator: Bool, _ pressable: Bool,
        _ expected: Bool
    ) {
        #expect(
            MenuSearchItem.isEligible(
                title: title, isEnabled: enabled, isHidden: hidden, isSeparator: separator,
                canPress: pressable) == expected)
    }

    @Test func pathsSeparateGroupingFromSearchingAndDisambiguateIdentity() {
        let pdf = MenuSearchItem(title: "PDF", parentComponents: ["File", "Export as"])
        #expect(pdf.displayPath == "File → Export as → PDF")
        #expect(pdf.id != MenuSearchItem(title: "PDF", parentComponents: ["Edit"]).id)
        #expect(pdf.menu == "File")
        #expect(pdf.menuPath == "File → Export as")
        #expect(pdf.submenuPath == "Export as")
        #expect(MenuSearchItem(title: "About", parentComponents: []).displayPath == "About")
        #expect(MenuSearchItem(title: "About", parentComponents: ["Apple"]).submenuPath.isEmpty)
    }

    @Test(arguments: [("pd", true), ("exp", true), ("fxa", false)])
    func titleMatchesFuzzilyAndParentPathMatchesLiterally(_ query: String, _ expected: Bool) {
        let pdf = MenuSearchItem(title: "PDF", parentComponents: ["File", "Export as"])
        #expect((SearchRelevance.quality(query: query, fields: pdf.searchFields()) != nil) == expected)
    }

    @Test func aTitleHitOutranksAPathOnlyHit() throws {
        let title = MenuSearchItem(title: "Export", parentComponents: ["File"])
        let path = MenuSearchItem(title: "PDF", parentComponents: ["File", "Export as"])
        let titleHit = try #require(SearchRelevance.quality(query: "export", fields: title.searchFields()))
        let pathHit = try #require(SearchRelevance.quality(query: "export", fields: path.searchFields()))
        #expect(titleHit > pathHit)

        let panel = MenuSearchItem(title: "Export Panel", parentComponents: ["View"])
        #expect(MenuSearchQuery.rank([path, panel], for: "export").map(\.title) == ["Export Panel", "PDF"])
    }

    @Test(
        arguments: [
            ("s", true, true, false, false, "⇧⌘S"),
            ("x", true, true, true, true, "⌃⌥⇧⌘X"),
            ("", true, false, false, false, nil),
            ("\u{F707}", false, false, false, false, "F4")
        ] as [(String, Bool, Bool, Bool, Bool, String?)])
    func shortcutGlyphsFollowMenuOrder(
        _ key: String, _ command: Bool, _ shift: Bool, _ option: Bool, _ control: Bool, _ expected: String?
    ) {
        let shortcut = MenuSearchShortcut(
            character: key, hasCommand: command, hasShift: shift, hasOption: option, hasControl: control)
        #expect(shortcut.displayString == expected)
    }

    @Test func aMenuItemCanCarryOnlyItsPath() {
        #expect(MenuSearchItem(title: "Save", parentComponents: ["File"]).shortcut == nil)
    }

    @Test func exactAndPrefixTitlesLeadEvenWithReversedTermsInTheResults() throws {
        let candidates = ["Report Annual", "My Annual Report", "Annual Report", "Annual Reporting Notes"].map
        {
            MenuSearchItem(title: $0, parentComponents: ["File"])
        }
        let titles = MenuSearchQuery.rank(candidates, for: "annual report").map(\.title)
        let prefix = try #require(titles.firstIndex(of: "Annual Reporting Notes"))
        let inner = try #require(titles.firstIndex(of: "My Annual Report"))
        #expect(titles.first == "Annual Report")
        #expect(prefix < inner)
        #expect(titles.last == "Report Annual")
        #expect(MenuSearchQuery.rank(candidates, for: "   ").isEmpty)
    }

    @Test func equalTitlesBreakTiesByPath() {
        let items = ["Edit", "Format"].map { MenuSearchItem(title: "Copy", parentComponents: [$0]) }
        #expect(
            MenuSearchQuery.rank(items, for: "copy").map(\.displayPath) == ["Edit → Copy", "Format → Copy"])
    }

    @Test func rankingCapsTheNumberOfPublishedRows() {
        let items = (0..<205).map { MenuSearchItem(title: "Report \($0)", parentComponents: ["File"]) }
        #expect(MenuSearchQuery.rank(items, for: "report").count == MenuSearchQuery.resultLimit)
    }

    @Test func collectionWalksEveryEligibleLeafAndSkipsCollapsedSubmenus() throws {
        let file = branch(
            "File",
            [
                leaf("New"),
                leaf("Open…", enabled: false),
                branch("Export as", [leaf("PDF"), leaf("Hidden Draft", hidden: true)]),
                leaf("Recent", submenu: true),
                leaf("", separator: true),
                leaf("Reload", pressable: false)
            ])
        let items = MenuSnapshotPolicy.collect([branch("", [file, branch("Edit", [leaf("Copy")])])])
        #expect(items.map(\.displayPath) == ["File → New", "File → Export as → PDF", "Edit → Copy"])
        let pdf = try #require(items.first { $0.title == "PDF" })
        #expect(pdf.shortcut == nil)
        #expect(items.allSatisfy { $0.title != "Recent" })
    }

    @Test(arguments: [(10, ["Deep"]), (25, [])])
    func collectionEnforcesTheDepthBudget(_ depth: Int, _ expected: [String]) {
        let menu = (1...depth).reversed().reduce(leaf("Deep")) { child, level in
            branch("Level \(level)", [child])
        }
        #expect(MenuSnapshotPolicy.collect([branch("", [menu])]).map(\.title) == expected)
    }

    @Test func theGlobalBudgetKeepsOnlyThePreorderPrefix() throws {
        let menus = (0..<25).map { menu in branch("Menu \(menu)", leaves("Item", count: 200)) }
        let items = MenuSnapshotPolicy.collect([branch("", menus)])
        #expect(items.count == MenuSnapshotPolicy.itemLimit)
        let first = try #require(items.first)
        let last = try #require(items.last)
        #expect(first.displayPath == "Menu 0 → Item 0")
        #expect(last.displayPath == "Menu 19 → Item 199")
    }

    @Test func aSingleSubmenuHasItsOwnPreorderBudget() throws {
        let items = MenuSnapshotPolicy.collect([branch("", [branch("History", leaves("Item", count: 500))])])
        #expect(items.count == MenuSnapshotPolicy.perSubmenuLimit)
        let first = try #require(items.first)
        let last = try #require(items.last)
        #expect(first.title == "Item 0")
        #expect(last.title == "Item 199")
    }

    @Test func aNestedSubmenuKeepsIndependentCapacity() throws {
        let file = branch("File", leaves("File", count: 150) + [branch("More", leaves("Deep", count: 150))])
        #expect(MenuSnapshotPolicy.collect([branch("", [file])]).count == 300)
        let history = branch(
            "History", leaves("Item", count: 250) + [branch("More", [leaf("Extra A"), leaf("Extra B")])])
        let items = MenuSnapshotPolicy.collect([branch("", [history])])
        #expect(items.count == MenuSnapshotPolicy.perSubmenuLimit + 2)
        let last = try #require(items.last)
        #expect(last.title == "Extra B")
    }

    @Test(arguments: [(false, 5), (true, 9)])
    func cancellationAlwaysReturnsAPreorderPrefix(_ nested: Bool, _ budget: Int) {
        let nodes =
            nested
            ? [branch("A", (0..<5).map { leaf("A\($0)") }), branch("B", (0..<5).map { leaf("B\($0)") })]
            : leaves("Item", count: 10)
        let bar = [branch("", nodes)]
        let full = MenuSnapshotPolicy.collect(bar)
        var visits = 0
        let partial = MenuSnapshotPolicy.collect(bar) {
            visits += 1
            return visits > budget
        }
        #expect(!partial.isEmpty)
        #expect(partial.count < full.count)
        #expect(partial == Array(full.prefix(partial.count)))
    }

    @Test func theSameFrozenTreeProducesTheSameValue() {
        let bar = [branch("", [branch("File", [leaf("New")])])]
        #expect(MenuSnapshotPolicy.collect(bar) == MenuSnapshotPolicy.collect(bar))
    }

    @Test func duplicatePathsCollapseWhileDifferentParentsStay() {
        let bar = [
            branch(
                "",
                [
                    branch("File", [leaf("Eject")]),
                    branch("Special", [leaf("Eject")]),
                    branch("File", [leaf("Eject")])
                ])
        ]
        #expect(MenuSnapshotPolicy.collect(bar).map(\.displayPath) == ["File → Eject", "Special → Eject"])
    }

    @Test func hidingTheAppleMenuRemovesOnlyTheFirstRoot() {
        let bar = [
            branch("Apple", [branch("", [leaf("About This Mac")])]),
            branch("File", [branch("", [leaf("New")])])
        ]
        #expect(MenuSnapshotPolicy.collect(bar).map(\.title) == ["About This Mac", "New"])
        #expect(
            MenuSnapshotPolicy.collect(MenuSnapshotPolicy.excludingAppleMenu(bar)).map(\.title) == ["New"])
        #expect(MenuSnapshotPolicy.excludingAppleMenu([]).isEmpty)
    }

    @Test(
        arguments: [
            ("TextEdit", false, true, false, .searchable(name: "TextEdit")),
            ("Tinycast", true, false, false, .selfTarget),
            ("Helper", false, false, false, .menuLess(name: "Helper")),
            (nil, false, true, false, .noApplication),
            ("Passwords", false, true, true, .excluded(name: "Passwords")),
            ("Helper", false, false, true, .excluded(name: "Helper")),
            ("Tinycast", true, true, true, .selfTarget)
        ] as [(String?, Bool, Bool, Bool, MenuSearchTarget)])
    func selfAndExclusionTakePrecedenceWhenClassifyingATarget(
        _ name: String?, _ isSelf: Bool, _ hasBar: Bool, _ excluded: Bool, _ expected: MenuSearchTarget
    ) {
        #expect(
            MenuSearchTarget.classify(appName: name, isSelf: isSelf, hasMenuBar: hasBar, isExcluded: excluded)
                == expected)
    }

    @Test func filteringAndClearingQueriesKeepsTheOriginalSnapshot() {
        let session = MenuSearchSession()
        let items = [
            MenuSearchItem(title: "New", parentComponents: ["File"]),
            MenuSearchItem(title: "Copy", parentComponents: ["Edit"])
        ]
        session.present(target: .searchable(name: "TextEdit"), snapshot: items)
        #expect(session.filtered == items)
        #expect(!session.isSearching)
        session.filter("copy")
        #expect(session.filtered.map(\.title) == ["Copy"])
        #expect(session.isSearching)
        session.filter("   ")
        #expect(!session.isSearching)
        #expect(session.filtered == items)
        session.filter("zzz")
        #expect(session.filtered.isEmpty)
        #expect(session.snapshot == items)
        session.filter("")
        #expect(session.filtered == items)

        session.filter("copy")
        session.reset()
        #expect(session.snapshot.isEmpty)
        #expect(session.filtered.isEmpty)
        #expect(!session.isSearching)
        #expect(session.target == .noApplication)
    }

    @Test(arguments: [
        ("N", 0, "⌘N"), ("N", 0b001, "⇧⌘N"), ("N", 0b010, "⌥⌘N"), ("N", 0b100, "⌃⌘N"),
        ("D", 0b011, "⌥⇧⌘D"), ("\u{8}", 0b001, "⇧⌘⌫"), ("\u{1B}", 0b011, "⌥⇧⌘esc"),
        ("f", 0b1100, "⌃F"), ("\u{F70A}", 0b1000, "F7"), ("\u{F700}", 0b100, "⌃⌘↑")
    ])
    func axModifierBitsAndSpecialCharactersMapToShortcutGlyphs(
        _ character: String, _ modifiers: Int, _ expected: String
    ) throws {
        let shortcut = try #require(
            MenuSearchShortcut.commandEquivalent(character: character, modifiers: modifiers))
        #expect(shortcut.displayString == expected)
    }

    @Test(arguments: [("", 0), ("E", 0b10000)])
    func noShortcutIsDecodedFromAMissingCharacterOrUnsupportedBits(_ character: String, _ modifiers: Int) {
        #expect(MenuSearchShortcut.commandEquivalent(character: character, modifiers: modifiers) == nil)
    }

    @Test func shortcutKeycapsMatchTheRenderedChord() throws {
        let all = MenuSearchShortcut(
            character: "x", hasCommand: true, hasShift: true, hasOption: true, hasControl: true)
        let missing = MenuSearchShortcut(
            character: "", hasCommand: true, hasShift: true, hasOption: false, hasControl: false)
        let arrow = try #require(
            MenuSearchShortcut.commandEquivalent(character: "\u{F700}", modifiers: 0b100))
        #expect(all.keycaps == ["⌃", "⌥", "⇧", "⌘", "X"])
        #expect(missing.keycaps.isEmpty)
        #expect(arrow.keycaps == ["⌃", "⌘", "↑"])
    }

    @Test(.timeLimit(.minutes(1)))
    func oneWalkMovesFromReadingToPublishedRows() async {
        let walker = MenuWalk()
        let session = MenuSearchSession(walkOperation: walker.walk)
        session.startWalk(target: .searchable(name: "TextEdit"), pid: 42, showsAppleMenu: true)
        #expect(session.state == .reading)
        #expect(session.filtered.isEmpty)
        await ready(session)
        #expect(session.snapshot.map(\.title) == ["Walk 1"])
        #expect(session.filtered.map(\.title) == ["Walk 1"])
        #expect(await walker.calls == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func aNewTargetSupersedesTheWalkInProgress() async {
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let walker = MenuWalk(firstStarted: started.continuation, firstRelease: release.stream)
        let session = MenuSearchSession(walkOperation: walker.walk)
        defer { release.continuation.finish() }
        session.startWalk(target: .searchable(name: "A"), pid: 1, showsAppleMenu: true)
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()

        session.startWalk(target: .searchable(name: "B"), pid: 2, showsAppleMenu: true)
        await ready(session)
        #expect(session.target == .searchable(name: "B"))
        #expect(session.snapshot.map(\.title) == ["Walk 2"])
    }

    private func ready(_ session: MenuSearchSession) async {
        for await state in Observations({ @MainActor in session.state }) where state == .ready {
            break
        }
    }

    private actor MenuWalk {
        private let firstStarted: AsyncStream<Void>.Continuation?
        private let firstRelease: AsyncStream<Void>?
        private(set) var calls = 0

        init(
            firstStarted: AsyncStream<Void>.Continuation? = nil, firstRelease: AsyncStream<Void>? = nil
        ) {
            self.firstStarted = firstStarted
            self.firstRelease = firstRelease
        }

        func walk(_ pid: pid_t, _ showsAppleMenu: Bool) async -> [MenuSearchItem] {
            calls += 1
            let invocation = calls
            if invocation == 1, let firstRelease {
                firstStarted?.yield()
                firstStarted?.finish()
                var iterator = firstRelease.makeAsyncIterator()
                _ = await iterator.next()
            }
            return [MenuSearchItem(title: "Walk \(invocation)", parentComponents: ["Menu"])]
        }
    }

    private func branch(_ title: String, _ children: [MenuTreeNode]) -> MenuTreeNode {
        MenuTreeNode(title: title, children: children)
    }

    private func leaves(_ stem: String, count: Int) -> [MenuTreeNode] {
        (0..<count).map { leaf("\(stem) \($0)") }
    }

    private func leaf(
        _ title: String, enabled: Bool = true, hidden: Bool = false, separator: Bool = false,
        pressable: Bool = true, submenu: Bool = false
    ) -> MenuTreeNode {
        MenuTreeNode(
            title: title, isEnabled: enabled, isHidden: hidden, isSeparator: separator,
            canPress: pressable, hasSubmenu: submenu)
    }
}
