import SwiftUI

@MainActor
enum ExtensionMenuBarImage {
    static let size: CGFloat = 18

    static func loadAdaptive(_ value: RenderValue?, assetsPath: String) async -> NSImage? {
        guard let light = await load(value, assetsPath: assetsPath, isDark: false) else { return nil }
        guard let dark = await load(value, assetsPath: assetsPath, isDark: true), !Task.isCancelled else { return light }
        let image = NSImage(size: light.size, flipped: false) { rect in
            let source = NSAppearance.currentDrawing().isDark ? dark : light
            source.draw(in: rect)
            return true
        }
        image.isTemplate = light.isTemplate && dark.isTemplate
        return image
    }

    static func load(_ value: RenderValue?, assetsPath: String, isDark: Bool) async -> NSImage? {
        guard let resolved = ExtensionImage.resolve(value, assetsPath: assetsPath, isDark: isDark) else { return nil }
        let source: NSImage?
        var template = false
        switch resolved.source {
        case .symbol(let name):
            source = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            template = resolved.tint == nil
        case .file(let path):
            source = await ExtensionIconCache.loadOriginalAsync(atPath: path)
        case .fileIcon(let path):
            source = NSWorkspace.shared.icon(forFile: path)
        case .remote(let url):
            source = await ExtensionIconCache.loadRemoteAsync(url, asIcon: false)
        case .inline(let url):
            source = await ExtensionIconCache.loadInlineAsync(url, palette: ExtensionImage.svgPalette(isDark: isDark))
        case .glyph(let text):
            source = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size - 2)])
                return true
            }
        }
        guard !Task.isCancelled, let source, source.size.width > 0, source.size.height > 0 else { return nil }
        let tint = resolved.tint.map(NSColor.init)
        let circular = resolved.isCircular
        let result = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if circular { NSBezierPath(ovalIn: rect).addClip() }
            let scale = min(rect.width / source.size.width, rect.height / source.size.height)
            let fitted = NSRect(x: (rect.width - source.size.width * scale) / 2,
                                y: (rect.height - source.size.height * scale) / 2,
                                width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: fitted)
            if let tint {
                tint.setFill()
                rect.fill(using: .sourceIn)
            }
            return true
        }
        guard let pixels = result.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let image = NSImage(cgImage: pixels, size: NSSize(width: size, height: size))
        image.isTemplate = template
        return image
    }
}
