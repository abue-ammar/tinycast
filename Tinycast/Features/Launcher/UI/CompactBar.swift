import SwiftUI

private typealias BarMotion = Theme.CompactBarMotion

/// Where the capsule ends and each button rests, in a compact window exactly as wide as the panel.
struct CompactBarGeometry {
    let width: CGFloat
    let height: CGFloat
    let diameter: CGFloat
    let gap: CGFloat
    let count: Int

    init(metrics: InterfaceMetrics, count: Int) {
        width = metrics.size.panelWidth
        height = metrics.size.compactHeight
        // A point inside the bar's height, so the last button clears the window's rounded end.
        diameter = height - metrics.scaled(1) * 2
        gap = metrics.spacing.lg
        self.count = count
    }

    func capsuleWidth(revealed: Bool) -> CGFloat {
        revealed ? width - CGFloat(count) * (diameter + gap) : width
    }

    func center(of index: Int) -> CGPoint {
        CGPoint(
            x: capsuleWidth(revealed: true) + gap + diameter / 2 + CGFloat(index) * (diameter + gap),
            y: height / 2)
    }

    /// Just inside the shortened capsule's end, so the capsule pulling back uncovers each button.
    var parked: CGPoint {
        CGPoint(x: capsuleWidth(revealed: true) - diameter / 2, y: height / 2)
    }
}

/// The compact bar's glass: a capsule the buttons bead off, with their glyphs drawn above it.
struct CompactBar: View {
    let commands: [CommandID]
    let selection: CommandID?
    let onRun: (CommandID) -> Void
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    var body: some View {
        let geometry = CompactBarGeometry(metrics: metrics, count: commands.count)
        let revealed = isRevealed
        let capsule = Capsule(style: .continuous)
        // One container, or the buttons could never bead off the capsule they come out of.
        GlassEffectContainer(spacing: metrics.scaled(BarMotion.blend)) {
            ZStack(alignment: .topLeading) {
                capsule.fill(.clear)
                    .frame(width: geometry.capsuleWidth(revealed: revealed))
                    .frame(maxHeight: .infinity)
                    .glassEffect(.regular, in: capsule)
                    .animation(
                        reduceMotion ? nil : BarMotion.capsule.delay(BarMotion.revealDelay),
                        value: revealed)
                ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                    button(command, at: index, geometry: geometry, revealed: revealed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay { scrim(geometry: geometry, revealed: revealed) }
        // Above the glass rather than inside it, where a morph would smear them.
        .overlay(alignment: .topLeading) {
            ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                glyph(command, at: index, geometry: geometry, revealed: revealed)
            }
        }
        .task(id: palette.isVisible) { await followVisibility() }
    }

    private func button(
        _ command: CommandID, at index: Int, geometry: CompactBarGeometry, revealed: Bool
    ) -> some View {
        Button {
            onRun(command)
        } label: {
            Color.clear
                .frame(width: geometry.diameter, height: geometry.diameter)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(command.name)
        .accessibilityLabel(command.name)
        .accessibilityAddTraits(selection == command ? [.isSelected] : [])
        .accessibilityHidden(!revealed)
        .background(
            Theme.Colors.panelScrim.opacity(
                colorScheme == .dark && selection == command && revealed ? 1 : 0),
            in: .circle
        )
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay {
            if colorScheme == .dark {
                Circle().fill(selection == command ? Theme.Colors.compactShortcutGlassSelection : .clear)
            }
        }
        .scaleEffect(revealed ? 1 : BarMotion.parkedScale)
        .position(revealed ? geometry.center(of: index) : geometry.parked)
        .allowsHitTesting(revealed)
        .animation(travel(index), value: revealed)
    }

    private func scrim(geometry: CompactBarGeometry, revealed: Bool) -> some View {
        Theme.Colors.panelScrim
            .mask {
                ZStack(alignment: .topLeading) {
                    Capsule().fill(.white)
                        .frame(width: geometry.capsuleWidth(revealed: revealed))
                        .frame(maxHeight: .infinity)
                        .animation(
                            reduceMotion ? nil : BarMotion.capsule.delay(BarMotion.revealDelay),
                            value: revealed)
                    ForEach(commands.indices, id: \.self) { index in
                        if colorScheme != .dark || selection != commands[index] {
                            Circle().fill(.white)
                                .frame(width: geometry.diameter, height: geometry.diameter)
                                .opacity(revealed ? 1 : 0)
                                .scaleEffect(revealed ? 1 : BarMotion.parkedScale)
                                .position(revealed ? geometry.center(of: index) : geometry.parked)
                                .animation(travel(index), value: revealed)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func glyph(
        _ command: CommandID, at index: Int, geometry: CompactBarGeometry, revealed: Bool
    ) -> some View {
        SymbolImage(
            name: command.sfSymbol, size: metrics.scaled(Theme.Typography.headerIconSize),
            monochrome: selection == command
        )
        .environment(\.symbolVariants, .none)
        .foregroundStyle(
            selection == command ? Theme.Colors.compactShortcutSelectedInk : Theme.Colors.textSecondary
        )
        .animation(fade(index)) {
            $0.opacity(revealed ? 1 : 0).blur(radius: revealed ? 0 : BarMotion.glyphBlur)
        }
        .background {
            if selection == command {
                Circle().fill(Theme.Colors.compactShortcutSelection)
                    .frame(width: geometry.diameter, height: geometry.diameter)
                    .opacity(revealed ? 1 : 0)
            }
        }
        // Shrinks with its circle but never travels: glyphs sent home would pile into one blot.
        .animation(travel(index)) {
            $0.scaleEffect(revealed ? 1 : BarMotion.parkedScale)
        }
        .position(geometry.center(of: index))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func travel(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return BarMotion.button.delay(BarMotion.revealDelay + BarMotion.stagger * Double(index))
    }

    private func fade(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: BarMotion.glyphFade)
            .delay(BarMotion.revealDelay + BarMotion.glyphDelay + BarMotion.stagger * Double(index))
    }

    /// Out on every summon, and parked only once the window has faded, so leaving fades it whole.
    private func followVisibility() async {
        guard !palette.isVisible else {
            isRevealed = true
            return
        }
        try? await Task.sleep(for: .seconds(Motion.duration(BarMotion.parkAfterHide)))
        guard !Task.isCancelled else { return }
        withTransaction(\.disablesAnimations, true) { isRevealed = false }
    }
}
