import AppKit
import SwiftUI

/// A thin auto-hiding SwiftUI overlay scrollbar (hairline thumb while scrolling plus a hover-reveal rail), with all pointer handling isolated in the AppKit `ScrollbarInteraction` view to sidestep SwiftUI/AppKit event-routing gaps.
struct ThinScrollbar: ViewModifier {
    private struct Metrics: Equatable {
        /// Raw `contentOffset.y`; with `safeAreaInset` bars it rests at `-insetTop`, so normalize by `insetTop` before mapping to a track fraction.
        var offset: CGFloat = 0
        var insetTop: CGFloat = 0
        var content: CGFloat = 0
        var viewport: CGFloat = 0
        var scrollable: Bool { content > viewport + 1 }
    }

    // Interaction signals — kept separate so each source of "show the bar" is independent.
    @State private var isScrolling = false
    @State private var isHoveringTrack = false
    /// Mirrors the AppKit-side thumb drag (`ScrollbarInteraction` owns the actual drag state).
    @State private var isDragging = false

    @State private var metrics = Metrics()
    /// Instantaneous "pointer is in the trailing hover zone" mirror, for edge-transition detection.
    @State private var inZone = false
    @State private var scrollStop: Task<Void, Never>?
    @State private var hoverExit: Task<Void, Never>?

    // Knob/rail geometry: thin at rest, fatter on hover/drag — like the macOS overlay knob.
    private let thinWidth: CGFloat = 6
    private let expandedWidth: CGFloat = 10
    private let inset: CGFloat = 3
    private let minThumb: CGFloat = 28
    private let hoverZone: CGFloat = 16  // trailing strip that reveals the rail; wider than the thumb

    // Animation curves shared across the interaction transitions.
    private let fadeCurve: Animation = .easeOut(duration: 0.18)
    private let morphCurve: Animation = .spring(response: 0.28, dampingFraction: 0.85)

