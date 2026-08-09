import CoreGraphics
import Foundation

/// Pure geometry, entirely in AX space. See docs/features/window-management.md#coordinate-space.
enum WindowLayout {
    /// A display, already converted to AX space by the caller.
    struct Screen: Equatable, Sendable {
        /// `CGDirectDisplayID` in the app; any stable value in tests.
        let id: Int
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// Where a window that refused to shrink sits in its slot; a left half stays left-aligned.
    struct Anchor: Equatable, Sendable {
        /// `min` is left / top, since +Y points down here.
        enum Axis: Equatable, Sendable { case min, center, max }

        var horizontal: Axis
        var vertical: Axis

        static let topLeading = Anchor(horizontal: .min, vertical: .min)
        static let centered = Anchor(horizontal: .center, vertical: .center)

        /// Places `size` inside `slot` per the anchor, when an app clamped itself larger.
        func place(_ size: CGSize, in slot: CGRect) -> CGRect {
            func origin(
                _ axis: Axis, slotMin: CGFloat, slotLength: CGFloat, length: CGFloat
            )
                -> CGFloat
            {
                switch axis {
                case .min: return slotMin
                case .center: return slotMin + (slotLength - length) / 2
                case .max: return slotMin + slotLength - length
                }
            }
            return CGRect(
                x: origin(
                    horizontal, slotMin: slot.minX, slotLength: slot.width, length: size.width),
                y: origin(vertical, slotMin: slot.minY, slotLength: slot.height, length: size.height),
                width: size.width, height: size.height)
        }
    }

    struct Input: Equatable, Sendable {
        var command: WindowCommand.ID
        var windowFrame: CGRect
        var screens: [Screen]
        var gap: CGFloat
        /// Cycle position, supplied by `WindowActionMemory` so the geometry itself stays stateless.
        var step: Int
        /// Read only by `.restore`.
        var restoreFrame: CGRect?
        /// The tile that last placed this window, so a display move re-derives rather than scales.
        var lastTileCommand: WindowCommand.ID?

        init(
            command: WindowCommand.ID, windowFrame: CGRect, screens: [Screen], gap: CGFloat = 0,
            step: Int = 0, restoreFrame: CGRect? = nil, lastTileCommand: WindowCommand.ID? = nil
        ) {
            self.command = command
            self.windowFrame = windowFrame
            self.screens = screens
            self.gap = gap
            self.step = step
            self.restoreFrame = restoreFrame
            self.lastTileCommand = lastTileCommand
        }
    }

    struct Placement: Equatable, Sendable {
        var frame: CGRect
        var screenID: Int
        var anchor: Anchor
        var resizes: Bool
    }

    // MARK: - Tuning

    /// Make Larger / Make Smaller and the four nudges all step by this fraction of the screen.
    private static let stepFraction: CGFloat = 0.05
    private static let almostMaximizeFraction: CGFloat = 0.9
    private static let reasonableSizeFraction: CGFloat = 0.6
    /// Hard ceiling, in points: 60% of a 5K display is not a reasonable size for a window.
    private static let reasonableSizeMax = CGSize(width: 1025, height: 900)

    // MARK: - Entry point

