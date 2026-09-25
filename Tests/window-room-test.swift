// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
// Standalone contract tests for the pure room model, its plan and its three stores.
import CoreGraphics
import Foundation

@main
@MainActor
struct WindowRoomTests {
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

    static func expectThrows(
        _ expected: RoomValidationError, _ message: String, _ body: () throws -> Void
    ) {
        do {
            try body()
            expect(false, message)
        } catch let error as RoomValidationError {
            expect(error == expected, message)
        } catch {
            expect(false, message)
        }
    }

    // MARK: - Fixtures

    static let gap: CGFloat = 16
    /// A 1728 × 1080 visible frame under a 37-pt menu bar.
    static let area = CGRect(x: 0, y: 37, width: 1728, height: 1080)
    static let laptop = CGRect(x: 0, y: 33, width: 1728, height: 1000)
    static let monitor = CGRect(x: 0, y: 25, width: 2560, height: 1390)
    static let typicalMinimums = [
        CGSize.zero, CGSize(width: 360, height: 360), CGSize(width: 606, height: 454),
        CGSize(width: 600, height: 400)
    ]

    static func canvas(_ visible: CGRect, gap: CGFloat = gap) -> CGRect {
        RoomLayoutEngine.Area(visible: visible, gap: gap).canvas
    }

    static func overlapping(_ frames: [CGRect]) -> Bool {
        for i in frames.indices {
            for j in frames.indices where i < j {
                let shared = frames[i].intersection(frames[j])
                if !shared.isNull, shared.width > 0, shared.height > 0 { return true }
            }
        }
        return false
    }

    static func inside(_ frames: [CGRect], _ box: CGRect) -> Bool {
        frames.allSatisfy { box.insetBy(dx: -1, dy: -1).contains($0) }
    }

    static func screen(
        _ visible: CGRect, uuid: String = "display-a", id: Int = 1
    ) -> WindowLayoutScreen {
        WindowLayoutScreen(
            display: WindowLayoutDisplay(uuid: uuid, name: uuid),
            screen: WindowPlacementEngine.Screen(id: id, frame: visible, visibleFrame: visible))
    }

