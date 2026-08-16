// Standalone contract tests for the pure window-management geometry and action memory.
import CoreGraphics
import Foundation

@main
@MainActor
struct WindowCommandTests {
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

    static func expectRect(_ actual: CGRect, _ expected: CGRect, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), expected \(expected)")
        }
    }

    // MARK: - Fixtures

    /// The reference display: origin at the AX origin, evenly divisible by halves and thirds.
    static let mainScreen = WindowLayout.Screen(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    static func screens(_ list: WindowLayout.Screen...) -> [WindowLayout.Screen] { list }

    static func frame(
        _ command: WindowCommand.ID, on screen: WindowLayout.Screen = mainScreen,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400), gap: CGFloat = 0,
        step: Int = 0, restore: CGRect? = nil, lastTile: WindowCommand.ID? = nil,
        allScreens: [WindowLayout.Screen]? = nil
    ) -> CGRect? {
        WindowLayout.placement(
            for: WindowLayout.Input(
                command: command, windowFrame: window, screens: allScreens ?? [screen], gap: gap,
                step: step, restoreFrame: restore, lastTileCommand: lastTile)
        )?.frame
    }

    static func main() {
        testCatalog()
        testConventionLock()
        testTiling()
        testNonDivisible()
        testOffOriginScreens()
        testGaps()
        testSizing()
        testLargerSmaller()
        testNudges()
        testDisplays()
        testRestore()
        testMemory()
        testFuzz()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Catalog

    static func testCatalog() {
        let commands = WindowCommandCatalog.all
        expect(commands.count == 30, "catalog contains all 30 agreed commands")
        expect(commands.map(\.id) == WindowCommand.ID.allCases, "catalog covers every ID once")
        expect(
            Set(commands.map { $0.name.lowercased() }).count == commands.count, "names are unique")
        expect(commands.allSatisfy { !$0.name.isEmpty }, "names are non-empty")
        expect(commands.allSatisfy { !$0.sfSymbol.isEmpty }, "symbols are non-empty")

        for command in commands {
            expect(
                WindowCommandCatalog.command(forEntryID: command.entryID) == command,
                "\(command.id.rawValue) round-trips through its entry ID")
            expect(
                WindowCommandCatalog.command(id: command.id) == command,
                "\(command.id.rawValue) round-trips through its ID")
            expect(
                command.entryID.hasPrefix("window-command:"),
                "\(command.id.rawValue) is namespaced")
        }
        expect(
            WindowCommandCatalog.command(forEntryID: "window-command:unknown") == nil,
            "unknown entry IDs are rejected")
        expect(
            WindowCommandCatalog.command(forEntryID: "system-action:sleep") == nil,
            "system-action entry IDs are not claimed")

        let cycling = Set(commands.filter(\.cyclesOnRepeat).map(\.id))
        expect(
            cycling == [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
            "only the four halves cycle on repeat")
        let moveOnly = Set(commands.filter { !$0.resizes }.map(\.id))
        expect(
            moveOnly == [.moveLeft, .moveRight, .moveUp, .moveDown],
            "only the four nudges leave the size alone")
        expect(
            Set(commands.filter { $0.kind == .fullscreen }.map(\.id)) == [.toggleFullscreen],
            "only Toggle Fullscreen is a fullscreen command")
        expect(
            Set(commands.filter { $0.kind == .restore }.map(\.id)) == [.restore],
            "only Restore is a restore command")

        // Grouping drives the Settings list; every command must land in exactly one group.
        let grouped = WindowCommandCatalog.grouped()
        expect(
            grouped.flatMap(\.commands).count == commands.count, "grouping loses no command")
        expect(
            grouped.map(\.group) == WindowCommand.Group.allCases,
            "every group is represented, in declaration order")
        expect(grouped.first { $0.group == .halves }?.commands.count == 4, "four halves")
        expect(grouped.first { $0.group == .quarters }?.commands.count == 4, "four quarters")
        expect(grouped.first { $0.group == .thirds }?.commands.count == 5, "five thirds")
        expect(grouped.first { $0.group == .sizing }?.commands.count == 10, "ten sizing commands")
        expect(grouped.first { $0.group == .moving }?.commands.count == 6, "six moving commands")

        expect(
            WindowLayout.isTileCommand(.leftHalf) && WindowLayout.isTileCommand(.centerHalf),
            "halves and center half are tiles")
        expect(
            !WindowLayout.isTileCommand(.maximize) && !WindowLayout.isTileCommand(.moveLeft),
            "free-floating commands are not tiles")

        // Fullscreen has no geometry at all — the mover branches before ever asking for a placement.
        expect(frame(.toggleFullscreen) == nil, "Toggle Fullscreen produces no placement")
    }

    // MARK: - Convention lock

    static func testConventionLock() {
        // AX space: +Y points down, so the top half starts at the visible frame's minY. This single
        // assertion is what stops a bottom-left convention being reintroduced by accident.
        expect(
            frame(.topHalf)?.minY == mainScreen.visibleFrame.minY,
            "top half is anchored at visibleFrame.minY (AX space, +Y down)")
        expect(
            frame(.bottomHalf)?.maxY == mainScreen.visibleFrame.maxY,
            "bottom half is anchored at visibleFrame.maxY")
        expect(
            frame(.topLeftQuarter)?.minY == mainScreen.visibleFrame.minY,
            "top left quarter sits at the top")
    }

    // MARK: - Tiling

    static func testTiling() {
        expectRect(frame(.leftHalf)!, CGRect(x: 0, y: 0, width: 720, height: 900), "left half")
        expectRect(frame(.rightHalf)!, CGRect(x: 720, y: 0, width: 720, height: 900), "right half")
        expectRect(frame(.topHalf)!, CGRect(x: 0, y: 0, width: 1440, height: 450), "top half")
        expectRect(
            frame(.bottomHalf)!, CGRect(x: 0, y: 450, width: 1440, height: 450), "bottom half")

        expectRect(
            frame(.topLeftQuarter)!, CGRect(x: 0, y: 0, width: 720, height: 450), "top left quarter")
        expectRect(
            frame(.topRightQuarter)!, CGRect(x: 720, y: 0, width: 720, height: 450),
            "top right quarter")
        expectRect(
            frame(.bottomLeftQuarter)!, CGRect(x: 0, y: 450, width: 720, height: 450),
            "bottom left quarter")
        expectRect(
            frame(.bottomRightQuarter)!, CGRect(x: 720, y: 450, width: 720, height: 450),
            "bottom right quarter")

        let quarters = [
            frame(.topLeftQuarter)!, frame(.topRightQuarter)!, frame(.bottomLeftQuarter)!,
            frame(.bottomRightQuarter)!
        ]
        expect(
            quarters.reduce(CGRect.null) { $0.union($1) } == mainScreen.visibleFrame,
            "the four quarters union to the visible frame")
        var overlapping = false
        for i in quarters.indices {
            for j in quarters.indices where j > i {
                if !quarters[i].intersection(quarters[j]).isEmpty { overlapping = true }
            }
        }
        expect(!overlapping, "quarters never overlap")

        expectRect(frame(.firstThird)!, CGRect(x: 0, y: 0, width: 480, height: 900), "first third")
        expectRect(
            frame(.centerThird)!, CGRect(x: 480, y: 0, width: 480, height: 900), "center third")
        expectRect(frame(.lastThird)!, CGRect(x: 960, y: 0, width: 480, height: 900), "last third")
        expectRect(
            frame(.firstTwoThirds)!, CGRect(x: 0, y: 0, width: 960, height: 900), "first two thirds")
        expectRect(
            frame(.lastTwoThirds)!, CGRect(x: 480, y: 0, width: 960, height: 900), "last two thirds")

        expect(
            frame(.firstThird)!.union(frame(.lastTwoThirds)!) == mainScreen.visibleFrame,
            "first third and last two thirds partition the screen")
        expect(
            frame(.firstTwoThirds)!.union(frame(.lastThird)!) == mainScreen.visibleFrame,
            "first two thirds and last third partition the screen")

        // Cycling: halves only, ½ → ⅓ → ⅔, wrapping.
        expectRect(frame(.leftHalf, step: 1)!, frame(.firstThird)!, "left half step 1 is a third")
        expectRect(
            frame(.leftHalf, step: 2)!, frame(.firstTwoThirds)!, "left half step 2 is two thirds")
        expectRect(frame(.leftHalf, step: 3)!, frame(.leftHalf)!, "left half step 3 wraps to the half")
        expectRect(frame(.rightHalf, step: 1)!, frame(.lastThird)!, "right half step 1 is a third")
        expectRect(
            frame(.rightHalf, step: 2)!, frame(.lastTwoThirds)!, "right half step 2 is two thirds")
        expectRect(
            frame(.topHalf, step: 1)!, CGRect(x: 0, y: 0, width: 1440, height: 300),
            "top half step 1 is a vertical third")
        expectRect(
            frame(.topHalf, step: 2)!, CGRect(x: 0, y: 0, width: 1440, height: 600),
            "top half step 2 is vertical two thirds")
        expectRect(
            frame(.bottomHalf, step: 1)!, CGRect(x: 0, y: 600, width: 1440, height: 300),
            "bottom half step 1 is a vertical third")
        expectRect(
            frame(.bottomHalf, step: 2)!, CGRect(x: 0, y: 300, width: 1440, height: 600),
            "bottom half step 2 is vertical two thirds")

        // A step handed to a command that doesn't cycle must be ignored outright.
        for step in 0...5 {
            expectRect(
                frame(.firstThird, step: step)!, frame(.firstThird)!,
                "non-cycling commands ignore step \(step)")
            expectRect(
                frame(.maximize, step: step)!, frame(.maximize)!,
                "maximize ignores step \(step)")
        }
        // Negative steps can't crash or escape the cycle.
        expectRect(frame(.leftHalf, step: -1)!, frame(.firstTwoThirds)!, "negative steps normalize")
    }

    // MARK: - Non-divisible widths

    static func testNonDivisible() {
        for width in [1441, 1000, 1367] as [CGFloat] {
            let screen = WindowLayout.Screen(
                id: 9, frame: CGRect(x: 0, y: 0, width: width, height: 901),
                visibleFrame: CGRect(x: 0, y: 0, width: width, height: 901))
            let first = frame(.firstThird, on: screen)!
            let center = frame(.centerThird, on: screen)!
            let last = frame(.lastThird, on: screen)!
            expect(first.maxX == center.minX, "\(width): first/center thirds share an edge exactly")
            expect(center.maxX == last.minX, "\(width): center/last thirds share an edge exactly")
            expect(
                first.union(center).union(last) == screen.visibleFrame,
                "\(width): thirds still cover the whole screen")

            let left = frame(.leftHalf, on: screen)!
            let right = frame(.rightHalf, on: screen)!
            expect(left.maxX == right.minX, "\(width): halves share an edge exactly")
            expect(left.union(right) == screen.visibleFrame, "\(width): halves cover the screen")
            expect(abs(left.width - right.width) <= 1, "\(width): halves differ by at most a point")

            let top = frame(.topHalf, on: screen)!
            let bottom = frame(.bottomHalf, on: screen)!
            expect(top.maxY == bottom.minY, "\(width): vertical halves share an edge exactly")
        }
    }

    // MARK: - Off-origin displays

    static func testOffOriginScreens() {
        // A display up and to the right of the primary — negative Y in AX space.
        let high = WindowLayout.Screen(
            id: 2, frame: CGRect(x: 1920, y: -300, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1920, y: -300, width: 2560, height: 1440))
        expectRect(
            frame(.leftHalf, on: high, window: CGRect(x: 2000, y: 0, width: 400, height: 300))!,
            CGRect(x: 1920, y: -300, width: 1280, height: 1440), "left half on an off-origin display")
        expect(
            frame(.topHalf, on: high, window: CGRect(x: 2000, y: 0, width: 400, height: 300))!.minY
                == -300, "top half honours a negative minY")

        // A display left of and below the primary.
        let low = WindowLayout.Screen(
            id: 3, frame: CGRect(x: -1440, y: 200, width: 1440, height: 900),
            visibleFrame: CGRect(x: -1440, y: 200, width: 1440, height: 900))
        expectRect(
            frame(.rightHalf, on: low, window: CGRect(x: -1000, y: 300, width: 400, height: 300))!,
            CGRect(x: -720, y: 200, width: 720, height: 900), "right half on a negative-X display")
        expectRect(
            frame(.maximize, on: low, window: CGRect(x: -1000, y: 300, width: 400, height: 300))!,
            low.visibleFrame, "maximize on a negative-X display")

        // A visible frame smaller than the full frame (menu bar and Dock reserved).
        let reserved = WindowLayout.Screen(
            id: 4, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 800))
        expectRect(
            frame(.topHalf, on: reserved)!, CGRect(x: 0, y: 25, width: 1440, height: 400),
            "tiles respect a reserved visible frame")
        expectRect(
            frame(.maximize, on: reserved)!, reserved.visibleFrame, "maximize never covers the menu bar")
    }

    // MARK: - Gaps

    static func testGaps() {
        expectRect(
            frame(.leftHalf, gap: 10)!, CGRect(x: 10, y: 10, width: 705, height: 880),
            "left half with a 10pt gap")
        expectRect(
            frame(.rightHalf, gap: 10)!, CGRect(x: 725, y: 10, width: 705, height: 880),
            "right half with a 10pt gap")
        expect(
            frame(.leftHalf, gap: 10)!.maxX + 10 == frame(.rightHalf, gap: 10)!.minX,
            "the gutter between halves is exactly the gap")
        expect(
            frame(.topHalf, gap: 10)!.maxY + 10 == frame(.bottomHalf, gap: 10)!.minY,
            "the gutter between vertical halves is exactly the gap")

        // Every outer edge is inset by the full gap, every gutter is exactly one gap.
        let quarters = [
            frame(.topLeftQuarter, gap: 10)!, frame(.topRightQuarter, gap: 10)!,
            frame(.bottomLeftQuarter, gap: 10)!, frame(.bottomRightQuarter, gap: 10)!
        ]
        expect(quarters[0].maxX + 10 == quarters[1].minX, "quarters: vertical gutter is the gap")
        expect(quarters[0].maxY + 10 == quarters[2].minY, "quarters: horizontal gutter is the gap")
        expect(
            quarters.allSatisfy {
                $0.minX >= 10 && $0.minY >= 10 && $0.maxX <= 1430 && $0.maxY <= 890
            }, "quarters stay inset from every screen edge")

        // Thirds: two gutters, both exact.
        expect(
            frame(.firstThird, gap: 10)!.maxX + 10 == frame(.centerThird, gap: 10)!.minX,
            "thirds: first/center gutter is the gap")
        expect(
            frame(.centerThird, gap: 10)!.maxX + 10 == frame(.lastThird, gap: 10)!.minX,
            "thirds: center/last gutter is the gap")

        // An odd gap must not drift when halved and rounded.
        expect(
            frame(.leftHalf, gap: 9)!.maxX + 9 == frame(.rightHalf, gap: 9)!.minX,
            "an odd gap still produces an exact gutter")

        expectRect(
            frame(.maximize, gap: 12)!, CGRect(x: 12, y: 12, width: 1416, height: 876),
            "maximize honours the gap")

        // Degenerate gaps must never produce an unusable window.
        for gap in [-5, 0, 10_000] as [CGFloat] {
            let rect = frame(.leftHalf, gap: gap)!
            expect(rect.width > 0 && rect.height > 0, "gap \(gap) still yields a positive tile")
            expect(
                mainScreen.visibleFrame.contains(rect), "gap \(gap) keeps the tile on screen")
        }
        expectRect(frame(.leftHalf, gap: -5)!, frame(.leftHalf)!, "a negative gap reads as zero")
        // Every non-finite value reads as zero — one rule, so NaN and infinity can't behave differently.
        expectRect(frame(.leftHalf, gap: .nan)!, frame(.leftHalf)!, "a NaN gap reads as zero")
        expectRect(
            frame(.leftHalf, gap: .infinity)!, frame(.leftHalf)!, "an infinite gap reads as zero")
        // A merely oversized (but finite) gap is capped rather than zeroed.
        expectRect(
            frame(.leftHalf, gap: 10_000)!, frame(.leftHalf, gap: 90)!,
            "an oversized finite gap is capped to a tenth of the smaller dimension")
    }

    // MARK: - Sizing

    static func testSizing() {
        expectRect(frame(.maximize)!, mainScreen.visibleFrame, "maximize fills the visible frame")

        let almost = frame(.almostMaximize)!
        expectRect(almost, CGRect(x: 72, y: 45, width: 1296, height: 810), "almost maximize")
        expectRect(
            frame(.almostMaximize, window: almost)!, almost, "almost maximize is idempotent")
        expect(
            almost.midX == mainScreen.visibleFrame.midX
                && almost.midY == mainScreen.visibleFrame.midY,
            "almost maximize stays centred")

        let reasonable = frame(.reasonableSize)!
        expectRect(
            reasonable, CGRect(x: 288, y: 180, width: 864, height: 540), "reasonable size is 60%")
        expectRect(
            frame(.reasonableSize, window: reasonable)!, reasonable, "reasonable size is idempotent")

        // Small displays never reach the cap, so the fraction is what shows.
        let small = WindowLayout.Screen(
            id: 7, frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        expectRect(
            frame(.reasonableSize, on: small)!, CGRect(x: 256, y: 160, width: 768, height: 480),
            "reasonable size is uncapped on a small display")

        // Large ones do, which is what keeps the command display-independent.
        let large = WindowLayout.Screen(
            id: 8, frame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let capped = frame(.reasonableSize, on: large)!
        expect(
            capped.width == 1025 && capped.height == 900, "reasonable size caps at 1025×900")
        expect(large.visibleFrame.contains(capped), "a capped reasonable size stays on screen")
        expect(
            abs(capped.midX - large.visibleFrame.midX) <= 0.5
                && abs(capped.midY - large.visibleFrame.midY) <= 0.5,
            "a capped reasonable size stays centred")

        let window = CGRect(x: 100, y: 200, width: 300, height: 400)
        let tall = frame(.maximizeHeight, window: window)!
        expect(
            tall.minX == 100 && tall.width == 300, "maximize height preserves minX and width exactly")
        expect(tall.minY == 0 && tall.height == 900, "maximize height fills the canvas vertically")

        let wide = frame(.maximizeWidth, window: window)!
        expect(
            wide.minY == 200 && wide.height == 400, "maximize width preserves minY and height exactly")
        expect(wide.minX == 0 && wide.width == 1440, "maximize width fills the canvas horizontally")

        // An off-screen window must not come back full-height and still off-screen.
        let stray = CGRect(x: -900, y: -900, width: 200, height: 150)
        let strayTall = frame(.maximizeHeight, window: stray)!
        expect(strayTall.minX == 0 && strayTall.width == 200, "maximize height clamps a stray x")
        expect(
            !strayTall.intersection(mainScreen.visibleFrame).isNull,
            "maximize height brings a stray window back on screen")
        let strayWide = frame(.maximizeWidth, window: stray)!
        expect(strayWide.minY == 0 && strayWide.height == 150, "maximize width clamps a stray y")
        expect(
            !strayWide.intersection(mainScreen.visibleFrame).isNull,
            "maximize width brings a stray window back on screen")

        expectRect(
            frame(.center, window: window)!, CGRect(x: 570, y: 250, width: 300, height: 400),
            "center preserves the size and centres it")
        expectRect(
            frame(.center, window: frame(.center, window: window)!)!,
            frame(.center, window: window)!, "center is idempotent")

        // A window larger than the screen must be clamped down, not centred off-screen.
        let huge = CGRect(x: -500, y: -500, width: 3000, height: 2000)
        let centred = frame(.center, window: huge)!
        expect(
            centred.width <= 1440 && centred.height <= 900, "center clamps an oversized window")
        expect(mainScreen.visibleFrame.contains(centred), "a clamped center stays on screen")

        expectRect(
            frame(.centerHalf)!, CGRect(x: 360, y: 0, width: 720, height: 900),
            "center half is half the screen's area")
    }

    // MARK: - Make Larger / Make Smaller

    static func testLargerSmaller() {
        let start = CGRect(x: 100, y: 100, width: 600, height: 400)
        let larger = frame(.makeLarger, window: start)!
        expect(larger.width > start.width && larger.height > start.height, "make larger grows")
        // The assertion that justifies screen-relative steps: size-relative ones cannot round-trip.
        expectRect(
            frame(.makeSmaller, window: larger)!, start,
            "larger then smaller returns the exact original rect")
        let smaller = frame(.makeSmaller, window: start)!
        expectRect(
            frame(.makeLarger, window: smaller)!, start,
            "smaller then larger returns the exact original rect")
        expect(larger.midX == start.midX && larger.midY == start.midY, "growing keeps the centre")
        expect(smaller.midX == start.midX && smaller.midY == start.midY, "shrinking keeps the centre")

        // Repeated shrinking saturates at the floor instead of collapsing.
        var shrinking = start
        for _ in 0..<40 { shrinking = frame(.makeSmaller, window: shrinking)! }
        expect(shrinking.width > 0 && shrinking.height > 0, "40 shrinks never collapse the window")
        expectRect(
            frame(.makeSmaller, window: shrinking)!, shrinking, "shrinking saturates into a no-op")

        // Repeated growing converges on the canvas.
        var growing = start
        for _ in 0..<40 { growing = frame(.makeLarger, window: growing)! }
        expectRect(growing, mainScreen.visibleFrame, "40 grows converge on the maximized frame")
        expectRect(frame(.makeLarger, window: growing)!, growing, "growing saturates into a no-op")

        // With a gap, growing converges on the gapped canvas rather than the raw visible frame.
        var gapped = start
        for _ in 0..<40 { gapped = frame(.makeLarger, window: gapped, gap: 12)! }
        expectRect(gapped, frame(.maximize, gap: 12)!, "growing respects the gap")
    }

    // MARK: - Nudges

    static func testNudges() {
        let start = CGRect(x: 300, y: 300, width: 600, height: 400)
        for command in [WindowCommand.ID.moveLeft, .moveRight, .moveUp, .moveDown] {
            let moved = frame(command, window: start)!
            expect(moved.size == start.size, "\(command.rawValue) leaves the size untouched")
        }
        expectRect(
            frame(.moveLeft, window: start)!, CGRect(x: 228, y: 300, width: 600, height: 400),
            "move left nudges by 5% of the screen width")
        expectRect(
            frame(.moveUp, window: start)!, CGRect(x: 300, y: 255, width: 600, height: 400),
            "move up nudges by 5% of the screen height")
        expectRect(
            frame(.moveRight, window: frame(.moveLeft, window: start)!)!, start,
            "left then right returns the original position")
        expectRect(
            frame(.moveDown, window: frame(.moveUp, window: start)!)!, start,
            "up then down returns the original position")

        var sliding = start
        for _ in 0..<30 { sliding = frame(.moveLeft, window: sliding)! }
        expect(sliding.minX == 0, "30 nudges left end flush against the canvas edge")
        expect(sliding.size == start.size, "nudging to the edge never resizes")
        expectRect(frame(.moveLeft, window: sliding)!, sliding, "a flush window nudges no further")

        // A window wider than the canvas pins its leading edge rather than being shoved off the far side.
        let overWide = CGRect(x: 100, y: 100, width: 2000, height: 400)
        let pinned = frame(.moveLeft, window: overWide)!
        expect(pinned.minX == 0, "an oversized window pins to the canvas edge")
        expect(pinned.size == overWide.size, "an oversized nudge never resizes")
    }

    // MARK: - Displays

    static func testDisplays() {
        expect(frame(.nextDisplay) == nil, "a single display makes Next Display a no-op")
        expect(frame(.previousDisplay) == nil, "a single display makes Previous Display a no-op")

        let left = mainScreen
        let right = WindowLayout.Screen(
            id: 2, frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440))
        // Deliberately out of order, to prove the ordering is derived and not inherited.
        let both = screens(right, left)
        expect(WindowLayout.ordered(both).map(\.id) == [1, 2], "displays order left-to-right")

        let leftHalfOnLeft = frame(.leftHalf, on: left)!
        let onRight = frame(
            .nextDisplay, window: leftHalfOnLeft, allScreens: both)!
        expectRect(
            onRight, CGRect(x: 1440, y: 0, width: 1280, height: 1440),
            "a left half maps proportionally onto the larger display")
        expect(right.visibleFrame.contains(onRight), "the moved window stays inside the destination")

        expectRect(
            frame(.previousDisplay, window: onRight, allScreens: both)!, leftHalfOnLeft,
            "next then previous round-trips to the original frame")

        // Wrapping in both directions.
        expect(
            WindowLayout.placement(
                for: WindowLayout.Input(
                    command: .previousDisplay, windowFrame: leftHalfOnLeft, screens: both)
            )?.screenID == 2, "previous from the first display wraps to the last")
        expect(
            WindowLayout.placement(
                for: WindowLayout.Input(command: .nextDisplay, windowFrame: onRight, screens: both)
            )?.screenID == 1, "next from the last display wraps to the first")

        // A remembered tile is re-derived exactly on the destination, gaps included.
        expectRect(
            frame(.nextDisplay, window: leftHalfOnLeft, gap: 10, lastTile: .leftHalf, allScreens: both)!,
            frame(.leftHalf, on: right, gap: 10)!,
            "a remembered tile is re-derived exactly on the destination")
        expectRect(
            frame(
                .nextDisplay, window: frame(.firstThird, on: left)!, lastTile: .firstThird,
                allScreens: both)!,
            frame(.firstThird, on: right)!,
            "a remembered third is re-derived exactly on the destination")

        // Screen resolution by overlap.
        expect(
            WindowLayout.screen(
                containing: CGRect(x: 1150, y: 0, width: 500, height: 100), in: both)?.id == 1,
            "a straddling window belongs to the display showing more of it")
        expect(
            WindowLayout.screen(
                containing: CGRect(x: 1300, y: 0, width: 500, height: 100), in: both)?.id == 2,
            "the overlap majority flips with the window")
        expect(
            WindowLayout.screen(
                containing: CGRect(x: -5000, y: -5000, width: 100, height: 100), in: both) != nil,
            "a window off every display still resolves to one")
    }

    // MARK: - Restore

    static func testRestore() {
        expect(frame(.restore) == nil, "restore with no recorded frame does nothing")

        let recorded = CGRect(x: 123, y: 234, width: 456, height: 321)
        expectRect(
            frame(.restore, restore: recorded)!, recorded, "a valid restore frame comes back untouched")

        // A restore point stranded off every current display (a monitor was unplugged) is recovered.
        let stranded = CGRect(x: 9000, y: 9000, width: 400, height: 300)
        let recovered = frame(.restore, restore: stranded)!
        expect(recovered.size == stranded.size, "a stranded restore keeps its size")
        expect(
            mainScreen.visibleFrame.contains(recovered), "a stranded restore lands back on screen")
        expect(
            recovered.midX == mainScreen.visibleFrame.midX,
            "a stranded restore is re-centred horizontally")
    }

    // MARK: - Action memory

    static func testMemory() {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let half = CGRect(x: 0, y: 0, width: 720, height: 900)
        let original = CGRect(x: 100, y: 100, width: 600, height: 400)

        // A fresh window: step 0, nothing to restore to yet, and the current frame becomes the anchor.
        var memory = WindowActionMemory<Int>()
        var decision = memory.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        expect(decision.step == 0, "a first press starts at step 0")
        expect(!decision.canRestore, "a never-seen window has nothing to restore to")
        expectRect(decision.restoreFrame, original, "the first press captures the original frame")
        memory.commit(
            key: 1, command: .leftHalf, decision: decision, appliedFrame: half, screenID: 1,
            now: clock)

        // Repeats advance the cycle and never disturb the restore point.
        for expected in [1, 2, 0, 1] {
            let applied = frame(.leftHalf, step: expected)!
            decision = memory.decide(
                key: 1, command: .leftHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
                currentScreenID: 1, cycleEnabled: true, now: clock)
            expect(decision.step == expected, "the cycle advances to step \(expected)")
            expectRect(decision.restoreFrame, original, "the restore point survives step \(expected)")
            expect(decision.canRestore, "a seen window can be restored")
            memory.commit(
                key: 1, command: .leftHalf, decision: decision, appliedFrame: applied, screenID: 1,
                now: clock)
        }

        // A different command, screen, or window resets the cycle.
        decision = memory.decide(
            key: 1, command: .rightHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 1, cycleEnabled: true, now: clock)
        expect(decision.step == 0, "a different command restarts the cycle")
        expectRect(decision.restoreFrame, original, "a different command keeps the restore point")
        decision = memory.decide(
            key: 1, command: .leftHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 2, cycleEnabled: true, now: clock)
        expect(decision.step == 0, "a different display restarts the cycle")
        decision = memory.decide(
            key: 99, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        expect(decision.step == 0 && !decision.canRestore, "another window has its own chain")

        // A user drag resets the cycle and re-anchors the restore point.
        var dragged = WindowActionMemory<Int>()
        let seed = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        dragged.commit(
            key: 1, command: .leftHalf, decision: seed, appliedFrame: half, screenID: 1, now: clock)
        let movedByUser = CGRect(x: 400, y: 400, width: 500, height: 300)
        decision = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: movedByUser, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        expect(decision.step == 0, "a user drag restarts the cycle")
        expectRect(decision.restoreFrame, movedByUser, "a user drag re-anchors the restore point")
        expect(decision.lastTileCommand == nil, "a user drag forgets the remembered tile")

        // A quantising app that lands a point off its target must NOT read as a user drag.
        let quantised = CGRect(x: half.minX + 1, y: half.minY, width: half.width - 1, height: half.height)
        decision = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: quantised, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        expect(decision.step == 1, "a sub-tolerance difference keeps the cycle running")
        expect(decision.lastTileCommand == .leftHalf, "an untouched tile is remembered")

        // The cycle switch pins everything to step 0.
        var pinned = WindowActionMemory<Int>()
        var pinnedDecision = pinned.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleEnabled: false, now: clock)
        for _ in 0..<5 {
            pinned.commit(
                key: 1, command: .leftHalf, decision: pinnedDecision, appliedFrame: half,
                screenID: 1, now: clock)
            pinnedDecision = pinned.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleEnabled: false, now: clock)
            expect(pinnedDecision.step == 0, "cycling off pins every repeat to step 0")
        }

        // A non-cycling command never advances even with cycling on.
        var nonCycling = WindowActionMemory<Int>()
        let maximized = mainScreen.visibleFrame
        var nonDecision = nonCycling.decide(
            key: 1, command: .maximize, currentFrame: original, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        for _ in 0..<5 {
            nonCycling.commit(
                key: 1, command: .maximize, decision: nonDecision, appliedFrame: maximized,
                screenID: 1, now: clock)
            nonDecision = nonCycling.decide(
                key: 1, command: .maximize, currentFrame: maximized, currentScreenID: 1,
                cycleEnabled: true, now: clock)
            expect(nonDecision.step == 0, "a non-cycling command never advances")
        }

        // Cycle timeout.
        var timed = WindowActionMemory<Int>(cycleTimeout: 60)
        let timedSeed = timed.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        timed.commit(
            key: 1, command: .leftHalf, decision: timedSeed, appliedFrame: half, screenID: 1,
            now: clock)
        expect(
            timed.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleEnabled: true, now: clock.addingTimeInterval(30)
            ).step == 1, "a cycle inside the timeout continues")
        expect(
            timed.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleEnabled: true, now: clock.addingTimeInterval(120)
            ).step == 0, "a cycle past the timeout restarts")

        // The restore point survives a run of different commands, then Restore is idempotent.
        var run = WindowActionMemory<Int>()
        var runDecision = run.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        run.commit(
            key: 1, command: .leftHalf, decision: runDecision, appliedFrame: half, screenID: 1,
            now: clock)
        var applied = half
        for command in [WindowCommand.ID.maximize, .topRightQuarter, .centerThird] {
            runDecision = run.decide(
                key: 1, command: command, currentFrame: applied, currentScreenID: 1,
                cycleEnabled: true, now: clock)
            applied = frame(command)!
            run.commit(
                key: 1, command: command, decision: runDecision, appliedFrame: applied, screenID: 1,
                now: clock)
        }
        runDecision = run.decide(
            key: 1, command: .restore, currentFrame: applied, currentScreenID: 1, cycleEnabled: true,
            now: clock)
        expectRect(
            runDecision.restoreFrame, original, "the restore point survives three other commands")
        expect(runDecision.canRestore, "the window can be restored after a run of commands")
        let restored = frame(.restore, restore: runDecision.restoreFrame)!
        expectRect(restored, original, "restore returns the true original frame")
        run.commit(
            key: 1, command: .restore, decision: runDecision, appliedFrame: restored, screenID: 1,
            now: clock)
        let second = run.decide(
            key: 1, command: .restore, currentFrame: restored, currentScreenID: 1,
            cycleEnabled: true, now: clock)
        expectRect(
            frame(.restore, restore: second.restoreFrame)!, original, "a second restore is idempotent")

        // Fullscreen breaks the cycle chain but keeps the restore point.
        run.forgetCycle(key: 1)
        expect(run.record(for: 1)?.step == 0, "forgetCycle resets the step")
        expectRect(
            run.record(for: 1)!.restoreFrame, original, "forgetCycle keeps the restore point")

        // Bounded growth, most-recently-used retained.
        var bounded = WindowActionMemory<Int>(capacity: 64)
        for key in 0..<100 {
            let boundedDecision = bounded.decide(
                key: key, command: .leftHalf, currentFrame: original, currentScreenID: 1,
                cycleEnabled: true, now: clock)
            bounded.commit(
                key: key, command: .leftHalf, decision: boundedDecision, appliedFrame: half,
                screenID: 1, now: clock)
        }
        expect(bounded.count == 64, "the memory is bounded at its capacity")
        expect(bounded.record(for: 99) != nil, "the most recent key survives eviction")
        expect(bounded.record(for: 0) == nil, "the oldest key is evicted")
        expect(bounded.record(for: 36) != nil, "the 64 most recent keys survive")

        // Forgetting.
        bounded.forget { $0 % 2 == 0 }
        expect(bounded.record(for: 99) != nil, "forget(where:) keeps non-matching keys")
        expect(bounded.record(for: 98) == nil, "forget(where:) drops matching keys")
        bounded.forget(key: 99)
        expect(bounded.record(for: 99) == nil, "forget(key:) drops that key")
    }

    // MARK: - Fuzz

    static func testFuzz() {
        let displays: [[WindowLayout.Screen]] = [
            [mainScreen],
            [
                mainScreen,
                WindowLayout.Screen(
                    id: 2, frame: CGRect(x: 1440, y: -200, width: 2560, height: 1440),
                    visibleFrame: CGRect(x: 1440, y: -175, width: 2560, height: 1390))
            ],
            [
                WindowLayout.Screen(
                    id: 5, frame: CGRect(x: 0, y: 0, width: 1024, height: 640),
                    visibleFrame: CGRect(x: 0, y: 25, width: 1024, height: 590)),
                WindowLayout.Screen(
                    id: 6, frame: CGRect(x: -3840, y: 0, width: 3840, height: 2160),
                    visibleFrame: CGRect(x: -3840, y: 25, width: 3840, height: 2060))
            ]
        ]
        let windows: [CGRect] = [
            CGRect(x: 100, y: 100, width: 600, height: 400),
            CGRect(x: 0, y: 0, width: 0, height: 0),
            CGRect(x: -900, y: -900, width: 200, height: 150),
            CGRect(x: 200, y: 200, width: 5000, height: 4000),
            CGRect(x: 1439, y: 899, width: 1, height: 1)
        ]
        let gaps: [CGFloat] = [0, 1, 8, 25, 200]

        var checked = 0
        var problems: [String] = []
        for screens in displays {
            for window in windows {
                for gap in gaps {
                    for command in WindowCommand.ID.allCases {
                        let input = WindowLayout.Input(
                            command: command, windowFrame: window, screens: screens, gap: gap,
                            step: 0, restoreFrame: window, lastTileCommand: nil)
                        // A nil placement is a legitimate quiet no-op, not a failure.
                        guard let placement = WindowLayout.placement(for: input) else { continue }
                        checked += 1
                        let rect = placement.frame
                        let label = "\(command.rawValue) gap \(gap) window \(window)"

                        if !(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite
                            && rect.height.isFinite)
                        {
                            problems.append("non-finite frame: \(label)")
                        }
                        if rect.width < 0 || rect.height < 0 {
                            problems.append("negative size: \(label)")
                        }
                        guard let host = screens.first(where: { $0.id == placement.screenID })
                        else {
                            problems.append("unknown screen id: \(label)")
                            continue
                        }
                        if rect.intersection(host.visibleFrame).isNull {
                            problems.append("off-screen frame: \(label)")
                        }
                        // Determinism, and no drift when the same command is applied twice at step 0.
                        if WindowLayout.placement(for: input)?.frame != rect {
                            problems.append("non-deterministic: \(label)")
                        }
                        var repeated = input
                        repeated.windowFrame = rect
                        if let again = WindowLayout.placement(for: repeated)?.frame,
                            command != .makeLarger, command != .makeSmaller, command != .moveLeft,
                            command != .moveRight, command != .moveUp, command != .moveDown,
                            command != .nextDisplay, command != .previousDisplay,
                            again != rect
                        {
                            problems.append("drifts on repeat: \(label) — \(rect) then \(again)")
                        }
                    }
                }
            }
        }
        expect(checked > 1000, "the fuzz sweep exercised a meaningful number of placements")
        expect(problems.isEmpty, "fuzz sweep found no violations")
        for problem in problems.prefix(10) { print("      \(problem)") }
    }
}