    /// The target placement, or `nil` when the mover should write nothing at all.
    static func placement(for input: Input) -> Placement? {
        guard let command = WindowCommandCatalog.command(id: input.command),
            command.kind != .fullscreen,
            !input.screens.isEmpty
        else { return nil }

        if command.kind == .restore { return restorePlacement(input) }

        guard let host = screen(containing: input.windowFrame, in: input.screens),
            host.visibleFrame.width > 0, host.visibleFrame.height > 0
        else { return nil }

        let gap = sanitizedGap(input.gap, in: host.visibleFrame)

        switch input.command {
        case .nextDisplay, .previousDisplay:
            return displayPlacement(input, from: host, gap: gap)
        default:
            break
        }

        // Non-cycling commands ignore the step, so a stale cycle position can't leak in.
        let step = command.cyclesOnRepeat ? normalizedStep(input.step) : 0

        if let fractions = tileFractions(input.command, step: step) {
            let frame = tile(
                host.visibleFrame, x0: fractions.x0, x1: fractions.x1, y0: fractions.y0,
                y1: fractions.y1, gap: gap)
            return Placement(
                frame: frame, screenID: host.id, anchor: fractions.anchor, resizes: true)
        }

        let canvas = canvas(host.visibleFrame, gap: gap)
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let current = input.windowFrame

        switch input.command {
        case .maximize:
            return Placement(
                frame: canvas, screenID: host.id, anchor: .topLeading, resizes: true)

        case .almostMaximize:
            let size = CGSize(
                width: canvas.width * almostMaximizeFraction,
                height: canvas.height * almostMaximizeFraction)
            return Placement(
                frame: rounded(Anchor.centered.place(size, in: canvas)), screenID: host.id,
                anchor: .centered, resizes: true)

        // The cap makes this display-independent; 0.6 < 1 stays inside the canvas unclamped.
        case .reasonableSize:
            let size = CGSize(
                width: min(canvas.width * reasonableSizeFraction, reasonableSizeMax.width),
                height: min(canvas.height * reasonableSizeFraction, reasonableSizeMax.height))
            return Placement(
                frame: rounded(Anchor.centered.place(size, in: canvas)), screenID: host.id,
                anchor: .centered, resizes: true)

        // Both keep the untouched axis, but clamp it, so an off-display window comes back.
        case .maximizeHeight:
            let frame = CGRect(
                x: current.minX, y: canvas.minY, width: current.width, height: canvas.height)
            return Placement(
                frame: rounded(clamped(frame, into: canvas)), screenID: host.id,
                anchor: .topLeading, resizes: true)

        case .maximizeWidth:
            let frame = CGRect(
                x: canvas.minX, y: current.minY, width: canvas.width, height: current.height)
            return Placement(
                frame: rounded(clamped(frame, into: canvas)), screenID: host.id,
                anchor: .topLeading, resizes: true)

        case .center:
            let size = CGSize(
                width: min(current.width, canvas.width), height: min(current.height, canvas.height))
            return Placement(
                frame: rounded(Anchor.centered.place(size, in: canvas)), screenID: host.id,
                anchor: .centered, resizes: true)

        case .makeLarger, .makeSmaller:
            return Placement(
                frame: resized(current, in: canvas, larger: input.command == .makeLarger),
                screenID: host.id, anchor: .centered, resizes: true)

        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return Placement(
                frame: nudged(current, in: canvas, command: input.command), screenID: host.id,
                anchor: .topLeading, resizes: false)

        default:
            return nil
        }
    }

    // MARK: - Screens

