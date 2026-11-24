import AppKit

enum PlanUsageGauge {
    private static let trackOpacity = 0.3

    /// A template while the limit is comfortable, so the menu bar inks it like its neighbours.
    static func image(for target: PlanUsagePin.Target?) -> NSImage {
        let level = target?.window.level ?? .normal
        let fraction = target?.window.fraction ?? 0
        let isTemplate = level == .normal
        let mark =
            target.flatMap { NSImage(named: $0.provider.brand.assetName) }
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        let side = Theme.Size.planUsageGauge
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            let ink = isTemplate ? NSColor.black : NSColor.labelColor
            drawRing(in: bounds, fraction: fraction, ink: ink, fill: isTemplate ? ink : level.nsTint)
            if let mark { draw(mark, in: bounds, ink: ink) }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    private static func drawRing(in bounds: NSRect, fraction: Double, ink: NSColor, fill: NSColor) {
        let line = Theme.Size.planUsageGaugeLine
        let ring = bounds.insetBy(dx: line / 2, dy: line / 2)
        let track = NSBezierPath(ovalIn: ring)
        track.lineWidth = line
        ink.withAlphaComponent(trackOpacity).setStroke()
        track.stroke()
        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: ring.midX, y: ring.midY), radius: ring.width / 2,
            startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        arc.lineWidth = line
        arc.lineCapStyle = .round
        fill.setStroke()
        arc.stroke()
    }

    /// Brand marks are drawn as templates, so the ink is laid over the mark's own shape.
    private static func draw(_ mark: NSImage, in bounds: NSRect, ink: NSColor) {
        let side = Theme.Size.planUsageGaugeGlyph
        let scale = side / max(mark.size.width, mark.size.height, 1)
        let size = NSSize(width: mark.size.width * scale, height: mark.size.height * scale)
        let frame = NSRect(
            x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
            width: size.width, height: size.height)
        let inked = NSImage(size: size, flipped: false) { canvas in
            mark.draw(in: canvas)
            ink.set()
            canvas.fill(using: .sourceAtop)
            return true
        }
        inked.draw(in: frame)
    }
}