    private var visible: Bool { isScrolling || isHoveringTrack || isDragging }
    private var expanded: Bool { isHoveringTrack || isDragging }

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)  // drop the native scroller (and its flash) entirely
            // Geometry drives the thumb's size/position, never its visibility.
            .onScrollGeometryChange(for: Metrics.self) { geo in
                Metrics(
                    offset: geo.contentOffset.y,
                    insetTop: geo.contentInsets.top,
                    content: geo.contentSize.height,
                    viewport: geo.containerSize.height
                )
            } action: { _, new in
                metrics = new
            }
            // Scrolling reveals the thumb (not the rail) and re-hides a beat after it stops; a thumb drag has no scroll phase, so its own handlers own visibility.
            .onScrollPhaseChange { _, phase in
                guard !isDragging else { return }
                phase == .idle ? scheduleScrollStop() : beganScrolling()
            }
            .overlay(alignment: .topTrailing) { bar }
            // One tracking view over the whole trailing strip owns all pointer handling: transparent except over the thumb, where it takes the drag and forwards wheel events, and never flickers the rail the way a content-level hover did.
            .overlay {
                ScrollbarInteraction(
                    edgeWidth: hoverZone,
                    inset: inset,
                    thumbY: thumbOffset,
                    thumbHeight: thumbHeight,
                    thumbGrabbable: metrics.scrollable && visible,
                    railActive: metrics.scrollable && expanded,
                    onZoneChange: updateZone,
                    onDragChange: dragChanged
                )
            }
    }

    @ViewBuilder private var bar: some View {
        if metrics.scrollable {
            ZStack(alignment: .top) {
                // Rail: a faint full-height track, present only while hovering/dragging.
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: expandedWidth, height: track)
                    .offset(y: inset)
                    .opacity(expanded ? 1 : 0)

                // Thumb: proportional knob, thin at rest and fatter when expanded.
                Capsule()
                    .fill(Color.primary.opacity(isDragging ? 0.5 : (expanded ? 0.42 : 0.30)))
                    .frame(width: expanded ? expandedWidth : thinWidth, height: thumbHeight)
                    .frame(width: expandedWidth)
                    .offset(y: thumbOffset)
                    .opacity(visible ? 1 : 0)
            }
            .frame(width: expandedWidth)
            .padding(.trailing, inset)
            // Purely visual; ScrollbarInteraction above owns clicks, drags and wheel routing.
            .allowsHitTesting(false)
        }
    }

    /// Usable vertical travel, inset a little from the top and bottom edges.
    private var track: CGFloat { max(0, metrics.viewport - inset * 2) }

    private var thumbHeight: CGFloat {
        guard metrics.content > 0 else { return minThumb }
        return min(track, max(minThumb, track * metrics.viewport / metrics.content))
    }

    private var thumbOffset: CGFloat {
        let maxScroll = max(0, metrics.content - metrics.viewport)
        guard maxScroll > 0 else { return inset }
        let fraction = min(1, max(0, (metrics.offset + metrics.insetTop) / maxScroll))
        return inset + fraction * (track - thumbHeight)
    }

    // MARK: - Scroll signal

    private func beganScrolling() {
        scrollStop?.cancel()
        withAnimation(fadeCurve) { isScrolling = true }
    }

    /// Fade the thumb out a beat after scrolling stops, like the native overlay scroller.
    private func scheduleScrollStop() {
        scrollStop?.cancel()
        scrollStop = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(fadeCurve) { isScrolling = false }
        }
    }

    // MARK: - Drag signal

    private func dragChanged(_ dragging: Bool) {
        withAnimation(morphCurve) { isDragging = dragging }
        if dragging {
            scrollStop?.cancel()
        } else {
            // Linger like a normal scroll, then fade unless still hovering/scrolling.
            isScrolling = true
            scheduleScrollStop()
        }
    }

    // MARK: - Hover signal

    /// Called on every pointer move; acts only on the in-zone ⇄ out-of-zone *transition*.
    private func updateZone(_ nowInZone: Bool) {
        guard nowInZone != inZone else { return }
        inZone = nowInZone
        if nowInZone {
            hoverExit?.cancel()
            withAnimation(morphCurve) { isHoveringTrack = true }
        } else {
            scheduleHoverExit()
        }
    }

    /// Leaving the zone collapses the rail after a short delay, so brief exits don't flicker it.
    private func scheduleHoverExit() {
        hoverExit?.cancel()
        hoverExit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation(morphCurve) { isHoveringTrack = false }
        }
    }
}

extension View {
    /// Attach to a `ScrollView` for a thin SwiftUI scrollbar that appears only while scrolling.
    func thinScrollbar() -> some View {
        modifier(ThinScrollbar())
    }

    /// Attach *inside* a `ScrollView` (on its content) to remove the native scrollers so only our `thinScrollbar` shows.
    func hideNativeScrollers() -> some View {
        background(NativeScrollerHider().frame(width: 0, height: 0))
    }
}

/// Forces the backing `NSScrollView` to a hidden `.overlay` scroller (removing the always-on legacy widget and its reserved gutter), re-asserting it on `preferredScrollerStyleDidChangeNotification` since macOS otherwise resets it.
private struct NativeScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HiderView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HiderView)?.applyOverlayStyle()
    }

    private final class HiderView: NSView {
        private var retriesLeft = 10
        private var styleChangeObserver: NotificationToken?

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
        override init(frame: NSRect) { super.init(frame: frame) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopObservingStyleChanges()
                return
            }
            startObservingStyleChanges()
            retriesLeft = 10  // fresh hierarchy on (re)attach — allow the splice a few ticks again
            applyOverlayStyle()
        }

        private func startObservingStyleChanges() {
            guard styleChangeObserver == nil else { return }
            let token = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                // Re-assert on the next tick, after AppKit's own handler has reset the style.
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
            styleChangeObserver = NotificationToken(token, center: .default)
        }

        private func stopObservingStyleChanges() {
            styleChangeObserver = nil
        }

        func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView else {
                // Not yet spliced into the scroll view's hierarchy; retry next tick, bounded so a view that never lands in one can't busy-loop the main thread.
                guard retriesLeft > 0 else { return }
                retriesLeft -= 1
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            // Idempotent: bail once already in the target state so re-runs don't churn layout.
            guard
                scrollView.scrollerStyle != .overlay
                    || scrollView.hasVerticalScroller
                    || scrollView.hasHorizontalScroller
            else { return }
            scrollView.scrollerStyle = .overlay  // float over content — reserves no layout width
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            // Reclaim the trailing gutter a legacy scroller was reserving, on this same layout pass.
            scrollView.tile()
        }
    }
}