    /// The display a window lives on: most overlapping area wins, else the one holding its centre.
    static func screen(containing frame: CGRect, in screens: [Screen]) -> Screen? {
        guard !screens.isEmpty else { return nil }
        var best: (screen: Screen, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        if let best, best.area > 0 { return best.screen }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return screens.first { $0.frame.contains(centre) } ?? screens.first
    }

    /// Left-to-right, then top-to-bottom: stable however `NSScreen.screens` is sorted.
    static func ordered(_ screens: [Screen]) -> [Screen] {
        screens.sorted {
            $0.frame.minX != $1.frame.minX
                ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
    }

    private static func displayPlacement(
        _ input: Input, from host: Screen, gap: CGFloat
    )
        -> Placement?
    {
        let ordered = ordered(input.screens)
        // A single display makes both commands a quiet no-op rather than a pointless re-place.
        guard ordered.count > 1, let index = ordered.firstIndex(where: { $0.id == host.id })
        else { return nil }
        let offset = input.command == .nextDisplay ? 1 : -1
        let destination = ordered[(index + offset + ordered.count) % ordered.count]
        let frame = moved(
            input.windowFrame, from: host, to: destination, gap: gap,
            lastTile: input.lastTileCommand)
        return Placement(
            frame: frame, screenID: destination.id, anchor: .centered, resizes: true)
    }

    private static func moved(
        _ frame: CGRect, from: Screen, to: Screen, gap: CGFloat, lastTile: WindowCommand.ID?
    ) -> CGRect {
        // Exactness beats proportion: an untouched tile re-derives instead of being scaled.
        if let lastTile, let fractions = tileFractions(lastTile, step: 0) {
            return tile(
                to.visibleFrame, x0: fractions.x0, x1: fractions.x1, y0: fractions.y0,
                y1: fractions.y1, gap: sanitizedGap(gap, in: to.visibleFrame))
        }
        let source = from.visibleFrame
        let target = to.visibleFrame
        guard source.width > 0, source.height > 0 else { return frame }
        // Relative to `visibleFrame`, so a window tucked against the Dock lands tucked again.
        let relativeX = (frame.minX - source.minX) / source.width
        let relativeY = (frame.minY - source.minY) / source.height
        let scaled = CGRect(
            x: target.minX + relativeX * target.width,
            y: target.minY + relativeY * target.height,
            width: min(target.width, frame.width / source.width * target.width),
            height: min(target.height, frame.height / source.height * target.height))
        return rounded(clamped(scaled, into: target))
    }

    // MARK: - Restore

    private static func restorePlacement(_ input: Input) -> Placement? {
        guard let restoreFrame = input.restoreFrame,
            let host = screen(containing: restoreFrame, in: input.screens)
        else { return nil }
        let overlap = host.visibleFrame.intersection(restoreFrame)
        // A restore point stranded off every display comes back centred, not unreachable.
        let stranded = overlap.isNull || overlap.width < 40 || overlap.height < 40
        let frame =
            stranded
            ? rounded(
                clamped(
                    Anchor.centered.place(restoreFrame.size, in: host.visibleFrame),
                    into: host.visibleFrame))
            : restoreFrame
        return Placement(frame: frame, screenID: host.id, anchor: .centered, resizes: true)
    }

    // MARK: - Tiles

    private struct Fractions {
        var x0: CGFloat
        var x1: CGFloat
        var y0: CGFloat
        var y1: CGFloat
        var anchor: Anchor
    }

    private static let oneThird: CGFloat = 1.0 / 3.0
    private static let twoThirds: CGFloat = 2.0 / 3.0

    /// Fractional bounds of a tile command, or `nil`; `step` matters only for the four halves.
    private static func tileFractions(_ command: WindowCommand.ID, step: Int) -> Fractions? {
        let cycle: [CGFloat] = [0.5, oneThird, twoThirds]
        let position = cycle[normalizedStep(step)]
        switch command {
        case .leftHalf:
            return Fractions(x0: 0, x1: position, y0: 0, y1: 1, anchor: .topLeading)
        case .rightHalf:
            return Fractions(
                x0: 1 - position, x1: 1, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .max, vertical: .min))
        case .topHalf:
            return Fractions(x0: 0, x1: 1, y0: 0, y1: position, anchor: .topLeading)
        case .bottomHalf:
            return Fractions(
                x0: 0, x1: 1, y0: 1 - position, y1: 1,
                anchor: Anchor(horizontal: .min, vertical: .max))

        case .topLeftQuarter:
            return Fractions(x0: 0, x1: 0.5, y0: 0, y1: 0.5, anchor: .topLeading)
        case .topRightQuarter:
            return Fractions(
                x0: 0.5, x1: 1, y0: 0, y1: 0.5, anchor: Anchor(horizontal: .max, vertical: .min))
        case .bottomLeftQuarter:
            return Fractions(
                x0: 0, x1: 0.5, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .min, vertical: .max))
        case .bottomRightQuarter:
            return Fractions(
                x0: 0.5, x1: 1, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .max, vertical: .max))

        case .firstThird:
            return Fractions(x0: 0, x1: oneThird, y0: 0, y1: 1, anchor: .topLeading)
        case .centerThird:
            return Fractions(
                x0: oneThird, x1: twoThirds, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .center, vertical: .min))
        case .lastThird:
            return Fractions(
                x0: twoThirds, x1: 1, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .max, vertical: .min))
        case .firstTwoThirds:
            return Fractions(x0: 0, x1: twoThirds, y0: 0, y1: 1, anchor: .topLeading)
        case .lastTwoThirds:
            return Fractions(
                x0: oneThird, x1: 1, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .max, vertical: .min))

        // Half the screen's area, so it reads as the family sibling of Center Third.
        case .centerHalf:
            return Fractions(
                x0: 0.25, x1: 0.75, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .center, vertical: .min))

        default:
            return nil
        }
    }

    /// Whether the command lands on the fractional grid, which a display move can re-derive.
    static func isTileCommand(_ command: WindowCommand.ID) -> Bool {
        tileFractions(command, step: 0) != nil
    }

    /// A tile from fractional bounds of `visible`. See docs/features/window-management.md#geometry.
    static func tile(
        _ visible: CGRect, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, gap: CGFloat
    ) -> CGRect {
        let left = visible.minX + x0 * visible.width + (x0 == 0 ? gap : gap / 2)
        let right = visible.minX + x1 * visible.width - (x1 == 1 ? gap : gap / 2)
        let top = visible.minY + y0 * visible.height + (y0 == 0 ? gap : gap / 2)
        let bottom = visible.minY + y1 * visible.height - (y1 == 1 ? gap : gap / 2)
        return rounded(
            CGRect(
                x: left, y: top, width: max(1, right - left), height: max(1, bottom - top)))
    }

    /// The box free-floating commands work in: full gap on every side, not the grid's halves.
    static func canvas(_ visible: CGRect, gap: CGFloat) -> CGRect {
        rounded(visible.insetBy(dx: gap, dy: gap))
    }

    // MARK: - Sizing

    /// Never let repeated shrinking collapse a window to nothing.
    private static func minimumSize(in canvas: CGRect) -> CGSize {
        CGSize(
            width: min(canvas.width, max(200, canvas.width * 0.15)),
            height: min(canvas.height, max(150, canvas.height * 0.15)))
    }

    /// Even, so each edge moves a whole point and the two commands stay exactly invertible.
    private static func evenStep(_ dimension: CGFloat) -> CGFloat {
        max(2, (dimension * stepFraction / 2).rounded() * 2)
    }

    /// About the centre, by a fraction of the screen. docs/features/window-management.md#geometry
    private static func resized(_ frame: CGRect, in canvas: CGRect, larger: Bool) -> CGRect {
        let direction: CGFloat = larger ? 1 : -1
        let floorSize = minimumSize(in: canvas)
        let width = min(
            canvas.width, max(floorSize.width, frame.width + direction * evenStep(canvas.width)))
        let height = min(
            canvas.height, max(floorSize.height, frame.height + direction * evenStep(canvas.height)))
        let centred = CGRect(
            x: frame.minX - (width - frame.width) / 2, y: frame.minY - (height - frame.height) / 2,
            width: width, height: height)
        return rounded(clamped(centred, into: canvas))
    }

    private static func nudged(
        _ frame: CGRect, in canvas: CGRect, command: WindowCommand.ID
    )
        -> CGRect
    {
        let dx = (canvas.width * stepFraction).rounded()
        let dy = (canvas.height * stepFraction).rounded()
        var moved = frame
        switch command {
        case .moveLeft: moved.origin.x -= dx
        case .moveRight: moved.origin.x += dx
        case .moveUp: moved.origin.y -= dy
        case .moveDown: moved.origin.y += dy
        default: break
        }
        return rounded(clamped(moved, into: canvas))
    }

    // MARK: - Primitives

    /// Rounds the four edges, so two tiles sharing a boundary round it identically.
    static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded()
        let maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// Keeps `frame` inside `box` unresized; an oversized window pins its leading edge.
    static func clamped(_ frame: CGRect, into box: CGRect) -> CGRect {
        let x = min(max(frame.minX, box.minX), max(box.minX, box.maxX - frame.width))
        let y = min(max(frame.minY, box.minY), max(box.minY, box.maxY - frame.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// A gap wider than the screen would produce zero-width tiles, so cap it before any math.
    static func sanitizedGap(_ gap: CGFloat, in visible: CGRect) -> CGFloat {
        guard gap.isFinite, gap > 0, visible.width > 0, visible.height > 0 else { return 0 }
        return min(gap, min(visible.width, visible.height) / 10)
    }

    private static func normalizedStep(_ step: Int) -> Int { ((step % 3) + 3) % 3 }
}
