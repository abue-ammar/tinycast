// Standalone contract tests for the pure window-layout model, geometry, plan and store.
import CoreGraphics
import Foundation

@main
@MainActor
struct WindowLayoutTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expectThrows(
        _ expected: WindowLayoutValidationError, _ message: String, _ body: () throws -> Void
    ) {
        do {
            try body()
            expect(false, message)
        } catch let error as WindowLayoutValidationError {
            expect(error == expected, message)
        } catch {
            expect(false, message)
        }
    }

    static func expectRect(_ actual: CGRect?, _ expected: CGRect, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print(
                "FAIL: \(message) — got \(actual.map(String.init(describing:)) ?? "nil"), expected \(expected)"
            )
        }
    }

    // MARK: - Fixtures

    /// The reference display: at the AX origin, evenly divisible by halves and thirds.
    static let mainScreen = WindowPlacementEngine.Screen(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    /// A second display to the right, differently sized, with a menu-bar inset.
    static let rightScreen = WindowPlacementEngine.Screen(
        id: 2, frame: CGRect(x: 1440, y: -300, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1440, y: -275, width: 2560, height: 1415))

    /// A display entirely in negative coordinates: the case a stray absolute coordinate breaks.
    static let leftScreen = WindowPlacementEngine.Screen(
        id: 3, frame: CGRect(x: -1920, y: -100, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: -75, width: 1920, height: 1055))

    static func display(_ index: Int) -> WindowLayoutDisplay {
        WindowLayoutDisplay(uuid: "UUID-\(index)", name: "Display \(index)")
    }

    static func target(_ screen: WindowPlacementEngine.Screen, _ index: Int) -> WindowLayoutScreen {
        WindowLayoutScreen(display: display(index), screen: screen)
    }

    static func entry(
        bundleID: String = "com.example.app", display index: Int = 1, width: CGFloat = 1,
        height: CGFloat = 1, anchor: WindowLayoutAnchor = .center, offset: CGPoint = .zero,
        argument: String? = nil
    ) -> WindowLayoutEntry {
        WindowLayoutEntry(
            bundleID: bundleID, argument: argument, display: display(index), widthFraction: width,
            heightFraction: height, anchor: anchor, offset: offset)
    }

    static func layout(
        _ name: String = "Office", entries: [WindowLayoutEntry], gap: Bool = false
    ) -> WindowLayout {
        WindowLayout(name: name, usesPreferredGap: gap, entries: entries)
    }

    static func main() {
        recordIdentity()
        anchorGrid()
        resolverExactFrames()
        resolverOnOffsetDisplays()
        resolverOffsets()
        resolverDegenerateInput()
        gapArithmetic()
        describeExactAnchors()
        roundTrip()
        nearestAnchorChoice()
        planSkipsAbsentDisplays()
        planBindsWindows()
        planShape()
        codableRoundTrip()
        storeCRUD()
        storeValidation()
        storeSanitization()
        storePersistence()
        fuzzSweep()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Record

    static func recordIdentity() {
        let value = layout(entries: [entry()])
        expect(value.entryID.hasPrefix("window-layout:"), "an entry id is namespaced")
        expect(
            WindowLayout.id(fromEntryID: value.entryID) == value.id, "the entry id round-trips")
        expect(
            WindowLayout.id(fromEntryID: "quicklink:\(value.id)") == nil,
            "another feature's entry id is not claimed")
        expect(
            WindowLayout.id(fromEntryID: "window-layout:not-a-uuid") == nil,
            "a malformed entry id is not claimed")
        expect(value.symbol == WindowLayout.sfSymbol, "an iconless layout uses the shared glyph")
        var custom = value
        custom.iconSymbol = "star"
        expect(custom.symbol == "star", "a chosen glyph wins")

        expect(layout(entries: [entry()]).summary == "1 window", "one entry reads singular")
        let two = layout(entries: [entry(display: 1), entry(display: 2)])
        expect(two.summary == "2 windows · 2 displays", "two displays are named")
        let same = layout(entries: [entry(display: 1), entry(display: 1)])
        expect(same.summary == "2 windows", "one display is not worth naming")

        let a = WindowLayout(name: "alpha", entries: [entry()])
        let b = WindowLayout(name: "Beta", entries: [entry()])
        expect(WindowLayout.precedes(a, b), "ordering is case-insensitive by name")
        expect(!WindowLayout.precedes(b, a), "ordering is antisymmetric")
    }

    static func anchorGrid() {
        expect(WindowLayoutAnchor.allCases.count == 9, "the grid has nine positions")
        expect(
            Set(WindowLayoutAnchor.allCases.map(\.rawValue)).count == 9,
            "every anchor has a distinct persisted spelling")
        expect(
            Set(WindowLayoutAnchor.allCases.map(\.title)).count == 9,
            "every anchor has a distinct label")

        // The AX-orientation lock: `.min` is the TOP, since +Y points down here.
        let box = mainScreen.visibleFrame
        let size = CGSize(width: 400, height: 300)
        expect(
            WindowLayoutAnchor.topLeft.placement.place(size, in: box).minY == box.minY,
            "top-left sits at the top edge, not the bottom")
        expect(
            WindowLayoutAnchor.topLeft.placement.place(size, in: box).minX == box.minX,
            "top-left sits at the leading edge")
        expect(
            WindowLayoutAnchor.bottomRight.placement.place(size, in: box).maxY == box.maxY,
            "bottom-right sits at the bottom edge")
        expect(
            WindowLayoutAnchor.center.placement.place(size, in: box).midX == box.midX,
            "center is centred horizontally")

        for anchor in WindowLayoutAnchor.allCases {
            let placement = anchor.placement
            expect(
                WindowLayoutAnchor.named(
                    horizontal: placement.horizontal, vertical: placement.vertical) == anchor,
                "\(anchor.rawValue) round-trips through its axis pair")
        }
    }

    // MARK: - Resolver

    static func resolverExactFrames() {
        expectRect(
            WindowLayoutGeometry.resolve(
                entry(width: 0.5, height: 1, anchor: .topLeft), on: mainScreen, gap: 0),
            CGRect(x: 0, y: 0, width: 720, height: 900), "50% × 100% top-left is the left half")
        expectRect(
            WindowLayoutGeometry.resolve(
                entry(width: 0.5, height: 1, anchor: .topRight), on: mainScreen, gap: 0),
            CGRect(x: 720, y: 0, width: 720, height: 900), "50% × 100% top-right is the right half")
        expectRect(
            WindowLayoutGeometry.resolve(entry(), on: mainScreen, gap: 0),
            mainScreen.visibleFrame, "100% × 100% is the whole visible frame")
        expectRect(
            WindowLayoutGeometry.resolve(
                entry(width: 0.5, height: 0.5, anchor: .center), on: mainScreen, gap: 0),
            CGRect(x: 360, y: 225, width: 720, height: 450), "50% × 50% centred is the middle")
        expectRect(
            WindowLayoutGeometry.resolve(
                entry(width: 0.5, height: 0.5, anchor: .bottomRight), on: mainScreen, gap: 0),
            CGRect(x: 720, y: 450, width: 720, height: 450), "bottom-right fills the last quarter")
    }

    static func resolverOnOffsetDisplays() {
        for screen in [mainScreen, rightScreen, leftScreen] {
            for anchor in WindowLayoutAnchor.allCases {
                let item = entry(width: 0.5, height: 0.5, anchor: anchor)
                guard let frame = WindowLayoutGeometry.resolve(item, on: screen, gap: 0) else {
                    expect(false, "an entry resolves on display \(screen.id)")
                    continue
                }
                expect(
                    screen.visibleFrame.contains(frame),
                    "\(anchor.rawValue) stays inside display \(screen.id)")
                expect(
                    frame.width == (screen.visibleFrame.width * 0.5).rounded(),
                    "a fraction yields the same width wherever the display sits")
            }
        }
    }

    static func resolverOffsets() {
        expectRect(
            WindowLayoutGeometry.resolve(
                entry(width: 0.5, height: 0.5, anchor: .topLeft, offset: CGPoint(x: 40, y: 40)),
                on: mainScreen, gap: 0),
            CGRect(x: 40, y: 40, width: 720, height: 450), "an offset moves by exactly that")

        // A nudge that would leave the display clamps, and the clamp never resizes.
        let pushed = WindowLayoutGeometry.resolve(
            entry(width: 0.5, height: 0.5, anchor: .bottomRight, offset: CGPoint(x: 999, y: 999)),
            on: mainScreen, gap: 0)
        expectRect(
            pushed, CGRect(x: 720, y: 450, width: 720, height: 450),
            "an offset off the display clamps back, keeping its size")

        expectRect(
            WindowLayoutGeometry.resolve(
                entry(width: 0.5, height: 0.5, anchor: .bottomRight, offset: CGPoint(x: -20, y: -20)),
                on: mainScreen, gap: 0),
            CGRect(x: 700, y: 430, width: 720, height: 450), "a negative offset moves inward")
    }

    static func resolverDegenerateInput() {
        let degenerate: [(CGFloat, String)] = [
            (0, "zero"), (-1, "negative"), (2, "over one"), (.nan, "NaN"),
            (.infinity, "infinite")
        ]
        for (value, label) in degenerate {
            guard
                let frame = WindowLayoutGeometry.resolve(
                    entry(width: value, height: value), on: mainScreen, gap: 0)
            else {
                expect(false, "a \(label) fraction still resolves")
                continue
            }
            expect(frame.width >= 1 && frame.height >= 1, "a \(label) fraction keeps some area")
            expect(
                frame.width.isFinite && frame.height.isFinite,
                "a \(label) fraction stays finite")
            expect(mainScreen.visibleFrame.contains(frame), "a \(label) fraction stays on screen")
        }

        for (value, label) in [(CGFloat.nan, "NaN"), (.infinity, "infinite")] {
            let frame = WindowLayoutGeometry.resolve(
                entry(width: 0.5, height: 0.5, offset: CGPoint(x: value, y: value)),
                on: mainScreen, gap: 0)
            expectRect(
                frame, CGRect(x: 360, y: 225, width: 720, height: 450),
                "a \(label) offset resolves as no offset")
        }

        let empty = WindowPlacementEngine.Screen(id: 9, frame: .zero, visibleFrame: .zero)
        expect(
            WindowLayoutGeometry.resolve(entry(), on: empty, gap: 0) == nil,
            "a display with no visible frame resolves to nothing")
    }

    static func gapArithmetic() {
        expectRect(
            WindowLayoutGeometry.resolve(entry(), on: mainScreen, gap: 8),
            CGRect(x: 8, y: 8, width: 1424, height: 884), "a gap insets the box on every side")
        expect(
            WindowLayoutGeometry.box(mainScreen, gap: 0) == mainScreen.visibleFrame,
            "no gap leaves the visible frame alone")
        for gap in [CGFloat(0), -1, .nan] {
            expect(
                WindowLayoutGeometry.box(mainScreen, gap: gap) == mainScreen.visibleFrame,
                "a \(gap) gap behaves as no gap")
        }
        // Capped at a tenth of the shorter side, so a huge gap can't produce a zero-size box.
        let huge = WindowLayoutGeometry.box(mainScreen, gap: 100_000)
        expect(huge.width > 0 && huge.height > 0, "an absurd gap still leaves a usable box")
    }

    // MARK: - Capture

    static func describeExactAnchors() {
        let box = mainScreen.visibleFrame
        let size = CGSize(width: 400, height: 300)
        for anchor in WindowLayoutAnchor.allCases {
            let frame = anchor.placement.place(size, in: box)
            let capture = WindowLayoutGeometry.describe(frame, on: mainScreen, gap: 0)
            expect(capture.anchor == anchor, "a frame at \(anchor.rawValue) describes as it")
            expect(capture.offset == .zero, "a frame exactly at an anchor needs no offset")
            expect(
                capture.widthFraction == size.width / box.width,
                "the width fraction is the exact ratio")
        }
    }

    static func roundTrip() {
        var checked = 0
        var problems: [String] = []
        for screen in [mainScreen, rightScreen, leftScreen] {
            for gap in [CGFloat(0), 8, 64] {
                let box = WindowLayoutGeometry.box(screen, gap: gap)
                var frames: [CGRect] = [box, CGRect(origin: box.origin, size: CGSize(width: 1, height: 1))]
                for anchor in WindowLayoutAnchor.allCases {
                    frames.append(
                        anchor.placement.place(CGSize(width: 400, height: 300), in: box))
                }
                for dx in stride(from: CGFloat(0), through: 1, by: 0.25) {
                    for dy in stride(from: CGFloat(0), through: 1, by: 0.25) {
                        let size = CGSize(width: 517, height: 331)
                        frames.append(
                            CGRect(
                                x: (box.minX + (box.width - size.width) * dx).rounded(),
                                y: (box.minY + (box.height - size.height) * dy).rounded(),
                                width: size.width, height: size.height))
                    }
                }
                // Whole points only: `resolve` rounds its four edges, so a half-point frame
                // round-trips to its rounded self — pinned separately below.
                for frame in frames.map(WindowPlacementEngine.rounded) where box.contains(frame) {
                    checked += 1
                    let capture = WindowLayoutGeometry.describe(frame, on: screen, gap: gap)
                    var item = entry(
                        width: capture.widthFraction, height: capture.heightFraction,
                        anchor: capture.anchor, offset: capture.offset)
                    item.display = display(screen.id)
                    let resolved = WindowLayoutGeometry.resolve(item, on: screen, gap: gap)
                    if resolved != frame {
                        problems.append(
                            "\(frame) on \(screen.id) gap \(gap) → \(resolved.map(String.init(describing:)) ?? "nil")"
                        )
                    }
                }
            }
        }
        expect(checked > 200, "the round trip covered a meaningful number of frames")
        expect(problems.isEmpty, "resolve(describe(frame)) == frame for every whole-point frame")
        for problem in problems.prefix(5) { print("      \(problem)") }

        // A window can report a fractional frame; it comes back snapped, never a point out.
        let half = CGRect(x: 100.5, y: 200.5, width: 400, height: 300)
        let capture = WindowLayoutGeometry.describe(half, on: mainScreen, gap: 0)
        var item = entry(
            width: capture.widthFraction, height: capture.heightFraction, anchor: capture.anchor,
            offset: capture.offset)
        item.display = display(mainScreen.id)
        expectRect(
            WindowLayoutGeometry.resolve(item, on: mainScreen, gap: 0),
            WindowPlacementEngine.rounded(half),
            "a fractional frame round-trips to its rounded self")
    }

    static func nearestAnchorChoice() {
        let box = mainScreen.visibleFrame
        let size = CGSize(width: 400, height: 300)

        let nudged = CGRect(x: box.minX + 1, y: box.minY, width: size.width, height: size.height)
        let capture = WindowLayoutGeometry.describe(nudged, on: mainScreen, gap: 0)
        expect(capture.anchor == .topLeft, "one point off an edge stays that edge, not the centre")
        expect(capture.offset == CGPoint(x: 1, y: 0), "the residual becomes the offset")

        let right = CGRect(
            x: box.maxX - size.width, y: box.midY - size.height / 2, width: size.width,
            height: size.height)
        expect(
            WindowLayoutGeometry.describe(right, on: mainScreen, gap: 0).anchor == .right,
            "a window against the trailing edge describes as trailing")

        // Per-axis independence: moving vertically must never change the horizontal choice.
        var independent = true
        for dy in stride(from: CGFloat(0), through: 600, by: 50) {
            let frame = CGRect(x: box.minX, y: box.minY + dy, width: size.width, height: size.height)
            let horizontal = WindowLayoutGeometry.describe(frame, on: mainScreen, gap: 0)
                .anchor.placement.horizontal
            if horizontal != .min { independent = false }
        }
        expect(independent, "each axis picks its anchor from its own axis alone")
    }

    // MARK: - Plan

    static func planSkipsAbsentDisplays() {
        let value = layout(entries: [entry(display: 1), entry(display: 2)])
        let plan = WindowLayoutPlan.make(
            layout: value, screens: [target(mainScreen, 1)], windows: [], preferredGap: 0)
        expect(plan.placements.count == 1, "the connected display still places")
        expect(plan.skipped.count == 1, "the absent display skips exactly one entry")
        expect(
            plan.skipped.first?.reason == .displayDisconnected(name: "Display 2"),
            "the skip names the stored display")
        expect(plan.skippedSummary == "1 display not connected", "the summary names the cause")

        let none = WindowLayoutPlan.make(
            layout: value, screens: [], windows: [], preferredGap: 0)
        expect(none.placements.isEmpty, "no display places nothing")
        expect(none.skippedSummary == "2 displays not connected", "both are counted")
    }

    static func planBindsWindows() {
        let value = layout(
            entries: [
                entry(width: 0.5, height: 1, anchor: .topLeft),
                entry(width: 0.5, height: 1, anchor: .topRight)
            ])
        let left = WindowLayoutWindow(
            handle: 1, bundleID: "com.example.app",
            frame: CGRect(x: 0, y: 0, width: 720, height: 900))
        let right = WindowLayoutWindow(
            handle: 2, bundleID: "com.example.app",
            frame: CGRect(x: 720, y: 0, width: 720, height: 900))

        let plan = WindowLayoutPlan.make(
            layout: value, screens: [target(mainScreen, 1)], windows: [left, right],
            preferredGap: 0)
        expect(plan.placements.count == 2, "two entries bind two windows")
        expect(
            plan.placements[0].source == .existing(handle: 1)
                && plan.placements[1].source == .existing(handle: 2),
            "the nearest window wins, so an already-correct desktop is a no-op")

        let shuffled = WindowLayoutPlan.make(
            layout: value, screens: [target(mainScreen, 1)], windows: [right, left],
            preferredGap: 0)
        expect(shuffled == plan, "shuffling the inventory cannot change the plan")

        let cold = WindowLayoutPlan.make(
            layout: value, screens: [target(mainScreen, 1)], windows: [], preferredGap: 0)
        expect(cold.opens.count == 1, "one open is issued for an app that isn't running")
        expect(
            cold.skipped.first?.reason == .duplicateTarget,
            "a second window of an unlaunched app has nothing to bind to")

        let partial = WindowLayoutPlan.make(
            layout: value, screens: [target(mainScreen, 1)], windows: [left], preferredGap: 0)
        expect(
            partial.placements.map(\.source) == [.existing(handle: 1), .launch],
            "one existing window binds and the shortfall launches")

        let arguments = layout(
            entries: [
                entry(argument: "~/Documents"), entry(argument: "~/Downloads"),
                entry(argument: "~/Documents")
            ])
        let opened = WindowLayoutPlan.make(
            layout: arguments, screens: [target(mainScreen, 1)], windows: [left], preferredGap: 0)
        expect(opened.opens.count == 2, "each distinct argument opens its own window")
        expect(
            opened.skipped.count == 1 && opened.skipped[0].reason == .duplicateTarget,
            "the same argument twice is one window, not two")
    }

    static func planShape() {
        let value = layout(entries: [entry(display: 1)], gap: true)
        let plan = WindowLayoutPlan.make(
            layout: value, screens: [target(mainScreen, 1)], windows: [], preferredGap: 16)
        expect(plan.placements.first?.screenID == mainScreen.id, "a placement names its display")
        expect(
            plan.placements.first?.canvas == WindowLayoutGeometry.box(mainScreen, gap: 16),
            "a placement carries the box the runner re-clamps into")

        let gapless = layout(entries: [entry(display: 1)], gap: false)
        let ignored = WindowLayoutPlan.make(
            layout: gapless, screens: [target(mainScreen, 1)], windows: [], preferredGap: 16)
        expect(
            ignored.placements.first?.frame == mainScreen.visibleFrame,
            "opting out of the gap ignores the preferred one entirely")

        let mixedCase = WindowLayout(
            name: "Office",
            entries: [
                WindowLayoutEntry(
                    bundleID: "com.example.app",
                    display: WindowLayoutDisplay(uuid: "uuid-1", name: "Display 1"))
            ])
        let matched = WindowLayoutPlan.make(
            layout: mixedCase, screens: [target(mainScreen, 1)], windows: [], preferredGap: 0)
        expect(matched.placements.count == 1, "display matching ignores case")
    }

    // MARK: - Codable

    static func codableRoundTrip() {
        let value = WindowLayout(
            name: "Office", iconSymbol: "star", usesPreferredGap: false,
            entries: [
                entry(width: 0.25, height: 0.75, anchor: .bottomLeft, offset: CGPoint(x: -8, y: 12)),
                entry(bundleID: "com.example.other", display: 2, argument: "https://example.com")
            ])
        guard let data = try? JSONEncoder().encode(value),
            let decoded = try? JSONDecoder().decode(WindowLayout.self, from: data)
        else {
            expect(false, "a layout encodes and decodes")
            return
        }
        expect(decoded == value, "a layout round-trips through JSON unchanged")

        for anchor in WindowLayoutAnchor.allCases {
            guard let data = try? JSONEncoder().encode(anchor),
                let back = try? JSONDecoder().decode(WindowLayoutAnchor.self, from: data)
            else {
                expect(false, "\(anchor.rawValue) encodes")
                continue
            }
            expect(back == anchor, "\(anchor.rawValue) round-trips")
        }

        let minimal = """
            [{"name": "Bare", "entries": [{"bundleID": "com.example.app",
              "display": {"uuid": "UUID-1"}}]}]
            """
        guard
            let bare = try? JSONDecoder().decode(
                [WindowLayout].self, from: Data(minimal.utf8)), let first = bare.first,
            let onlyEntry = first.entries.first
        else {
            expect(false, "a minimal hand-written payload decodes")
            return
        }
        expect(first.usesPreferredGap, "an absent gap flag defaults on")
        expect(onlyEntry.widthFraction == 1 && onlyEntry.heightFraction == 1, "fractions default full")
        expect(onlyEntry.anchor == .center, "an absent anchor defaults centred")
        expect(onlyEntry.offset == .zero, "an absent offset defaults to none")
        expect(onlyEntry.display.name == "Display", "an absent display name has a fallback")
    }

    // MARK: - Store

    static func withStore(_ body: (WindowLayoutStore) -> Void) {
        let name = "tinycast-window-layout-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            expect(false, "a scratch defaults suite opens")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        body(WindowLayoutStore(defaults: defaults))
    }

    static func storeCRUD() {
        withStore { store in
            guard let office = try? store.add(layout("Office", entries: [entry()])) else {
                return expect(false, "adding a layout succeeds")
            }
            expect(store.layouts.map(\.name) == ["Office"], "an added layout is listed")
            expect(store.layout(id: office.id)?.name == "Office", "a layout is found by id")
            expect(
                store.layout(entryID: office.entryID)?.id == office.id, "the entry id resolves")

            var renamed = office
            renamed.name = "Desk"
            try? store.update(renamed)
            expect(store.layouts.map(\.name) == ["Desk"], "an update lands")
            expect(store.layout(id: office.id) != nil, "an update keeps the identity")

            guard let copy = try? store.duplicate(id: office.id) else {
                return expect(false, "duplicating succeeds")
            }
            expect(copy.id != office.id, "a duplicate is a new identity")
            expect(copy.name == "Desk Copy", "a duplicate names itself")
            expect(
                copy.entries.first?.id != office.entries.first?.id,
                "a duplicate's entries take fresh identities")

            expect(store.remove(id: copy.id)?.id == copy.id, "removing returns the record")
            expect(store.layouts.count == 1, "removing takes it out of the library")
            expect(store.remove(id: UUID()) == nil, "removing an unknown id is a no-op")

            var changes = 0
            store.onChange = { _ in changes += 1 }
            try? store.update(store.layouts[0])
            expect(changes == 0, "committing an unchanged record notifies nobody")
        }
    }

    static func storeValidation() {
        withStore { store in
            for (name, label) in [("", "an empty"), ("   ", "a whitespace-only")] {
                expectThrows(.emptyName, "\(label) name is rejected") {
                    _ = try store.add(layout(name, entries: [entry()]))
                }
            }
            expectThrows(.invalidCharacter, "a null character is rejected") {
                _ = try store.add(layout("Bad\0Name", entries: [entry()]))
            }
            expectThrows(.noEntries, "a layout with no entries is rejected") {
                _ = try store.add(layout("Empty", entries: []))
            }
            _ = try? store.add(layout("Office", entries: [entry()]))
            expectThrows(.duplicateName, "a duplicate name is rejected") {
                _ = try store.add(layout("OFFICE", entries: [entry()]))
            }
        }
    }

    static func storeSanitization() {
        let shared = UUID()
        let hostile = [
            WindowLayout(id: shared, name: "Office", entries: [entry()]),
            WindowLayout(id: shared, name: "Second", entries: [entry()]),
            WindowLayout(name: "office", entries: [entry()]),
            WindowLayout(name: "  ", entries: [entry()]),
            WindowLayout(name: "Empty", entries: []),
            WindowLayout(
                name: "Clamped",
                entries: [
                    entry(width: 9, height: -3, offset: CGPoint(x: .nan, y: 1e12)),
                    WindowLayoutEntry(
                        bundleID: "  ", display: display(1))
                ])
        ]
        withStore { store in
            let kept = store.replace(with: hostile)
            expect(kept == 2, "only the sound records survive")
            expect(
                store.layouts.map(\.name) == ["Clamped", "Office"],
                "survivors are the first of each identity, in display order")
            guard let clamped = store.layouts.first(where: { $0.name == "Clamped" }),
                let onlyEntry = clamped.entries.first
            else {
                return expect(false, "the clamped layout kept its usable entry")
            }
            expect(clamped.entries.count == 1, "an entry with no bundle id is dropped")
            expect(onlyEntry.widthFraction == 1, "an over-range fraction clamps to full")
            expect(onlyEntry.heightFraction == 0, "a negative fraction clamps to zero")
            expect(onlyEntry.offset.x == 0, "a non-finite offset becomes none")
            expect(
                onlyEntry.offset.y == WindowLayoutEntry.offsetLimit,
                "an absurd offset clamps to the limit")
        }
    }

    static func storePersistence() {
        let name = "tinycast-window-layout-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            return expect(false, "a scratch defaults suite opens")
        }
        defer { defaults.removePersistentDomain(forName: name) }

        var stored: WindowLayout?
        do {
            let store = WindowLayoutStore(defaults: defaults)
            stored = try? store.add(
                WindowLayout(
                    name: "Office", iconSymbol: "star", usesPreferredGap: false,
                    entries: [entry(width: 0.5, height: 0.25, anchor: .bottomRight)]))
        }
        let reopened = WindowLayoutStore(defaults: defaults)
        expect(reopened.layouts.count == 1, "a reopened store finds its library")
        expect(reopened.layouts.first == stored, "every field survives the round trip")
    }

    // MARK: - Fuzz

    static func fuzzSweep() {
        let screens = [mainScreen, rightScreen, leftScreen]
        let fractions: [CGFloat] = [0, 0.05, 0.5, 1, 2, -1, .nan, .infinity]
        let offsets: [CGFloat] = [0, 40, -40, 1e9, .nan]
        let gaps: [CGFloat] = [0, 2, 64, -1, .nan, 1e6]
        var checked = 0
        var problems: [String] = []

        for screen in screens {
            for gap in gaps {
                let box = WindowLayoutGeometry.box(screen, gap: gap)
                for anchor in WindowLayoutAnchor.allCases {
                    for fraction in fractions {
                        for offset in offsets {
                            var item = entry(
                                width: fraction, height: fraction, anchor: anchor,
                                offset: CGPoint(x: offset, y: offset))
                            item.display = display(screen.id)
                            guard
                                let frame = WindowLayoutGeometry.resolve(
                                    item, on: screen, gap: gap)
                            else {
                                problems.append("nil for \(anchor.rawValue) \(fraction) \(offset)")
                                continue
                            }
                            checked += 1
                            let label = "\(screen.id)/\(gap)/\(anchor.rawValue)/\(fraction)/\(offset)"
                            if !frame.minX.isFinite || !frame.minY.isFinite
                                || !frame.width.isFinite || !frame.height.isFinite
                            {
                                problems.append("non-finite: \(label)")
                            }
                            if frame.width < 1 || frame.height < 1 {
                                problems.append("collapsed: \(label)")
                            }
                            if !box.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                                problems.append("outside the box: \(label)")
                            }
                            if WindowLayoutGeometry.resolve(item, on: screen, gap: gap) != frame {
                                problems.append("non-deterministic: \(label)")
                            }
                            // Describing what we just produced and resolving again must not drift.
                            let capture = WindowLayoutGeometry.describe(frame, on: screen, gap: gap)
                            var again = item
                            again.widthFraction = capture.widthFraction
                            again.heightFraction = capture.heightFraction
                            again.anchor = capture.anchor
                            again.offset = capture.offset
                            if WindowLayoutGeometry.resolve(again, on: screen, gap: gap) != frame {
                                problems.append("drifts on describe/resolve: \(label)")
                            }
                            if capture.widthFraction < 0 || capture.widthFraction > 1
                                || !capture.offset.x.isFinite
                            {
                                problems.append("capture out of range: \(label)")
                            }
                        }
                    }
                }
            }
        }
        expect(checked > 1000, "the fuzz sweep exercised a meaningful number of entries")
        expect(problems.isEmpty, "fuzz sweep found no violations")
        for problem in problems.prefix(10) { print("      \(problem)") }
    }
}