    static func live(
        _ handle: Int, _ bundleID: String, title: String = "", id: UInt32? = nil,
        frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600), minimized: Bool = false
    ) -> RoomLiveWindow {
        RoomLiveWindow(
            handle: handle, bundleID: bundleID, appName: bundleID, title: title, windowID: id,
            frame: frame, isMinimized: minimized)
    }

    static func window(_ bundleID: String, title: String = "", id: UInt32? = nil) -> RoomWindow {
        RoomWindow(bundleID: bundleID, appName: bundleID, title: title, windowID: id)
    }

    /// A deterministic sample of rooms: 1…6 windows mixing real apps' minimum sizes.
    static func everyRoom(_ check: (CGRect, [CGSize]) -> Void) {
        let sizes = [
            CGSize(width: 900, height: 600), CGSize(width: 606, height: 454),
            CGSize(width: 600, height: 400), CGSize(width: 360, height: 360), .zero
        ]
        for visible in [
            CGRect(x: 0, y: 33, width: 1728, height: 1084), CGRect(x: 0, y: 25, width: 3360, height: 1385)
        ] {
            for count in 1...6 {
                for seed in 0..<60 {
                    var value = UInt64(seed * 7919 + count)
                    let minimums = (0..<count).map { _ -> CGSize in
                        value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        return sizes[Int((value >> 33) % UInt64(sizes.count))]
                    }
                    check(visible, minimums)
                }
            }
        }
    }

    static func main() {
        tilingBasics()
        minimumSizes()
        autoAndStack()
        gapConvention()
        gridLayouts()
        arrangementReading()
        learning()
        windowMatching()
        parking()
        planning()
        layoutChoices()
        roomRecord()
        storeCRUD()
        minimumSizeStore()
        parkingLedger()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Tiling

    static func tilingBasics() {
        let box = canvas(area)
        expect(
            RoomLayoutEngine.frames(count: 1, kind: .auto, in: area, gap: gap) == [box],
            "one window fills the canvas")

        let focus = RoomLayoutEngine.frames(count: 3, kind: .focus, in: area, gap: gap)
        expect(focus.count == 3, "focus places every window")
        expect(focus[0].minX == box.minX && focus[0].height == box.height, "the hero is full height")
        expect(focus[0].width > focus[1].width, "the hero is the largest")
        expect(focus[1].minX == focus[2].minX, "the side windows share one column")
        expect(focus[2].minY - focus[1].maxY == gap, "stacked side windows keep one gap")
        expect(focus[1].minX - focus[0].maxX == gap, "the column sits one gap from the hero")
        expect(!overlapping(focus) && inside(focus, box), "focus is clean")

        for kind in [RoomLayoutKind.focus, .columns, .grid] {
            for count in 1...8 {
                let frames = RoomLayoutEngine.frames(count: count, kind: kind, in: area, gap: gap)
                expect(frames.count == count, "\(kind) \(count) places every window")
                expect(!overlapping(frames), "\(kind) \(count) never overlaps")
                expect(inside(frames, box), "\(kind) \(count) stays inside the canvas")
            }
        }

        let grid = RoomLayoutEngine.frames(count: 3, kind: .grid, in: area, gap: gap)
        expect(grid[2].width > grid[0].width && grid[2].minX == grid[0].minX, "a short last row stretches")

        for kind in RoomLayoutKind.allCases {
            expect(
                !RoomLayoutEngine.fits(count: 0, kind: kind, in: area, gap: gap),
                "\(kind) never fits zero windows")
            expect(
                RoomLayoutEngine.frames(count: 0, kind: kind, in: area, gap: gap).isEmpty,
                "\(kind) places nothing for zero windows")
        }

        let distributed = RoomLayoutEngine.distribute(1000, gap: 16, minimums: [0, 0, 0], weights: [1, 1, 1])
        expect(distributed.reduce(0, +) == 968, "whole-point pieces add up exactly")
        expect(
            RoomLayoutEngine.distribute(1016, gap: 16, minimums: [0, 0], weights: [0.6, 0.4]) == [600, 400],
            "without minimums the weights decide")
        expect(
            RoomLayoutEngine.distribute(1000, gap: 16, minimums: [0, 600], weights: [0.6, 0.4]) == [384, 600],
            "a minimum is kept and the rest give way")
    }

    static func minimumSizes() {
        let box = canvas(area)
        let wide = [CGSize.zero, .zero, CGSize(width: 900, height: 600)]
        let focus = RoomLayoutEngine.frames(count: 3, kind: .focus, in: area, gap: gap, minimums: wide)
        expect(focus[2].width >= 900 && focus[1].width >= 900, "the column widens for a wide app")
        expect(focus[0].maxX + gap == focus[1].minX, "the hero shrinks, keeping one gap")
        expect(!overlapping(focus) && inside(focus, box), "a wide app still tiles cleanly")

        let tall = [CGSize.zero, CGSize(width: 0, height: 684), .zero]
        let stacked = RoomLayoutEngine.frames(count: 3, kind: .focus, in: area, gap: gap, minimums: tall)
        expect(
            stacked[1].height >= 684 && stacked[2].minY - stacked[1].maxY == gap, "a tall app gets its height"
        )

        let columns = RoomLayoutEngine.frames(
            count: 3, kind: .columns, in: area, gap: gap,
            minimums: [CGSize(width: 900, height: 0), .zero, .zero])
        expect(
            columns[0].width >= 900 && abs(columns[1].width - columns[2].width) <= 1,
            "columns share what is left")

        for kind in [RoomLayoutKind.focus, .columns, .grid] {
            expect(
                RoomLayoutEngine.frames(count: 5, kind: kind, in: area, gap: gap)
                    == RoomLayoutEngine.frames(
                        count: 5, kind: kind, in: area, gap: gap,
                        minimums: Array(repeating: .zero, count: 5)),
                "\(kind): zero minimums change nothing")
        }

        let heights = [
            CGSize.zero, CGSize(width: 0, height: 360), CGSize(width: 0, height: 454),
            CGSize(width: 0, height: 400)
        ]
        let laptopFocus = RoomLayoutEngine.frames(
            count: 4, kind: .focus, in: laptop, gap: gap, minimums: heights)
        expect(inside(laptopFocus, canvas(laptop)), "tall minimums stay on a laptop")
        expect(!overlapping(laptopFocus), "tall minimums find another tidy arrangement")

        let small = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let impossible = Array(repeating: CGSize(width: 800, height: 500), count: 4)
        for kind in [RoomLayoutKind.focus, .columns, .grid] {
            let frames = RoomLayoutEngine.frames(
                count: 4, kind: kind, in: small, gap: gap, minimums: impossible)
            expect(
                frames.allSatisfy { small.contains($0) }, "\(kind): overlap is acceptable, off-screen is not")
        }

        let known = [
            CGSize.zero, CGSize(width: 360, height: 360), CGSize(width: 606, height: 454),
            CGSize(width: 0, height: 400)
        ]
        let mixed = RoomLayoutEngine.frames(count: 4, kind: .focus, in: laptop, gap: gap, minimums: known)
        expect(inside(mixed, canvas(laptop)) && !overlapping(mixed), "known widths and heights both fit")
        expect(
            mixed[0].width >= (canvas(laptop).width - gap) * 0.55, "the main window keeps most of the width")

        let unknown = [CGSize(width: 360, height: 360), .zero, CGSize(width: 970, height: 600)]
        for kind in [RoomLayoutKind.focus, .columns, .grid]
        where RoomLayoutEngine.fits(count: 3, kind: kind, in: laptop, gap: gap, minimums: unknown) {
            let frames = RoomLayoutEngine.frames(
                count: 3, kind: kind, in: laptop, gap: gap, minimums: unknown)
            expect(
                frames[1].width >= RoomLayoutEngine.usable.width - 1
                    && frames[1].height >= RoomLayoutEngine.usable.height - 1,
                "\(kind): an unknown minimum is never squeezed to nothing")
        }
        for count in 2...8 {
            for kind in [RoomLayoutKind.focus, .columns, .grid]
            where RoomLayoutEngine.fits(count: count, kind: kind, in: laptop, gap: gap) {
                let frames = RoomLayoutEngine.frames(count: count, kind: kind, in: laptop, gap: gap)
                expect(
                    frames.allSatisfy {
                        $0.width >= RoomLayoutEngine.usable.width - 1
                            && $0.height >= RoomLayoutEngine.usable.height - 1
                    }, "\(kind) \(count): every tidy window is usable")
            }
        }
    }

    static func autoAndStack() {
        expect(
            RoomLayoutEngine.frames(count: 3, kind: .auto, in: area, gap: gap)
                == RoomLayoutEngine.frames(count: 3, kind: .focus, in: area, gap: gap),
            "three windows on a laptop are Focus")
        expect(
            RoomLayoutEngine.frames(count: 4, kind: .auto, in: area, gap: gap)
                == RoomLayoutEngine.frames(count: 4, kind: .grid, in: area, gap: gap),
            "four windows on a laptop are a grid, not a stack")
        expect(
            RoomLayoutEngine.frames(count: 4, kind: .auto, in: monitor, gap: gap)
                == RoomLayoutEngine.frames(count: 4, kind: .focus, in: monitor, gap: gap),
            "four windows on a monitor are Focus")
        expect(
            RoomLayoutEngine.frames(count: 6, kind: .auto, in: monitor, gap: gap)
                == RoomLayoutEngine.frames(count: 6, kind: .grid, in: monitor, gap: gap),
            "six windows on a monitor are a grid")

        expect(
            RoomLayoutEngine.autoKind(count: 4, in: laptop, gap: gap, minimums: typicalMinimums) == .grid,
            "auto tiles a laptop")
        expect(
            RoomLayoutEngine.autoKind(count: 4, in: monitor, gap: gap, minimums: typicalMinimums) == .focus,
            "auto focuses a monitor")
        expect(RoomLayoutEngine.autoKind(count: 2, in: laptop, gap: gap) == .focus, "two windows are Focus")
        let sideBySide = [
            CGSize(width: 600, height: 400), CGSize(width: 480, height: 721), CGSize(width: 360, height: 360)
        ]
        expect(
            RoomLayoutEngine.autoKind(count: 3, in: laptop, gap: gap, minimums: sideBySide) == .columns,
            "tall apps go side by side")
        let big = CGSize(width: 900, height: 600)
        expect(
            RoomLayoutEngine.autoKind(count: 3, in: laptop, gap: gap, minimums: [big, big, big]) == .stack,
            "auto stacks only as a last resort")
        expect(
            !RoomLayoutEngine.fits(count: 2, kind: .columns, in: laptop, gap: gap, minimums: [big, big]),
            "two wide apps never fit side by side")

        let stack = RoomLayoutEngine.frames(
            count: 4, kind: .stack, in: laptop, gap: gap, minimums: typicalMinimums)
        let box = canvas(laptop)
        let side = Array(stack.dropFirst())
        expect(inside(stack, box), "a stack stays on screen")
        expect(stack[0].width >= (box.width - gap) * 0.6 - 1, "the main window keeps its share")
        expect(Set(side.map(\.size)).count == 1, "stacked windows share one size")
        expect(side[0].minY > side[1].minY && side[1].minY > side[2].minY, "the second window sits lowest")
        expect(side[0].minY - side[1].minY == RoomLayoutEngine.peek, "each title bar peeks out")
        expect(side.allSatisfy { $0.height >= 454 }, "a stack still honours minimum heights")

        everyRoom { visible, minimums in
            for kind in [RoomLayoutKind.focus, .columns, .grid]
            where RoomLayoutEngine.fits(
                count: minimums.count, kind: kind, in: visible, gap: gap, minimums: minimums)
            {
                let frames = RoomLayoutEngine.frames(
                    count: minimums.count, kind: kind, in: visible, gap: gap, minimums: minimums)
                expect(
                    !overlapping(frames),
                    "\(kind) \(minimums) on \(visible.width): a fitting layout never overlaps")
                expect(inside(frames, canvas(visible)), "\(kind) \(minimums): a fitting layout stays inside")
            }
            if RoomLayoutEngine.autoKind(count: minimums.count, in: visible, gap: gap, minimums: minimums)
                != .stack
            {
                let frames = RoomLayoutEngine.frames(
                    count: minimums.count, kind: .auto, in: visible, gap: gap, minimums: minimums)
                expect(!overlapping(frames), "\(minimums): auto overlaps only when it stacks")
            }
        }
    }

    static func gapConvention() {
        let zero = RoomLayoutEngine.frames(count: 2, kind: .columns, in: area, gap: 0)
        expect(zero[0].minX == area.minX && zero[1].maxX == area.maxX, "gap 0 reaches the screen edges")
        expect(zero[1].minX == zero[0].maxX, "gap 0 leaves windows touching")
        expect(zero[0].minY == area.minY && zero[0].maxY == area.maxY, "gap 0 spans the full height")

        let gapped = RoomLayoutEngine.frames(count: 2, kind: .columns, in: area, gap: 24)
        expect(
            gapped[0].minX - area.minX == 24 && area.maxX - gapped[1].maxX == 24,
            "the edges take the full gap")
        expect(gapped[1].minX - gapped[0].maxX == 24, "neighbours sit exactly one gap apart")

        let absurd = RoomLayoutEngine.frames(count: 2, kind: .columns, in: area, gap: 10_000)
        expect(absurd.allSatisfy { $0.width > 0 && area.contains($0) }, "an absurd gap is capped, not obeyed")
        let invalid = RoomLayoutEngine.frames(count: 2, kind: .columns, in: area, gap: .nan)
        expect(invalid == zero, "a non-finite gap reads as none")
    }

    // MARK: - Grid

    /// Dragged by hand: three thirds on top, ⅔ + ⅓ below, gaps a little uneven.
    static func roomByHand(_ visible: CGRect) -> [CGRect] {
        let x = visible.minX, y = visible.minY, w = visible.width, h = visible.height
        return [
            CGRect(x: x + 10, y: y + 12, width: w / 3 - 22, height: h / 2 - 20),
            CGRect(x: x + w / 3 + 4, y: y + 8, width: w / 3 - 14, height: h / 2 - 14),
            CGRect(x: x + 2 * w / 3 + 6, y: y + 14, width: w / 3 - 20, height: h / 2 - 22),
            CGRect(x: x + 12, y: y + h / 2 + 6, width: 2 * w / 3 - 24, height: h / 2 - 18),
            CGRect(x: x + 2 * w / 3 + 8, y: y + h / 2 + 10, width: w / 3 - 20, height: h / 2 - 22)
        ]
    }

    static func gridLayouts() {
        typealias Cell = RoomGrid.Cell
        let reading = RoomArrangement.read(roomByHand(monitor), in: monitor, gap: gap)
        expect(reading.kind == .custom, "⅔ + ⅓ under three thirds is not mistaken for a grid")
        expect(
            reading.cells == [
                Cell(column: 0, columns: 4, row: 0, rows: 6), Cell(column: 4, columns: 4, row: 0, rows: 6),
                Cell(column: 8, columns: 4, row: 0, rows: 6), Cell(column: 0, columns: 8, row: 6, rows: 6),
                Cell(column: 8, columns: 4, row: 6, rows: 6)
            ], "the hand-made room snaps to its cells")

        guard let cells = reading.cells, let frames = RoomGrid.frames(cells, in: monitor, gap: gap) else {
            return expect(false, "the custom layout draws")
        }
        expect(
            frames[1].minX - frames[0].maxX == gap && frames[2].minX - frames[1].maxX == gap,
            "thirds keep one gap")
        expect(frames[4].minX - frames[3].maxX == gap, "⅔ and ⅓ keep one gap")
        expect(frames[3].minY - frames[0].maxY == gap, "rows keep one gap")
        expect(
            frames[3].minX == frames[0].minX && frames[3].maxX == frames[1].maxX, "⅔ spans two thirds exactly"
        )
        expect(frames[4].maxX == frames[2].maxX, "the last column lines up")

        let moved = RoomGrid.frames(cells, in: laptop, gap: gap) ?? []
        expect(
            moved.count == 5 && moved.allSatisfy { laptop.contains($0) },
            "the custom layout fits another display")

        let region = CGRect(x: 0, y: 0, width: 2366, height: 1331)
        let thirds = [
            Cell(column: 0, columns: 4, row: 0, rows: 12), Cell(column: 4, columns: 4, row: 0, rows: 12),
            Cell(column: 8, columns: 4, row: 0, rows: 12)
        ]
        let minimums = [
            CGSize(width: 400, height: 300), CGSize(width: 900, height: 600), CGSize(width: 600, height: 400)
        ]
        let widened = RoomGrid.frames(thirds, in: region, gap: gap, minimums: minimums) ?? []
        expect(
            widened[1].width >= 900 && widened[2].width >= 600 && widened[0].width >= 400,
            "columns widen for apps")
        expect(
            widened[1].minX - widened[0].maxX == gap && widened[2].minX - widened[1].maxX == gap,
            "widened columns keep one gap")

        let two = [Cell(column: 0, columns: 8, row: 0, rows: 6), Cell(column: 8, columns: 4, row: 0, rows: 6)]
        expect(
            RoomGrid.frames(two, in: region, gap: gap)
                == RoomGrid.frames(two, in: region, gap: gap, minimums: [.zero, .zero]),
            "zero minimums change nothing")

        let holey = [
            Cell(column: 7, columns: 5, row: 0, rows: 12), Cell(column: 0, columns: 7, row: 6, rows: 6),
            Cell(column: 0, columns: 7, row: 0, rows: 5)
        ]
        let filled = RoomGrid.fillingHoles(holey)
        expect(filled.map { $0.columns * $0.rows }.reduce(0, +) == 144, "an empty row between windows fills")
        expect(filled[0] == holey[0], "a window already reaching its edges stays put")
        let loose = RoomGrid.fillingHoles([
            Cell(column: 1, columns: 4, row: 1, rows: 10), Cell(column: 6, columns: 5, row: 0, rows: 11)
        ])
        expect(
            loose.map { $0.columns * $0.rows }.reduce(0, +) == 144,
            "windows short of the edges fill the screen")
        let diagonal = RoomGrid.fillingHoles([
            Cell(column: 1, columns: 1, row: 1, rows: 1), Cell(column: 0, columns: 1, row: 0, rows: 1)
        ])
        let rects = diagonal.map { CGRect(x: $0.column, y: $0.row, width: $0.columns, height: $0.rows) }
        expect(!rects[0].intersects(rects[1]), "growing never crosses a diagonal neighbour")

        for bad in [
            Cell(column: -1, columns: 4, row: 0, rows: 12), Cell(column: 0, columns: 0, row: 0, rows: 0),
            Cell(column: Int.max, columns: Int.max, row: 0, rows: 1)
        ] {
            expect(RoomGrid.fillingHoles([bad]) == [bad], "a malformed cell is left alone")
            expect(RoomGrid.frames([bad], in: area, gap: gap) == nil, "a malformed cell draws nothing")
        }
        expect(RoomGrid.cells(for: [.infinite], in: area, gap: gap) == nil, "an infinite frame is no cell")
        expect(
            RoomGrid.cells(for: [CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)], in: area, gap: gap)
                == nil, "NaN is no cell")
        expect(RoomGrid.cells(for: [area], in: .infinite, gap: gap) == nil, "an infinite display has no grid")
        expect(
            RoomGrid.cells(for: [CGRect(x: 1e30, y: 0, width: 100, height: 100)], in: area, gap: gap) == nil,
            "a far-off frame is no cell")
    }

    // MARK: - Arrangement

    static func arrangementReading() {
        let exact = RoomLayoutEngine.frames(count: 3, kind: .columns, in: monitor, gap: gap)
        let rough = exact.map { $0.offsetBy(dx: 12, dy: -9).insetBy(dx: 6, dy: 4) }
        let columns = RoomArrangement.read(rough, in: monitor, gap: gap)
        expect(columns.kind == .columns && columns.order == [0, 1, 2], "rough columns read as columns")

        let focus = RoomLayoutEngine.frames(count: 3, kind: .focus, in: monitor, gap: gap)
        let swapped = RoomArrangement.read([focus[1], focus[2], focus[0]], in: monitor, gap: gap)
        expect(swapped.kind == .focus && swapped.order.first == 2, "whoever holds the big spot becomes main")
        expect(Set(swapped.order) == [0, 1, 2], "every window keeps a place")

        let custom = [
            CGRect(x: 100, y: 200, width: 700, height: 500),
            CGRect(x: 900, y: 120, width: 1100, height: 1200),
            CGRect(x: 300, y: 800, width: 500, height: 400)
        ]
        let reading = RoomArrangement.read(custom, in: monitor, gap: gap)
        expect(
            reading.kind == .custom && reading.order == [0, 1, 2] && reading.cells?.count == 3,
            "side by side snaps to the grid")

        let stack = RoomLayoutEngine.frames(count: 4, kind: .stack, in: monitor, gap: gap)
        expect(RoomArrangement.read(stack, in: monitor, gap: gap).kind == .stack, "a stack reads as a stack")

        let cascade = (0..<3).map { CGRect(x: 100 + 40 * $0, y: 100 + 40 * $0, width: 900, height: 700) }
        expect(
            RoomArrangement.read(cascade, in: monitor, gap: gap).kind == .saved,
            "overlapping on purpose is kept exactly")
        expect(RoomArrangement.read([area], in: area, gap: gap).kind == .focus, "one window reads as Focus")
    }

    static func learning() {
        let display = screen(monitor, uuid: "MONITOR")
        let frames = RoomLayoutEngine.frames(count: 2, kind: .columns, in: monitor, gap: gap)
        let windows = [
            live(0, "app.a", title: "A", id: 1, frame: frames[1]),
            live(1, "app.b", title: "B", id: 2, frame: frames[0])
        ]
        let room = Room(name: "Build", windows: [window("app.gone", title: "Closed", id: 99)])

        let remembered = RoomArrangement.learn(
            room, from: windows, keeping: room.windows, on: display, spansDisplays: false, gap: gap,
            minimums: [.zero, .zero], keepsOrder: false)
        expect(remembered.reading.kind == .columns, "remembering reads the layout")
        expect(
            remembered.room.windows.map(\.bundleID) == ["app.b", "app.a", "app.gone"],
            "the main spot comes first and closed windows stay")
        expect(
            remembered.room.layout(onDisplay: "monitor") == .columns,
            "the layout is kept for this display, whatever its case")
        expect(remembered.room.layout(onDisplay: "laptop") == .auto, "other displays keep the room's layout")

        let relearned = RoomArrangement.learn(
            remembered.room, from: windows, keeping: [room.windows[0]], on: display,
            spansDisplays: false, gap: gap, minimums: [.zero, .zero], keepsOrder: false)
        expect(relearned.room.windows.count == 3, "remembering again never duplicates a member")

        let picked = RoomArrangement.learn(
            room, from: windows, on: display, spansDisplays: false, gap: gap,
            minimums: [.zero, .zero], keepsOrder: true)
        expect(
            picked.room.windows.map(\.bundleID) == ["app.a", "app.b"],
            "the picker's order wins and replaces the set")

        let cascade = (0..<2).map {
            live($0, "app.\($0)", frame: CGRect(x: 100 + 40 * $0, y: 100, width: 900, height: 700))
        }
        let loose = RoomArrangement.learn(
            room, from: cascade, on: display, spansDisplays: false, gap: gap, minimums: [], keepsOrder: true)
        expect(loose.reading.kind == .auto, "picking loose windows lets Auto tidy them")
        let spread = RoomArrangement.learn(
            room, from: windows, on: display, spansDisplays: true, gap: gap, minimums: [], keepsOrder: false)
        expect(spread.reading.kind == .auto, "windows from several displays have no arrangement to read")

        let custom = [
            CGRect(x: 100, y: 200, width: 700, height: 500),
            CGRect(x: 900, y: 120, width: 1100, height: 1200),
            CGRect(x: 300, y: 800, width: 500, height: 400)
        ]
        let learned = RoomArrangement.learn(
            room, from: custom.enumerated().map { live($0.offset, "app.\($0.offset)", frame: $0.element) },
            on: display, spansDisplays: false, gap: gap, minimums: [], keepsOrder: false)
        expect(
            learned.room.windows.prefix(3).allSatisfy { $0.cell != nil }, "a custom reading stores each cell")
        let unit = learned.room.windows[0].unitFrame
        expectRect(
            learned.room.windows[0].frame(in: monitor), custom[0],
            "a unit frame resolves back to the window (unit \(unit))")
    }

    // MARK: - Matching

    static func windowMatching() {
        let byID = RoomWindowMatcher.assign(
            [window("chrome", title: "Old title", id: 42)],
            to: [live(0, "chrome", title: "Old title", id: 7), live(1, "chrome", title: "Other", id: 42)])
        expect(byID == [0: 1], "the window ID wins over the title")

        let relaunched = RoomWindowMatcher.assign(
            [
                window("figma", title: "Design — Flows v3", id: 1),
                window("figma", title: "Portfolio — Case studies", id: 2)
            ],
            to: [
                live(0, "figma", title: "Portfolio — Case studies", id: 90),
                live(1, "figma", title: "Design — Flows v4", id: 91)
            ])
        expect(relaunched == [0: 1, 1: 0], "after a relaunch titles find the windows")

        let three = RoomWindowMatcher.assign(
            [window("chrome", title: "A"), window("chrome", title: "B"), window("chrome", title: "C")],
            to: [live(0, "chrome", title: "Z", id: 1), live(1, "chrome", title: "B", id: 2)])
        expect(three[1] == 1 && three.count == 2 && Set(three.values).count == 2, "no window is used twice")

        expect(
            RoomWindowMatcher.assign(
                [window("teams", title: "Chat")], to: [live(0, "chrome", title: "Chat", id: 1)]
            ).isEmpty,
            "another app's window never matches")

        let saved = window("chrome", title: "Project A", id: 1)
        let other = live(0, "chrome", title: "Project B", id: 20)
        let free = live(1, "chrome", title: "New Tab", id: 30)
        expect(
            RoomWindowMatcher.assign([saved], to: [other, free], claimed: [20]) == [0: 1],
            "a free window beats another room's")
        expect(
            RoomWindowMatcher.assign([saved], to: [other], claimed: [20]) == [0: 0],
            "with nothing free, any window fills it")

        expect(RoomWindowMatcher.isSimilar("Report — draft 3", "Report — draft 4"), "near titles are similar")
        expect(RoomWindowMatcher.isSimilar("Café Notes", "cafe notes"), "case and accents fold")
        expect(!RoomWindowMatcher.isSimilar("abc", "abc"), "very short titles are never similar")
        expect(!RoomWindowMatcher.isSimilar("Inbox", "Calendar"), "different titles are not similar")
    }

    // MARK: - Parking

    static func parking() {
        let screen = CGRect(x: 0, y: 25, width: 1728, height: 1092)
        let size = CGSize(width: 800, height: 600)
        expect(
            RoomParking.origin(for: size, on: screen, avoiding: []) == CGPoint(x: 1727, y: 1116),
            "with nothing around, a window parks bottom right")
        expect(
            RoomParking.origin(
                for: size, on: screen, avoiding: [CGRect(x: 1728, y: 0, width: 2560, height: 1440)])
                == CGPoint(x: -799, y: 1116),
            "a display to the right sends it bottom left")

        let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let window = CGSize(width: 1000, height: 700)
        for other in [
            CGRect(x: -823, y: -1418, width: 3360, height: 1418),
            CGRect(x: 1728, y: 0, width: 2560, height: 1440),
            CGRect(x: 0, y: 1117, width: 2560, height: 1440),
            CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        ] {
            let parked = CGRect(
                origin: RoomParking.origin(for: window, on: laptop, avoiding: [other]), size: window)
            expect(!parked.intersects(other), "parking avoids a display at \(other)")
            expect(laptop.intersects(parked), "a sliver stays on the laptop beside \(other)")
        }
        let boxedIn = [
            CGRect(x: 1728, y: -2000, width: 3000, height: 5000),
            CGRect(x: -3000, y: -2000, width: 3000, height: 5000)
        ]
        let cornered = CGRect(
            origin: RoomParking.origin(for: window, on: laptop, avoiding: boxedIn), size: window)
        expect(laptop.intersects(cornered), "boxed in, the least bad corner still keeps a sliver")

        let gone = CGRect(x: 500, y: -1200, width: 2000, height: 900)
        expect(
            laptop.contains(RoomParking.returnFrame(for: gone, screens: [laptop])),
            "a way back to a gone display comes home")
        let onLaptop = CGRect(x: 100, y: 100, width: 800, height: 600)
        expectRect(
            RoomParking.returnFrame(for: onLaptop, screens: [laptop]), onLaptop,
            "a way back on screen is kept")
    }

    // MARK: - Plan

    static func planning() {
        let display = screen(area)
        let room = Room(
            name: "Build",
            windows: [
                window("editor", title: "main.swift", id: 1), window("browser", title: "Docs", id: 2),
                window("gone")
            ])
        let windows = [
            live(0, "browser", title: "Docs", id: 2), live(1, "browser", title: "Mail", id: 3),
            live(2, "editor", title: "main.swift", id: 1), live(3, "chat", title: "Team", id: 4),
            live(4, "browser", title: "Old", id: 5, minimized: true),
            live(5, "com.apple.finder", title: "Desktop", id: 6)
        ]
        let plan = RoomPlan.make(room, windows: windows, on: display, gap: gap, minimums: [:])
        expect(plan.placements.map(\.index) == [0, 1], "placements follow the room's order")
        expect(plan.placements.map(\.handle) == [2, 0], "each room window takes its own window")
        expect(
            plan.placements.map(\.frame)
                == RoomLayoutEngine.frames(count: 2, kind: .auto, in: area, gap: gap),
            "the frames are the room's layout")
        expect(plan.missing == [2], "a closed window is missing, not guessed")
        expect(plan.parks == [1, 5], "other windows of room apps park, and so does the desktop's")
        expect(plan.keeps == ["editor", "browser", "gone", "com.apple.finder"], "only room apps stay visible")

        var columns = room
        columns.layoutsByDisplay["display-a"] = .columns
        let perDisplay = RoomPlan.make(columns, windows: windows, on: display, gap: gap, minimums: [:])
        expect(
            perDisplay.placements.map(\.frame)
                == RoomLayoutEngine.frames(count: 2, kind: .columns, in: area, gap: gap),
            "a layout chosen for this display applies here")
        let elsewhere = RoomPlan.make(
            columns, windows: windows, on: screen(area, uuid: "other"), gap: gap, minimums: [:])
        expect(elsewhere.placements.map(\.frame) == plan.placements.map(\.frame), "and nowhere else")

        var saved = Room(name: "Saved", windows: [window("editor", id: 1)], layout: .saved)
        saved.windows[0].unitFrame = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let savedPlan = RoomPlan.make(saved, windows: windows, on: display, gap: gap, minimums: [:])
        expectRect(
            savedPlan.placements.first?.frame, saved.windows[0].frame(in: area),
            "as arranged resolves the unit frame")
        saved.windows[0].unitFrame = CGRect(x: 0, y: 0, width: 2, height: 2)
        let tooBig = RoomPlan.make(saved, windows: windows, on: display, gap: gap, minimums: [:])
        expect(
            tooBig.placements.first?.frame == canvas(area),
            "an arrangement too big for this display falls back to Auto")

        var custom = Room(name: "Custom", windows: [window("editor", id: 1), window("gone")], layout: .custom)
        custom.windows[0].cell = RoomGrid.Cell(column: 0, columns: 6, row: 0, rows: 12)
        custom.windows[1].cell = RoomGrid.Cell(column: 6, columns: 6, row: 0, rows: 12)
        let partial = RoomPlan.make(custom, windows: windows, on: display, gap: gap, minimums: [:])
        expect(
            partial.placements.first?.frame == canvas(area),
            "a custom layout missing a window falls back to Auto")

        let big = CGSize(width: 1500, height: 900)
        var focused = room
        focused.layout = .columns
        let crowded = RoomPlan.make(
            focused, windows: windows, on: display, gap: gap, minimums: ["editor": big, "browser": big])
        expect(
            crowded.placements.map(\.frame)
                == RoomLayoutEngine.frames(count: 2, kind: .auto, in: area, gap: gap, minimums: [big, big]),
            "a layout that no longer fits falls back to Auto")
    }

    static func layoutChoices() {
        let display = screen(monitor)
        let windows = (0..<3).map { live($0, "app.\($0)", id: UInt32($0 + 1)) }
        let room = Room(name: "Three", windows: (0..<3).map { window("app.\($0)", id: UInt32($0 + 1)) })
        let choices = RoomPlan.layoutChoices(
            for: room, windows: windows, on: display, gap: gap, minimums: [:])
        expect(choices.first == .auto && choices.count > 1, "Auto leads, with more to try")
        expect(!choices.contains(.focus), "Focus hides while it looks exactly like Auto")
        expect(!choices.contains(.stack), "Stack hides while something tidier fits")
        expect(!choices.contains(.saved) && !choices.contains(.custom), "Tab never invents an arrangement")
        var seen: [[CGRect]] = []
        for kind in choices where kind != .auto {
            let frames = RoomPlan.frames(
                for: room, indices: [0, 1, 2], kind: kind, in: monitor, gap: gap,
                minimums: [.zero, .zero, .zero])
            expect(!seen.contains(frames), "\(kind) looks unlike the other choices")
            seen.append(frames)
        }

        let single = Room(name: "One", windows: [window("app.0", id: 1)])
        expect(
            RoomPlan.layoutChoices(for: single, windows: windows, on: display, gap: gap, minimums: [:]) == [
                .auto
            ],
            "one window offers Auto alone")
        var stacked = room
        stacked.layout = .stack
        expect(
            RoomPlan.layoutChoices(for: stacked, windows: windows, on: display, gap: gap, minimums: [:])
                .contains(.stack),
            "the current layout stays among the choices")

        expect(
            RoomPlan.nextLayout(after: .auto, in: [.auto, .focus, .grid], backwards: false) == .focus,
            "Tab steps forward")
        expect(
            RoomPlan.nextLayout(after: .auto, in: [.auto, .focus, .grid], backwards: true) == .grid,
            "⇧Tab wraps back")
        expect(
            RoomPlan.nextLayout(after: .columns, in: [.auto, .focus], backwards: false) == .focus,
            "an unoffered layout counts as Auto")
        expect(
            RoomPlan.nextLayout(after: .auto, in: [.auto], backwards: false) == nil,
            "one choice leaves Tab nothing to do")
    }

    // MARK: - Records and stores

    static func roomRecord() {
        let json = #"{"name":"Research","windows":[{"bundleID":"com.example.notes"}]}"#
        guard let room = try? JSONDecoder().decode(Room.self, from: Data(json.utf8)) else {
            return expect(false, "a minimal room decodes")
        }
        expect(room.layout == .auto && room.layoutsByDisplay.isEmpty, "a minimal room lays out with Auto")
        expect(
            room.windows[0].appName == "com.example.notes" && room.windows[0].title.isEmpty,
            "a minimal window gets defaults")

        var full = Room(name: "Design", windows: [window("figma", title: "Flows", id: 12)], layout: .grid)
        full.layoutsByDisplay["abc"] = .stack
        full.windows[0].cell = RoomGrid.Cell(column: 0, columns: 12, row: 0, rows: 12)
        let data = try? JSONEncoder().encode(full)
        expect(data.flatMap { try? JSONDecoder().decode(Room.self, from: $0) } == full, "a room round-trips")
        expect(
            full.layout(onDisplay: "ABC") == .stack && full.layout(onDisplay: nil) == .grid,
            "display layouts match on any case")
        expect(Room.id(fromEntryID: full.entryID) == full.id, "the entry id round-trips")
        expect(
            Room.id(fromEntryID: "window-layout:\(full.id.uuidString)") == nil,
            "another kind's id is not a room")

        let older = Room(name: "B", lastEnteredAt: Date(timeIntervalSince1970: 10))
        let newer = Room(name: "A", lastEnteredAt: Date(timeIntervalSince1970: 20))
        let never = Room(name: "0")
        expect(
            [older, never, newer].sorted(by: Room.enteredMoreRecently).map(\.name) == ["A", "B", "0"],
            "most recent first")
    }

    static func storeCRUD() {
        let suite = "tinycast-window-room-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return expect(false, "a scratch suite opens")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RoomStore(defaults: defaults)
        var changes = 0
        store.onChange = { _ in changes += 1 }
        expect(store.rooms.isEmpty, "a new store is empty")
        expectThrows(.noWindows, "a room needs a window") { try store.add(Room(name: "Empty")) }
        expectThrows(.emptyName, "a room needs a name") {
            try store.add(Room(name: "  ", windows: [window("a")]))
        }

        let design = try? store.add(Room(name: " Design ", windows: [window("figma", id: 1), window(" ")]))
        expect(design?.name == "Design" && design?.windows.count == 1, "names trim and empty windows drop")
        expectThrows(.duplicateName, "names are unique regardless of case") {
            try store.add(Room(name: "design", windows: [window("a")]))
        }
        let build = try? store.add(Room(name: "Build", windows: [window("editor", id: 2)]))
        expect(store.rooms.map(\.name) == ["Build", "Design"], "rooms keep name order")
        expect(changes == 2, "each commit reports once")
        expect(store.room(named: " BUILD ")?.id == build?.id, "rooms are found by name")
        expect(store.claimedWindowIDs(excluding: build?.id) == [1], "claimed IDs skip the room itself")

        guard let buildID = build?.id else { return expect(false, "the room was added") }
        store.setLayout(.columns, for: buildID, onDisplay: "DISPLAY")
        store.markEntered(id: buildID, at: Date(timeIntervalSince1970: 100))
        let reloaded = RoomStore(defaults: defaults)
        let mixed = #"[{"name":"Kept","layout":"someday","windows":[{"bundleID":"a"}]},{"windows":[]}]"#
        let mixedSuite = suite + "-mixed"
        if let other = UserDefaults(suiteName: mixedSuite) {
            other.set(Data(mixed.utf8), forKey: "windowRooms")
            let survivor = RoomStore(defaults: other).rooms
            expect(survivor.map(\.name) == ["Kept"], "one bad record never costs the library")
            expect(survivor.first?.layout == .auto, "an unknown layout resets to Auto")
            other.removePersistentDomain(forName: mixedSuite)
        }
        expect(
            reloaded.room(id: buildID)?.layout(onDisplay: "display") == .columns, "a display layout persists")
        expect(
            reloaded.room(id: buildID)?.lastEnteredAt == Date(timeIntervalSince1970: 100),
            "the last entry persists")

        expect(store.remove(id: buildID)?.name == "Build" && store.rooms.count == 1, "a room removes")
        let imported = store.replace(with: [
            Room(name: "One", windows: [window("a")]), Room(name: "one", windows: [window("b")]),
            Room(name: "Two", windows: [])
        ])
        expect(
            imported == 1 && store.rooms.map(\.name) == ["One"], "an import drops duplicates and empty rooms")
    }

    static func minimumSizeStore() {
        let suite = "tinycast-window-room-minimums-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return expect(false, "a scratch suite opens")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RoomMinimumSizeStore(defaults: defaults)
        expect(store.size(for: "app") == .zero, "an unknown app has no minimum")
        expect(store.learn(CGSize(width: 900, height: 0), for: "app"), "a refused width is learned")
        expect(!store.learn(CGSize(width: 800, height: 0), for: "app"), "a smaller size teaches nothing")
        expect(store.learn(CGSize(width: 0, height: 600), for: "app"), "each axis is learned on its own")
        expect(
            !store.learn(CGSize(width: CGFloat.infinity, height: 0), for: "app"),
            "a non-finite size is ignored")
        expect(
            RoomMinimumSizeStore(defaults: defaults).size(for: "app") == CGSize(width: 900, height: 600),
            "minimums persist")
    }

    static func parkingLedger() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-window-room-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("room-parking.json")

        let ledger = RoomParkingLedger(fileURL: url)
        let first = RoomParkingLedger.Entry(
            windowID: 5, bundleID: "chrome", title: "X", frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        expect(ledger.isEmpty, "a new ledger is empty")
        expect(ledger.record(first), "an entry is written before its window moves")
        var parkedAgain = first
        parkedAgain.frame = CGRect(x: 5000, y: 5000, width: 3, height: 4)
        expect(ledger.record(parkedAgain), "a second record writes too")
        expect(ledger.entry(for: 5) == first, "parking again keeps the first way back")
        expect(RoomParkingLedger(fileURL: url).entries == ledger.entries, "the ledger persists")

        ledger.keepOnly(bundleIDs: ["mail"])
        expect(ledger.isEmpty && RoomParkingLedger(fileURL: url).isEmpty, "a quit app's entries are dropped")
        _ = ledger.record(first)
        ledger.forget([5])
        expect(RoomParkingLedger(fileURL: url).isEmpty, "a window back home is forgotten")

        let unwritable = RoomParkingLedger(
            fileURL: directory.appendingPathComponent("missing/room-parking.json"))
        expect(!unwritable.record(first), "a ledger that cannot be written refuses the move")

        try? Data("{ not json".utf8).write(to: url)
        expect(RoomParkingLedger(fileURL: url).isEmpty, "an unreadable ledger starts over")
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        expect(
            kept.filter { $0.hasPrefix("room-parking.unreadable-") }.count == 1,
            "the unreadable ledger is kept aside")
    }
}
