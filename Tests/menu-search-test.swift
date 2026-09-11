import Foundation

@main
@MainActor
struct MenuSearchTests {
    static var failures = 0

    actor WalkProbe {
        private(set) var calls = 0
        private let firstSlow: Bool

        init(firstSlow: Bool = false) { self.firstSlow = firstSlow }

        func walk(_ pid: pid_t) async -> [MenuSearchItem] {
            calls += 1
            let call = calls
            if firstSlow, call == 1 { try? await Task.sleep(for: .milliseconds(200)) }
            return [MenuSearchItem(title: "Walk \(call)", parentComponents: ["Menu"])]
        }
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func item(
        _ title: String, parents: [String] = ["File"],
        shortcut: MenuSearchShortcut? = nil
    ) -> MenuSearchItem {
        MenuSearchItem(title: title, parentComponents: parents, shortcut: shortcut)
    }

    static func eligible(
        _ title: String = "Export", enabled: Bool = true, hidden: Bool = false,
        separator: Bool = false, pressable: Bool = true
    ) -> Bool {
        MenuSearchItem.isEligible(
            title: title, isEnabled: enabled, isHidden: hidden, isSeparator: separator,
            canPress: pressable)
    }

    static func tree(
        _ title: String, children: [MenuTreeNode] = [],
        enabled: Bool = true, hidden: Bool = false, separator: Bool = false,
        pressable: Bool = true, submenu: Bool = false, shortcut: MenuSearchShortcut? = nil
    ) -> MenuTreeNode {
        MenuTreeNode(
            title: title, isEnabled: enabled, isHidden: hidden, isSeparator: separator,
            canPress: pressable, hasSubmenu: submenu, shortcut: shortcut, children: children)
    }

    static func chain(_ levels: Int) -> [MenuTreeNode] {
        var leaf: [MenuTreeNode] = [tree("Deep")]
        for level in (1...levels).reversed() {
            leaf = [tree("Level \(level)", children: leaf)]
        }
        return [tree("", children: leaf)]
    }

    static func main() async {
        eligibility()
        pathModel()
        searchMapping()
        shortcutModel()
        ranking()
        snapshotCollect()
        snapshotDepth()
        snapshotLimit()
        snapshotPerSubmenu()
        snapshotCancel()
        snapshotFrozen()
        snapshotDuplicates()
        targetClassify()
        sessionPresent()
        shortcutDecoding()
        await sessionWalk()
        await sessionWalkSuperseded()

        print(failures == 0 ? "Menu search tests passed" : "\(failures) menu search tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func eligibility() {
        expect(eligible(), "an enabled visible pressable leaf is a Menu Item")
        expect(!eligible(enabled: false), "a disabled row is never activatable")
        expect(!eligible(hidden: true), "a hidden row is never activatable")
        expect(!eligible(separator: true), "a separator is never activatable")
        expect(!eligible(pressable: false), "a row with no press action is never activatable")
        expect(!eligible(""), "an untitled row is never activatable")
        expect(!eligible("   "), "a whitespace-only title is never activatable")
    }

    static func pathModel() {
        let nested = item("PDF", parents: ["File", "Export as"])
        expect(nested.displayPath == "File > Export as > PDF", "the path spans bar to leaf")
        expect(item("About", parents: []).displayPath == "About", "a top-level leaf is bare")
        expect(nested.id != item("PDF", parents: ["Edit"]).id, "identity includes the path")
    }

    static func searchMapping() {
        let pdf = item("PDF", parents: ["File", "Export as"])
        expect(
            SearchRelevance.quality(query: "pd", fields: pdf.searchFields()) != nil,
            "the leaf title matches fuzzily")
        expect(
            SearchRelevance.quality(query: "exp", fields: pdf.searchFields()) != nil,
            "the Menu Path contributes as a literal signal")
        expect(
            SearchRelevance.quality(query: "fxa", fields: pdf.searchFields()) == nil,
            "a subsequence spanning only the path matches nothing")
        let titleHit = SearchRelevance.quality(query: "export", fields: item("Export").searchFields())!
        let pathHit = SearchRelevance.quality(
            query: "export", fields: item("PDF", parents: ["File", "Export as"]).searchFields())!
        expect(titleHit > pathHit, "a title hit outranks a path-only hit")
    }

    static func shortcutModel() {
        let full = MenuSearchShortcut(
            character: "s", hasCommand: true, hasShift: true, hasOption: false,
            hasControl: false)
        expect(full.displayString == "⇧⌘S", "glyphs read control, option, shift, command")
        let ordered = MenuSearchShortcut(
            character: "x", hasCommand: true, hasShift: true, hasOption: true,
            hasControl: true)
        expect(ordered.displayString == "⌃⌥⇧⌘X", "every modifier appears in menu order")
        expect(
            MenuSearchShortcut(
                character: "", hasCommand: true, hasShift: false, hasOption: false,
                hasControl: false
            ).displayString == nil, "a missing character shows no glyph")
        expect(
            MenuSearchShortcut(
                character: "s", hasCommand: false, hasShift: false, hasOption: false,
                hasControl: false
            ).displayString == nil, "a modifier-less character shows no glyph")
        expect(item("Save").shortcut == nil, "a shortcut-less item carries path alone")
    }

    static func ranking() {
        let candidates = [
            item("Report Annual", parents: ["File"]),
            item("My Annual Report", parents: ["File"]),
            item("Annual Report", parents: ["File"]),
            item("Annual Reporting Notes", parents: ["File"])
        ]
        let ranked = MenuSearchQuery.rank(candidates, for: "annual report").map(\.title)
        expect(ranked.first == "Annual Report", "an exact leaf title ranks first")
        expect(
            ranked.firstIndex(of: "Annual Reporting Notes")!
                < ranked.firstIndex(of: "My Annual Report")!,
            "a prefix beats a later word-start match")
        expect(ranked.last == "Report Annual", "reversed terms stay present but rank last")

        let pathOnly = MenuSearchQuery.rank(
            [item("PDF", parents: ["File", "Export as"]), item("Export Panel", parents: ["View"])],
            for: "export")
        expect(
            pathOnly.map(\.title) == ["Export Panel", "PDF"],
            "a title hit leads a path-only hit for the same query")

        let ties = MenuSearchQuery.rank(
            [item("Copy", parents: ["Edit"]), item("Copy", parents: ["Format"])], for: "copy")
        expect(
            ties.map(\.displayPath) == ["Edit > Copy", "Format > Copy"],
            "identical titles break ties on the path")

        let capped = (0..<205).map { item("Report \($0)", parents: ["File"]) }
        expect(
            MenuSearchQuery.rank(capped, for: "report").count == MenuSearchQuery.resultLimit,
            "ranking publishes no more than the display cap")
        expect(
            MenuSearchQuery.rank(candidates, for: "   ").isEmpty,
            "an empty query ranks nothing; browsing is the session's job")
    }

    static func snapshotCollect() {
        let bar: [MenuTreeNode] = [
            tree(
                "",
                children: [
                    tree(
                        "File",
                        children: [
                            tree("New"),
                            tree("Open…", enabled: false),
                            tree(
                                "Export as",
                                children: [
                                    tree("PDF"),
                                    tree("Hidden Draft", hidden: true)
                                ]),
                            tree("Recent", submenu: true),
                            tree("", separator: true),
                            tree("Reload", pressable: false)
                        ]),
                    tree("Edit", children: [tree("Copy")])
                ])
        ]
        let items = MenuSnapshotPolicy.collect(bar)
        expect(
            items.map(\.displayPath) == ["File > New", "File > Export as > PDF", "Edit > Copy"],
            "one snapshot holds every eligible leaf with its full path")
        expect(
            items.first { $0.title == "PDF" }?.shortcut == nil,
            "a leaf without AX shortcut data carries path alone")
        expect(
            items.allSatisfy { $0.title != "Recent" },
            "a collapsed submenu is accepted as missing, never emitted as a leaf")
    }

    static func snapshotDepth() {
        expect(
            MenuSnapshotPolicy.collect(chain(10)).map(\.title) == ["Deep"],
            "a leaf within the depth budget is collected")
        expect(
            MenuSnapshotPolicy.collect(chain(25)).isEmpty,
            "a leaf past the depth budget is silently absent")
    }

    static func snapshotLimit() {
        let bar: [MenuTreeNode] = [
            tree(
                "",
                children: (0..<25).map { menu in
                    tree("Menu \(menu)", children: (0..<200).map { tree("Item \($0)") })
                })
        ]
        let items = MenuSnapshotPolicy.collect(bar)
        expect(
            items.count == MenuSnapshotPolicy.itemLimit,
            "the snapshot truncates silently at the item cap")
        expect(
            items.first?.displayPath == "Menu 0 > Item 0"
                && items.last?.displayPath == "Menu 19 > Item 199",
            "truncation keeps pre-order, so ranking still sees the front of the menu")
    }

    static func snapshotPerSubmenu() {
        let history: [MenuTreeNode] = [
            tree(
                "",
                children: [
                    tree("History", children: (0..<500).map { tree("Item \($0)") })
                ])
        ]
        let capped = MenuSnapshotPolicy.collect(history)
        expect(
            capped.count == MenuSnapshotPolicy.perSubmenuLimit,
            "one giant submenu stops at the per-submenu cap, not the global one")
        expect(
            capped.first?.title == "Item 0" && capped.last?.title == "Item 199",
            "the cap keeps pre-order, so the submenu's front stays searchable")

        let nested: [MenuTreeNode] = [
            tree(
                "",
                children: [
                    tree(
                        "File",
                        children: (0..<150).map { tree("File \($0)") }
                            + [tree("More", children: (0..<150).map { tree("Deep \($0)") })])
                ])
        ]
        let nestedItems = MenuSnapshotPolicy.collect(nested)
        expect(
            nestedItems.count == 300,
            "nested submenus carry their own budget instead of sharing one")

        let trailing: [MenuTreeNode] = [
            tree(
                "",
                children: [
                    tree(
                        "History",
                        children: (0..<250).map { tree("Item \($0)") }
                            + [tree("More", children: [tree("Extra A"), tree("Extra B")])])
                ])
        ]
        let trailingItems = MenuSnapshotPolicy.collect(trailing)
        expect(
            trailingItems.count == MenuSnapshotPolicy.perSubmenuLimit + 2
                && trailingItems.last?.title == "Extra B",
            "a full frame still walks later parents into their own budget")
    }

    static func snapshotCancel() {
        let bar: [MenuTreeNode] = [tree("", children: (0..<10).map { tree("Item \($0)") })]
        let full = MenuSnapshotPolicy.collect(bar)
        var visits = 0
        let partial = MenuSnapshotPolicy.collect(bar) {
            visits += 1
            return visits > 5
        }
        expect(!partial.isEmpty && partial.count < full.count, "cancellation stops the walk early")
        expect(
            partial == Array(full.prefix(partial.count)),
            "a cancelled snapshot is a prefix of the full one, never a reshuffle")

        let nested: [MenuTreeNode] = [
            tree(
                "",
                children: [
                    tree("A", children: (0..<5).map { tree("A\($0)") }),
                    tree("B", children: (0..<5).map { tree("B\($0)") })
                ])
        ]
        let nestedFull = MenuSnapshotPolicy.collect(nested)
        var nestedVisits = 0
        let nestedPartial = MenuSnapshotPolicy.collect(nested) {
            nestedVisits += 1
            return nestedVisits > 9
        }
        expect(
            !nestedPartial.isEmpty && nestedPartial.count < nestedFull.count
                && nestedPartial == Array(nestedFull.prefix(nestedPartial.count)),
            "cancellation inside a submenu still yields a prefix, never resumes siblings")
    }

    static func snapshotFrozen() {
        let bar: [MenuTreeNode] = [tree("", children: [tree("File", children: [tree("New")])])]
        expect(
            MenuSnapshotPolicy.collect(bar) == MenuSnapshotPolicy.collect(bar),
            "the snapshot is a value: the same tree always yields the same items")
    }

    static func targetClassify() {
        expect(
            MenuSearchTarget.classify(appName: "TextEdit", isSelf: false, hasMenuBar: true)
                == .searchable(name: "TextEdit"),
            "a regular app is searchable under its own name")
        expect(
            MenuSearchTarget.classify(appName: "Tinycast", isSelf: true, hasMenuBar: false)
                == .selfTarget,
            "self wins over the menu-bar check, since Tinycast itself runs accessory")
        expect(
            MenuSearchTarget.classify(appName: "Helper", isSelf: false, hasMenuBar: false)
                == .menuLess(name: "Helper"),
            "a background app keeps its name for the empty state")
        expect(
            MenuSearchTarget.classify(appName: nil, isSelf: false, hasMenuBar: true)
                == .noApplication,
            "no captured app is its own empty state")
    }

    static func sessionPresent() {
        let session = MenuSearchSession()
        let items = [item("New", parents: ["File"]), item("Copy", parents: ["Edit"])]
        session.present(target: .searchable(name: "TextEdit"), snapshot: items)
        expect(
            session.filtered == items,
            "presenting shows the whole snapshot before anything is typed")
        session.filter("copy")
        expect(
            session.filtered.map(\.title) == ["Copy"],
            "a typed query filters the frozen snapshot")
        session.filter("zzz")
        expect(session.filtered.isEmpty, "a matchless query empties the rows, not the snapshot")
        expect(session.snapshot == items, "filtering never shrinks what was captured")
        session.filter("")
        expect(session.filtered == items, "clearing the query browses the whole snapshot again")
        session.reset()
        expect(
            session.snapshot.isEmpty && session.filtered.isEmpty
                && session.target == .noApplication,
            "reset clears the show back to no application")
    }

    static func shortcutDecoding() {
        let plain = MenuSearchShortcut.commandEquivalent(character: "N", modifiers: 0)
        expect(plain?.displayString == "⌘N", "a bare character implies ⌘")
        let shifted = MenuSearchShortcut.commandEquivalent(character: "N", modifiers: 0b001)
        expect(shifted?.displayString == "⇧⌘N", "bit 0 is Shift")
        let optioned = MenuSearchShortcut.commandEquivalent(character: "N", modifiers: 0b010)
        expect(optioned?.displayString == "⌥⌘N", "bit 1 is Option")
        let controlled = MenuSearchShortcut.commandEquivalent(character: "N", modifiers: 0b100)
        expect(controlled?.displayString == "⌃⌘N", "bit 2 is Control")
        let chord = MenuSearchShortcut.commandEquivalent(character: "D", modifiers: 0b011)
        expect(chord?.displayString == "⌥⇧⌘D", "combined bits stack in menu order")
        expect(
            MenuSearchShortcut.commandEquivalent(character: "", modifiers: 0) == nil,
            "a missing character carries no shortcut, whatever the modifiers claim")
        expect(
            MenuSearchShortcut.commandEquivalent(character: "E", modifiers: 24) == nil,
            "higher bits mark keys outside ⌘ chords, which have no glyph to show")
        expect(
            MenuSearchShortcut(
                character: "x", hasCommand: true, hasShift: true, hasOption: true,
                hasControl: true
            ).keycaps == ["⌃", "⌥", "⇧", "⌘", "X"],
            "keycaps split the chord in menu order for the row's chips")
        expect(
            MenuSearchShortcut(
                character: "s", hasCommand: false, hasShift: false, hasOption: false,
                hasControl: false
            ).keycaps.isEmpty,
            "a chord with no glyph carries no chips")
        let upArrow = MenuSearchShortcut.commandEquivalent(character: "\u{F700}", modifiers: 0b100)
        expect(
            upArrow?.displayString == "⌃⌘↑",
            "a PUA arrow scalar renders as a visible glyph, never tofu")
        expect(
            upArrow?.keycaps == ["⌃", "⌘", "↑"],
            "the chips carry the same mapped glyph")
    }

    static func snapshotDuplicates() {
        let bar: [MenuTreeNode] = [
            tree(
                "",
                children: [
                    tree("File", children: [tree("Eject")]),
                    tree("Special", children: [tree("Eject")]),
                    tree("File", children: [tree("Eject")])
                ])
        ]
        let items = MenuSnapshotPolicy.collect(bar).map(\.displayPath)
        expect(
            items == ["File > Eject", "Special > Eject"],
            "an exact repeated path keeps its first row only: \(items)")
    }

    static func waitForReady(_ session: MenuSearchSession) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while session.state != .ready, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    static func sessionWalk() async {
        let probe = WalkProbe()
        let session = MenuSearchSession(walkOperation: probe.walk)
        session.startWalk(target: .searchable(name: "TextEdit"), pid: 42)
        expect(session.state == .reading, "the walk starts reading with empty rows")
        expect(session.filtered.isEmpty, "nothing publishes before the walk lands")
        await waitForReady(session)
        expect(
            session.snapshot.map(\.title) == ["Walk 1"],
            "the landed walk publishes its snapshot")
        expect(
            session.filtered.map(\.title) == ["Walk 1"],
            "publishing filters the pending query, here the whole snapshot")
        let calls = await probe.calls
        expect(calls == 1, "one show walks once")
    }

    static func sessionWalkSuperseded() async {
        let probe = WalkProbe(firstSlow: true)
        let session = MenuSearchSession(walkOperation: probe.walk)
        session.startWalk(target: .searchable(name: "A"), pid: 1)
        session.startWalk(target: .searchable(name: "B"), pid: 2)
        await waitForReady(session)
        expect(
            session.target == .searchable(name: "B")
                && session.snapshot.map(\.title) == ["Walk 2"],
            "a superseded walk never publishes")
    }
}
