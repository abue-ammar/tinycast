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
            rootView: Scene(startedAt: .now, landing: position, reveal: reveal))
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

    private struct Scene: View {
        private static let violetCurve = UnitCurve.bezier(
            startControlPoint: .init(x: 0.16, y: 0), endControlPoint: .init(x: 0.35, y: 1))
        private static let liftCurve = UnitCurve.bezier(
            startControlPoint: .init(x: 0.72, y: 0), endControlPoint: .init(x: 0.28, y: 1))

        let startedAt: Date
        let landing: CGPoint
        let reveal: Reveal

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let diagonal = hypot(size.width, size.height)
                TimelineView(
                    .animation(minimumInterval: 1.0 / 60, paused: reveal.fadesBackdrop)
                ) { timeline in
                    artwork(
                        at: reveal.fadesBackdrop
                            ? Theme.Onboarding.introDuration
                            : timeline.date.timeIntervalSince(startedAt),
                        size: size, diagonal: diagonal)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }

        private func artwork(at elapsed: Double, size: CGSize, diagonal: CGFloat) -> some View {
            let dimPhase = min(max(elapsed / 1.30, 0), 1)
            let dim = 1 - pow(1 - dimPhase, 5) * (1 + 5 * dimPhase)
            let violetPhase = min(max((elapsed - 0.14) / 1.32, 0), 1)
            let violet = Self.violetCurve.value(at: violetPhase)
            let zoomStart = 0.99
            let zoomDuration = 1.41
            let zoom = ease((elapsed - zoomStart) / zoomDuration)
            let mark = ease((zoom - 0.48) / 0.44)
            let liftStart = zoomStart + zoomDuration + 0.09
            let liftPhase = min(
                max((elapsed - liftStart) / (Theme.Onboarding.introDuration - liftStart), 0), 1)
            let lift = Self.liftCurve.value(at: liftPhase)
            let introHeight = Theme.Onboarding.introMarkSize
            let height = introHeight + (Theme.Onboarding.markSize - introHeight) * lift
            let scale = pow(diagonal * 4.4 / introHeight, 1 - zoom)
            return ZStack {
                Theme.Onboarding.night.opacity(dim * 0.94)
                    .opacity(reveal.fadesBackdrop ? 0 : 1)
                if mark < 1 {
                    let texture = violetTexture(radius: diagonal * 0.57).opacity(violet * (1 - mark))
                    if zoom > 0 {
                        texture.mask {
                            OnboardingArtwork.Mark.silhouette.frame(width: height, height: height)
                                .scaleEffect(scale)
                        }
                    } else {
                        texture
                    }
                }
                if mark > 0, reveal.showsMark {
                    OnboardingArtwork.Mark(height: height)
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
                    colors: [Theme.Colors.brand.opacity(0.40), Theme.Colors.brand.opacity(0.18), .clear],
                    center: .center, startRadius: 0, endRadius: radius)
                OnboardingArtwork.Grain().opacity(0.055)
            }
        }

        private func ease(_ x: Double) -> Double {
            let t = min(max(x, 0), 1)
            return t * t * t * (t * (6 * t - 15) + 10)
        }
    }
}
