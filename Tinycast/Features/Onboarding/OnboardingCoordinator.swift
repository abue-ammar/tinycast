import AppKit
import SwiftUI

@MainActor
final class OnboardingCoordinator {
    private var window: AppWindowController?
    private weak var chrome: Chrome?
    private weak var model: OnboardingModel?
    private var introTask: Task<Void, Never>?
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    func showOnboarding() {
        guard !focusExisting() else { return }
        let screen = preferredScreen
        let chrome = prepareWizard(on: screen)
        guard Motion.isEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            let screen, let landing = chrome.markOnScreen
        else {
            chrome.reveal()
            window?.focus()
            return
        }
        let intro = OnboardingIntro(on: screen, landing: landing)
        introTask = Task { [weak self] in
            defer { self?.introTask = nil }
            try? await Task.sleep(for: .seconds(Theme.Onboarding.introDuration))
            guard !Task.isCancelled, let self else {
                intro.close()
                return
            }
            let sameDisplay = NSScreen.screens.contains(screen)
            if !sameDisplay {
                intro.close()
                chrome.place(on: preferredScreen)
            }
            window?.focus()
            if chrome.reveal(intro: sameDisplay ? intro : nil) {
                try? await Task.sleep(for: .seconds(Theme.Onboarding.revealShadowDelay))
                intro.hideMark()
                guard !Task.isCancelled, let wizard = chrome.window, wizard.isVisible else { return }
                wizard.hasShadow = true
            }
        }
    }

    private var preferredScreen: NSScreen? {
        core.settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    private func prepareWizard(on screen: NSScreen?) -> Chrome {
        let paletteSize = core.settings.interfaceSize.metrics.size
        var size = CGSize(width: paletteSize.panelWidth, height: paletteSize.panelHeight)
        if let bounds = screen?.visibleFrame {
            size.width = min(size.width, bounds.width - Theme.Onboarding.inset * 2)
            size.height = min(size.height, bounds.height - Theme.Onboarding.inset * 2)
        }
        let controller = AppWindowController(
            title: String(localized: "Welcome to Tinycast"), contentSize: size,
            activation: nil, closesOnEscape: true)
        let chrome = Chrome()
        let model = OnboardingModel()
        window = controller
        self.chrome = chrome
        self.model = model
        controller.show(chrome: chrome, orderFront: false) {
            OnboardingView(
                model: model,
                runImport: { [weak self] in
                    if let self { model.run(core: core) }
                },
                finish: { [weak self] in self?.finishOnboarding(model) },
                setMarkAnchor: { [weak chrome] in chrome?.markAnchor = $0 }
            )
            .environment(self.core.settings)
            .environment(self.core.hotKeys)
        }
        chrome.place(on: screen)
        return chrome
    }

    func handleLauncherShortcut() -> Bool {
        guard let model, model.step == .ready, chrome?.window?.isKeyWindow == true else { return false }
        model.shortcutConfirmed = true
        return true
    }

    private func finishOnboarding(_ model: OnboardingModel) {
        guard self.model === model, chrome?.window?.isVisible == true else { return }
        self.model = nil
        window?.close()
        core.paletteCoordinator.showPalette(mode: .launcher)
    }

    func focusExisting() -> Bool {
        introTask != nil || window?.focus() == true
    }

    @MainActor
    private final class Chrome: WindowChrome {
        private(set) weak var window: NSWindow?
        weak var markAnchor: NSView?

        var markOnScreen: CGPoint? {
            guard let window, let content = window.contentView,
                let center = markCenter(in: content)
            else { return nil }
            return window.convertPoint(toScreen: content.convert(center, to: nil))
        }

        func install(in window: NSWindow) {
            self.window = window
            window.alphaValue = 0
            window.animationBehavior = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.toolbar = NSToolbar(identifier: "Onboarding")
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        }

        func place(on screen: NSScreen?) {
            guard let window, let bounds = screen?.visibleFrame else { return }
            let size = window.frame.size
            let anchor = PalettePlacement.defaultAnchor(
                in: bounds, width: size.width, topMarginFraction: Theme.Size.paletteTopMarginFraction)
            let frame = PalettePlacement.frame(at: anchor, size: size, outset: 0)
            window.setFrameOrigin(NSPoint(x: frame.minX, y: max(frame.minY, bounds.minY)))
        }

        private func markCenter(in content: NSView) -> CGPoint? {
            content.layoutSubtreeIfNeeded()
            guard let markAnchor, markAnchor.window === window, !markAnchor.bounds.isEmpty else { return nil }
            return content.convert(
                CGPoint(x: markAnchor.bounds.midX, y: markAnchor.bounds.midY), from: markAnchor)
        }

        @discardableResult
        func reveal(intro: OnboardingIntro? = nil) -> Bool {
            guard let window else {
                intro?.close()
                return false
            }
            guard let intro, let content = window.contentView, let center = markCenter(in: content) else {
                intro?.close()
                window.alphaValue = 1
                return false
            }

            let bounds = content.bounds
            let farthestCorner = hypot(
                max(center.x - bounds.minX, bounds.maxX - center.x),
                max(center.y - bounds.minY, bounds.maxY - center.y))
            let radius = farthestCorner + Theme.Onboarding.revealFeather
            let solidEdge = farthestCorner / radius
            let feather = 1 - solidEdge
            let stops = (0...12).map { CGFloat($0) / 12 }
            let locations = ([0] + stops.map { solidEdge + feather * $0 }).map {
                NSNumber(value: Double($0))
            }
            let colors =
                [CGColor(gray: 1, alpha: 1)]
                + stops.map { progress in
                    CGColor(gray: 1, alpha: 1 - progress * progress * (3 - 2 * progress))
                }
            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = Array(repeating: NSNumber(value: 0), count: locations.count)
            animation.duration = Theme.Onboarding.revealDuration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.43, 0, 0.27, 1)

            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let views = [content] + buttons.compactMap { window.standardWindowButton($0) }
            let normalLevel = window.level
            window.hasShadow = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let layers = views.compactMap { view -> CALayer? in
                view.wantsLayer = true
                guard let layer = view.layer else { return nil }
                let origin = view.convert(center, from: content)
                let mask = CAGradientLayer()
                mask.type = .radial
                mask.startPoint = CGPoint(x: 0.5, y: 0.5)
                mask.endPoint = CGPoint(x: 1, y: 1)
                mask.frame = CGRect(
                    x: origin.x - radius, y: origin.y - radius,
                    width: radius * 2, height: radius * 2)
                mask.colors = colors
                mask.locations = locations
                layer.mask = mask
                return layer
            }
            CATransaction.setCompletionBlock { [weak window] in
                DispatchQueue.main.async {
                    for layer in layers { layer.mask = nil }
                    intro.close()
                    window?.level = normalLevel
                }
            }
            for layer in layers { layer.mask?.add(animation, forKey: "reveal") }
            intro.fadeBehind(window)
            window.alphaValue = 1
            CATransaction.commit()
            return true
        }
    }
}
