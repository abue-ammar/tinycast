import SwiftUI

private typealias BarMotion = Theme.CompactBarMotion

/// Where the capsule ends and each button rests, in a compact window exactly as wide as the panel.
struct CompactBarGeometry {
    let width: CGFloat
    let height: CGFloat
    let diameter: CGFloat
    let gap: CGFloat
    let cornerRadius: CGFloat
    let count: Int

    init(metrics: InterfaceMetrics, count: Int) {
        width = metrics.size.panelWidth
        height = metrics.size.compactHeight
        cornerRadius = metrics.radius.panel
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

    func outline(at elapsed: TimeInterval, in rect: CGRect) -> Path {
        let capsule = CompactBarReveal.capsule(at: elapsed)
        let shortened = width + (capsuleWidth(revealed: true) - width) * capsule
        var path = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: CGRect(x: rect.minX, y: rect.minY, width: shortened, height: height))
        for index in 0..<count {
            let progress = CompactBarReveal.button(index, at: elapsed)
            let size = diameter * (BarMotion.parkedScale + (1 - BarMotion.parkedScale) * progress)
            let target = center(of: index)
            let x = rect.minX + parked.x + (target.x - parked.x) * progress
            let y = rect.minY + parked.y + (target.y - parked.y) * progress
            let circle = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
            path = path.union(Path(ellipseIn: circle))
        }
        return path
    }
}

/// The reveal's progress at a moment, from the same springs the glyphs animate with.
enum CompactBarReveal {
    static func duration(count: Int) -> TimeInterval {
        max(
            BarMotion.revealDelay + BarMotion.capsule.settlingDuration,
            buttonDelay(max(count - 1, 0)) + BarMotion.button.settlingDuration)
    }

    static func buttonDelay(_ index: Int) -> TimeInterval {
        BarMotion.revealDelay + BarMotion.stagger * Double(index)
    }

    static func capsule(at elapsed: TimeInterval) -> CGFloat {
        progress(of: BarMotion.capsule, at: elapsed - BarMotion.revealDelay)
    }

    static func button(_ index: Int, at elapsed: TimeInterval) -> CGFloat {
        progress(of: BarMotion.button, at: elapsed - buttonDelay(index))
    }

    private static func progress(of spring: Spring, at time: TimeInterval) -> CGFloat {
        guard time > 0 else { return 0 }
        guard time < spring.settlingDuration else { return 1 }
        return spring.value(target: 1, time: time)
    }
}

struct PaletteOutline: Shape {
    let cornerRadius: CGFloat
    let bar: CompactBarGeometry?
    var elapsed: TimeInterval

    var animatableData: TimeInterval {
        get { elapsed }
        set { elapsed = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard let bar else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        }
        return bar.outline(at: elapsed, in: rect)
    }
}

struct CompactBar: View {
    let commands: [CommandID]
    let selection: CommandID?
    let isRevealed: Bool
    let onRun: (CommandID) -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let geometry = CompactBarGeometry(metrics: metrics, count: commands.count)
        ZStack(alignment: .topLeading) {
            selectionFace(geometry: geometry)
            ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                glyph(command, at: index, geometry: geometry)
                button(command, at: index, geometry: geometry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func selectionFace(geometry: CompactBarGeometry) -> some View {
        if let selection, let index = commands.firstIndex(of: selection) {
            Circle().fill(Theme.Colors.compactShortcutSelectionTint)
                .frame(width: geometry.diameter, height: geometry.diameter)
                .position(geometry.center(of: index))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func button(
        _ command: CommandID, at index: Int, geometry: CompactBarGeometry
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
        .accessibilityHidden(!isRevealed)
        .position(geometry.center(of: index))
        .allowsHitTesting(isRevealed)
    }

    private func glyph(
        _ command: CommandID, at index: Int, geometry: CompactBarGeometry
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
            $0.opacity(isRevealed ? 1 : 0).blur(radius: isRevealed ? 0 : BarMotion.glyphBlur)
        }
        // Shrinks with its circle but never travels: glyphs sent home would pile into one blot.
        .animation(travel(index)) {
            $0.scaleEffect(isRevealed ? 1 : BarMotion.parkedScale)
        }
        .position(geometry.center(of: index))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func travel(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(BarMotion.button).delay(CompactBarReveal.buttonDelay(index))
    }

    private func fade(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: BarMotion.glyphFade)
            .delay(CompactBarReveal.buttonDelay(index) + BarMotion.glyphDelay)
    }
}