/// The single AppKit view (a sibling of the backing `NSScrollView`) that owns hover tracking, thumb drag/track-click, and wheel forwarding, driving the clip view directly since SwiftUI's scroll APIs and responder chain don't reach it reliably.
private struct ScrollbarInteraction: NSViewRepresentable {
    let edgeWidth: CGFloat
    let inset: CGFloat
    let thumbY: CGFloat
    let thumbHeight: CGFloat
    let thumbGrabbable: Bool
    let railActive: Bool
    let onZoneChange: @MainActor (Bool) -> Void
    let onDragChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        InteractionView(onZoneChange: onZoneChange, onDragChange: onDragChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? InteractionView else { return }
        view.edgeWidth = edgeWidth
        view.inset = inset
        view.thumbY = thumbY
        view.thumbHeight = thumbHeight
        view.thumbGrabbable = thumbGrabbable
        view.railActive = railActive
        view.onZoneChange = onZoneChange
        view.onDragChange = onDragChange
    }

    private final class InteractionView: NSView {
        var edgeWidth: CGFloat = 0
        var inset: CGFloat = 0
        var thumbY: CGFloat = 0
        var thumbHeight: CGFloat = 0
        var thumbGrabbable = false
        var railActive = false
        var onZoneChange: @MainActor (Bool) -> Void
        var onDragChange: @MainActor (Bool) -> Void

        private var lastInZone = false
        /// Pointer y + content offset captured at `mouseDown`; non-nil only while dragging the thumb.
        private var dragStart: (pointerY: CGFloat, offset: CGFloat)?
        private weak var scrollView: NSScrollView?

        init(
            onZoneChange: @escaping @MainActor (Bool) -> Void,
            onDragChange: @escaping @MainActor (Bool) -> Void
        ) {
            self.onZoneChange = onZoneChange
            self.onDragChange = onDragChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // Match SwiftUI's top-down coordinates so `thumbY` can be used directly.
        override var isFlipped: Bool { true }

        // MARK: Hit testing

        /// Opaque over the thumb's grab strip (and the whole trailing strip while the rail is expanded), transparent elsewhere so content clicks and wheel events fall through.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview else { return nil }
            let p = convert(point, from: superview)
            if grabRect.contains(p) { return self }
            if railActive && p.x >= bounds.width - edgeWidth { return self }
            return nil
        }

        /// Full trailing-strip width at the thumb's vertical span, so the hairline thumb is comfortably grabbable.
        private var grabRect: CGRect {
            guard thumbGrabbable else { return .null }
            return CGRect(
                x: bounds.width - edgeWidth, y: thumbY, width: edgeWidth, height: thumbHeight)
        }

        // MARK: Wheel routing

