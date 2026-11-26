import SwiftUI

struct OnboardingView: View {
    private typealias Step = OnboardingModel.Step

    @Bindable var model: OnboardingModel
    let runImport: () -> Void
    let finish: () -> Void
    let setMarkAnchor: (NSView) -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()

    var body: some View {
        let step = model.step
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let compact =
                    step != .welcome && step != .ready
                    && geometry.size.height < Theme.Onboarding.compactSetupHeight
                let inset = compact ? Theme.Spacing.xl : Theme.Spacing.xxxl
                ZStack {
                    ScrollViewReader { scroll in
                        ScrollView {
                            page(
                                step, compact: compact,
                                contentHeight: max(0, geometry.size.height - 2 * inset), scroll: scroll
                            )
                            .padding(.horizontal, Theme.Onboarding.inset)
                            .padding(.vertical, inset)
                            .frame(maxWidth: .infinity)
                        }
                        .defaultScrollAnchor(.center, for: .alignment)
                        .scrollIndicators(.hidden)
                    }
                    .id(step)
                    .transition(PageTransition(model: model))
                }
                .clipped()
            }
            .ignoresSafeArea(.container, edges: .top)
            footer
        }
        .background { OnboardingArtwork.Atmosphere() }
        .shortcutRecorderPopoverHost()
        .tint(Theme.Colors.brand)
        .animation(reduceMotion ? nil : Theme.Onboarding.pageMotion, value: step)
        .task(id: model.step) {
            guard model.step == .accessibility else { return }
            while !Task.isCancelled {
                let trusted = Permissions.isAccessibilityTrusted()
                if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: model.shortcutConfirmed) {
            guard model.shortcutConfirmed else { return }
            if Motion.isEnabled, !reduceMotion {
                try? await Task.sleep(for: .seconds(Theme.Onboarding.shortcutConfirmationDuration))
            }
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    @ViewBuilder
    private func page(
        _ step: Step, compact: Bool, contentHeight: CGFloat, scroll: ScrollViewProxy
    ) -> some View {
        switch step {
        case .welcome:
            welcome
        case .accessibility:
            OnboardingSetupPages.Pasting(trusted: accessibilityTrusted, compact: compact)
        case .importData:
            OnboardingSetupPages.Import(
                model: model, compact: compact, contentHeight: contentHeight, scroll: scroll)
        case .ready:
            OnboardingShortcutView(session: model.shortcut, confirmed: model.shortcutConfirmed)
        }
    }

    private var welcome: some View {
        VStack(spacing: Theme.Spacing.xxxl) {
            OnboardingArtwork.Mark(height: Theme.Onboarding.markSize)
                .background { MarkAnchor(register: setMarkAnchor) }
            VStack(spacing: Theme.Spacing.md) {
                Text("Welcome to Tinycast")
                    .font(.system(size: Theme.Onboarding.titleSize, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Everything on your Mac, one keystroke away.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            OnboardingFeatureCarousel(animates: settings.animationsEnabled && !reduceMotion)
        }
        .multilineTextAlignment(.center)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Theme.Spacing.xl) {
                HStack {
                    if let previous = Step(rawValue: model.step.rawValue - 1) {
                        footerButton(String(localized: "Back"), symbol: "chevron.left") {
                            model.step = previous
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Step.allCases, id: \.self) { step in
                        let current = step == model.step
                        Capsule()
                            .fill(current ? Theme.Colors.brand : Color.primary.opacity(0.18))
                            .frame(
                                width: current ? Theme.Spacing.xxl : Theme.Spacing.sm,
                                height: Theme.Spacing.xs
                            )
                            .shadow(
                                color: Theme.Colors.brand.opacity(current ? 0.72 : 0.22),
                                radius: current ? Theme.Spacing.sm : Theme.Spacing.xs)
                    }
                }
                .accessibilityHidden(true)
                HStack(spacing: Theme.Spacing.xl) {
                    if showsSkip {
                        footerButton(String(localized: "Skip"), action: advance)
                    }
                    if model.importing {
                        ProgressView().controlSize(.small)
                    }
                    if model.step != .importData || model.isRaycastExport {
                        footerButton(primaryTitle, usesReturn: primaryUsesReturn, action: primaryAction)
                            .disabled(model.step == .importData && !model.didImport && !model.canImport)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .disabled(model.importing || model.shortcutConfirmed)
            .padding(Theme.Spacing.xxl)
        }
    }

    private func footerButton(
        _ title: String, symbol: String? = nil, usesReturn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        BarButton(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
                if usesReturn {
                    Image(systemName: "return")
                        .font(Theme.Typography.keyCap.weight(.semibold))
                        .frame(width: Theme.Size.keyCap, height: Theme.Size.keyCap)
                        .background(
                            Theme.Onboarding.returnKeyFill, in: .rect(cornerRadius: Theme.Radius.keyCap)
                        )
                        .accessibilityHidden(true)
                }
            }
            .font(Theme.Typography.bar)
            .foregroundStyle(usesReturn ? Color.white : Color.primary)
        }
        .padding(Theme.Spacing.xs)
        .glassEffect(.regular.tint(usesReturn ? Theme.Colors.brand : nil).interactive(), in: Capsule())
        .keyboardShortcut(usesReturn ? .defaultAction : nil)
    }

    private var primaryUsesReturn: Bool {
        model.step != .accessibility || accessibilityTrusted
    }

    private var showsSkip: Bool {
        (model.step == .accessibility && !accessibilityTrusted)
            || (model.step == .importData && !model.didImport)
    }

    private var primaryTitle: String {
        switch model.step {
        case .accessibility where !accessibilityTrusted: String(localized: "Grant Access")
        case .importData where model.importing: String(localized: "Importing…")
        case .importData where !model.didImport: String(localized: "Import")
        case .ready: String(localized: "Get Started")
        default: String(localized: "Next", comment: "Button that advances to the next onboarding step")
        }
    }

    private func primaryAction() {
        switch model.step {
        case .accessibility where !accessibilityTrusted: Permissions.openAccessibilitySettings()
        case .importData where !model.didImport: runImport()
        case .ready: finish()
        default: advance()
        }
    }

    private func advance() {
        if let next = Step(rawValue: model.step.rawValue + 1) { model.step = next }
    }

    private struct PageTransition: Transition {
        let model: OnboardingModel

        func body(content: Content, phase: TransitionPhase) -> some View {
            let distance = model.movesForward ? Theme.Onboarding.pageTravel : -Theme.Onboarding.pageTravel
            content
                .offset(x: -CGFloat(phase.value) * distance)
                .opacity(phase.isIdentity ? 1 : 0)
        }
    }

    private struct MarkAnchor: NSViewRepresentable {
        let register: (NSView) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            register(view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}
