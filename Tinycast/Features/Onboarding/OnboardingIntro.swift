import AppKit
import SwiftUI

@MainActor
final class OnboardingIntro {
    private let panel: NSPanel
    private let reveal = Reveal()

    init(on screen: NSScreen, landing: CGPoint) {
        panel = NSPanel(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false, screen: screen)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let position = CGPoint(x: landing.x - screen.frame.minX, y: screen.frame.maxY - landing.y)
        let hosting = NSHostingController(
            rootView: Backdrop(startedAt: .now, landing: position, reveal: reveal))
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
    }

    func fadeBehind(_ wizard: NSWindow) {
        wizard.level = panel.level
        wizard.orderFrontRegardless()
        panel.order(.below, relativeTo: wizard.windowNumber)
        let delay = Theme.Onboarding.revealBackdropDelay
        withAnimation(.easeInOut(duration: Theme.Onboarding.revealDuration - delay).delay(delay)) {
            reveal.fadesBackdrop = true
        }
    }

    func close() {
        panel.close()
    }

    func hideMark() {
        reveal.showsMark = false
    }

    @Observable
    fileprivate final class Reveal {
        var fadesBackdrop = false
        var showsMark = true
    }

    private struct Backdrop: View {
        private typealias Intro = Theme.Onboarding.Intro

        let startedAt: Date
        let landing: CGPoint
        let reveal: Reveal

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let diagonal = hypot(size.width, size.height)
                TimelineView(
                    .animation(minimumInterval: Intro.frameInterval, paused: reveal.fadesBackdrop)
                ) { timeline in
                    artwork(
                        at: reveal.fadesBackdrop
                            ? Intro.duration
                            : timeline.date.timeIntervalSince(startedAt),
                        size: size, diagonal: diagonal)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }

        private func artwork(at elapsed: Double, size: CGSize, diagonal: CGFloat) -> some View {
            let dimPhase = progress(elapsed, from: 0, over: Intro.dimDuration)
            let dim = 1 - pow(1 - dimPhase, 5) * (1 + 5 * dimPhase)
            let violet = Intro.violetCurve.value(
                at: progress(elapsed, from: Intro.violetDelay, over: Intro.violetDuration))
            let zoom = ease(progress(elapsed, from: Intro.zoomDelay, over: Intro.zoomDuration))
            let mark = ease(progress(zoom, from: Intro.markFadeStart, over: Intro.markFadeLength))
            let liftStart = Intro.zoomDelay + Intro.zoomDuration + Intro.liftDelay
            let lift = Intro.liftCurve.value(
                at: progress(elapsed, from: liftStart, over: Intro.duration - liftStart))
            let height = Intro.markSize + (Theme.Onboarding.markSize - Intro.markSize) * lift
            let scale = pow(diagonal * Intro.zoomReach / Intro.markSize, 1 - zoom)
            return ZStack {
                Theme.Onboarding.night.opacity(dim * Intro.dimOpacity)
                    .opacity(reveal.fadesBackdrop ? 0 : 1)
                if mark < 1 {
                    let texture = violetTexture(radius: diagonal * Intro.violetRadius)
                        .opacity(violet * (1 - mark))
                    if zoom > 0 {
                        texture.mask {
                            BrandArtwork.Mark.silhouette.frame(width: height, height: height)
                                .scaleEffect(scale)
                        }
                    } else {
                        texture
                    }
                }
                if mark > 0, reveal.showsMark {
                    BrandArtwork.Mark(height: height)
                        .scaleEffect(scale)
                        .position(
                            x: size.width / 2 + (landing.x - size.width / 2) * lift,
                            y: size.height / 2 + (landing.y - size.height / 2) * lift
                        )
                        .opacity(mark)
                }
            }
        }

        private func violetTexture(radius: CGFloat) -> some View {
            ZStack {
                RadialGradient(
                    colors: [
                        Theme.Colors.brand.opacity(Intro.violetCenterOpacity),
                        Theme.Colors.brand.opacity(Intro.violetMidOpacity), .clear
                    ],
                    center: .center, startRadius: 0, endRadius: radius)
                BrandArtwork.Grain().opacity(Intro.grainOpacity)
            }
        }

        private func progress(_ value: Double, from start: Double, over length: Double) -> Double {
            min(max((value - start) / length, 0), 1)
        }

        private func ease(_ progress: Double) -> Double {
            progress * progress * progress * (progress * (6 * progress - 15) + 10)
        }
    }
}