        /// Wheel events only reach us over the bar; hand them to the sibling scroll view the responder chain would otherwise bypass.
        override func scrollWheel(with event: NSEvent) {
            if let target = targetScrollView() {
                target.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
        }

        // MARK: Thumb drag & track click

        override func mouseDown(with event: NSEvent) {
            guard let target = targetScrollView() else { return }
            let p = convert(event.locationInWindow, from: nil)
            // Track click outside the thumb's span jumps the thumb to center on the pointer, then continues as a drag.
            if !(thumbY...(thumbY + thumbHeight)).contains(p.y) {
                jumpThumb(toPointerY: p.y, in: target)
            }
            dragStart = (p.y, target.contentView.bounds.origin.y)
            onDragChange(true)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart, let target = targetScrollView() else { return }
            let (minOffset, maxOffset) = offsetRange(of: target.contentView)
            let travel = trackTravel
            guard maxOffset > minOffset, travel > 0 else { return }
            let p = convert(event.locationInWindow, from: nil)
            // Map thumb travel back to content offset, anchored at mouse-down so clamped over-drags don't drift.
            let offset =
                dragStart.offset + (p.y - dragStart.pointerY) / travel * (maxOffset - minOffset)
            scroll(target, toOffset: min(maxOffset, max(minOffset, offset)))
        }

        override func mouseUp(with event: NSEvent) {
            guard dragStart != nil else { return }
            dragStart = nil
            onDragChange(false)
        }

        /// Thumb travel in track points: the rail's height minus the thumb.
        private var trackTravel: CGFloat { (bounds.height - inset * 2) - thumbHeight }

        /// Scroll so the thumb's center lands on the given pointer y (clamped to the track).
        private func jumpThumb(toPointerY y: CGFloat, in target: NSScrollView) {
            let (minOffset, maxOffset) = offsetRange(of: target.contentView)
            let travel = trackTravel
            guard maxOffset > minOffset, travel > 0 else { return }
            let thumbTop = min(inset + travel, max(inset, y - thumbHeight / 2))
            let fraction = (thumbTop - inset) / travel
            scroll(target, toOffset: minOffset + fraction * (maxOffset - minOffset))
        }

        /// The clip view's legal `bounds.origin.y` range via AppKit's own constraint logic, which keeps the drag inset-correct where a raw `[0, content − viewport]` clamp isn't.
        private func offsetRange(of clip: NSClipView) -> (min: CGFloat, max: CGFloat) {
            var probe = clip.bounds
            probe.origin.y = -1_000_000_000
            let minY = clip.constrainBoundsRect(probe).origin.y
            probe.origin.y = 1_000_000_000
            let maxY = clip.constrainBoundsRect(probe).origin.y
            return (minY, maxY)
        }

        private func scroll(_ target: NSScrollView, toOffset y: CGFloat) {
            let clip = target.contentView
            var origin = clip.bounds.origin
            origin.y = y
            clip.scroll(to: origin)
            target.reflectScrolledClipView(clip)
        }

        /// The backing `NSScrollView`, found by walking up to the nearest scroll view in a sibling subtree (since `enclosingScrollView` can't reach a sibling) and cached weakly.
        private func targetScrollView() -> NSScrollView? {
            if let scrollView, scrollView.window === window { return scrollView }
            var branch: NSView = self
            var node = superview
            while let ancestor = node {
                if let found = Self.firstScrollView(under: ancestor, excluding: branch) {
                    scrollView = found
                    return found
                }
                branch = ancestor
                node = ancestor.superview
            }
            return nil
        }

        private static func firstScrollView(under view: NSView, excluding: NSView?) -> NSScrollView?
        {
            for sub in view.subviews where sub !== excluding {
                if let scroll = sub as? NSScrollView { return scroll }
                if let scroll = firstScrollView(under: sub, excluding: nil) { return scroll }
            }
            return nil
        }

        // MARK: Hover tracking

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            // `.inVisibleRect` pins the area to the resizing bounds; `.activeAlways` so hover reveals the rail in non-key windows too.
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [
                        .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect,
                    ],
                    owner: self
                ))
        }

        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { update(inZone: false) }

        private func report(_ event: NSEvent) {
            let x = convert(event.locationInWindow, from: nil).x
            update(inZone: x >= bounds.width - edgeWidth)
        }

        /// Fire the callback only on a zone transition, so a stream of `mouseMoved`s stays cheap.
        private func update(inZone: Bool) {
            guard inZone != lastInZone else { return }
            lastInZone = inZone
            onZoneChange(inZone)
        }
    }
}
