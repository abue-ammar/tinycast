import AppKit
import Foundation
import SwiftUI

@main
@MainActor
struct ExtensionIconTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// Artwork is normalized, so a source's transparent margin cannot change its size.
    static func artworkIsNormalized() {
        guard let bleed = writePNG("bleed", inset: 0), let padded = writePNG("padded", inset: 96)
        else { return expect(false, "the fixtures write") }
        defer {
            try? FileManager.default.removeItem(at: bleed.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: padded.deletingLastPathComponent())
        }

        guard let full = inkExtent(ExtensionIconCache.icon(atPath: bleed.path)),
            let margin = inkExtent(ExtensionIconCache.icon(atPath: padded.path))
        else { return expect(false, "both fixtures rasterize") }

        expect(abs(full - margin) <= 0.03, "padding can't change the drawn size: \(full) vs \(margin)")
        expect(
            full < IconCache.appIconExtent - 0.03,
            "artwork draws below an app icon's \(IconCache.appIconExtent): \(full)")
    }

    /// A missing file still answers, so a row never renders an empty slot.
    static func missingFileFallsBack() {
        let icon = ExtensionIconCache.icon(atPath: "/nonexistent/\(UUID().uuidString).png")
        expect(icon.size.width > 0, "a missing icon falls back to the puzzle-piece tile")
    }

    /// No SVG renderer knows a Raycast colour name, so the shape draws nothing.
    static func paletteColorsInSVGResolve() async {
        // The usage-ring shape every quota extension draws: a track and an arc, each named.
        let ring = """
            <svg xmlns="http://www.w3.org/2000/svg" width="100px" height="100px"><circle cx="50" \
            cy="50" r="40" stroke-width="10" stroke="raycast-secondary-text" fill="none" />\
            <path d="M 50 10 A 40 40 0 0 0 20 25" stroke="raycast-green" stroke-width="10" \
            fill="none" /></svg>
            """
        let drawn = await drawnInk(ring, isDark: true)
        expect(drawn != nil, "the rewritten ring draws ink")
        // Both encodings: base64 hides the name from a scan, so the payload has to be decoded.
        let asBase64 = await drawnInk(ring, isDark: true, base64: true)
        expect(asBase64 != nil, "a base64 ring draws ink too")
        // Detail markdown's sizing query trails the payload and is not part of it.
        let sized = await drawnInk(ring, isDark: true, query: "?raycast-width=32")
        expect(sized != nil, "a sized payload still draws")

        // The rewrite walks whole names: a known one inside a longer unknown must not match.
        let unknown = await drawnInk(circle(stroke: "raycast-green-invented"), isDark: true)
        expect(unknown == nil, "an unknown name is left whole, and draws nothing")
        let known = await drawnInk(circle(stroke: "raycast-green"), isDark: true)
        expect(known != nil, "the known name it shadows still resolves")

        // Light and dark disagree on every ramp, so the pick has to follow the surface drawn on.
        let ramp = circle(stroke: "raycast-primary-text")
        let dark = await drawnColor(ramp, isDark: true)
        let light = await drawnColor(ramp, isDark: false)
        expect(dark?.brightnessComponent ?? 0 > 0.9, "the dark ramp strokes white ink")
        expect(light?.brightnessComponent ?? 1 < 0.1, "the light ramp strokes black ink")

        // A photo names no colour, and is never decoded as text: its bytes must reach the decoder.
        let png = writePNG("photo", inset: 0).flatMap { try? Data(contentsOf: $0) }
        let photo = URL(string: "data:image/png;base64,\(png?.base64EncodedString() ?? "")")!
        let passed = await ExtensionIconCache.loadInlineAsync(
            photo, palette: ExtensionImage.svgPalette(isDark: true))
        expect(passed != nil, "an inline photo is passed through untouched")
    }

    /// A stroked ring, thick enough that a 96pt raster samples the colour cleanly.
    static func circle(stroke: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100px\" height=\"100px\"><circle "
            + "cx=\"50\" cy=\"50\" r=\"36\" stroke-width=\"24\" stroke=\"\(stroke)\" "
            + "fill=\"none\" /></svg>"
    }

    /// An SVG as a row draws it: a `data:` URL decoded with the palette.
    static func drawnImage(
        _ svg: String, isDark: Bool, base64: Bool = false, query: String = ""
    ) async -> NSImage? {
        let allowed = CharacterSet(charactersIn: "<>\"# %{}|\\^~[]`").inverted
        let payload =
            base64
            ? Data(svg.utf8).base64EncodedString()
            : svg.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let header = base64 ? "data:image/svg+xml;base64," : "data:image/svg+xml,"
        guard let url = URL(string: header + payload + query) else { return nil }
        return await ExtensionIconCache.loadInlineAsync(
            url, palette: ExtensionImage.svgPalette(isDark: isDark))
    }

    static func drawnInk(
        _ svg: String, isDark: Bool, base64: Bool = false, query: String = ""
    ) async -> CGFloat? {
        await drawnImage(svg, isDark: isDark, base64: base64, query: query).flatMap(inkExtent)
    }

    /// The colour an unresolved name never produces, since the shape it strokes draws nothing.
    static func drawnColor(_ svg: String, isDark: Bool) async -> NSColor? {
        await drawnImage(svg, isDark: isDark).flatMap(inkColor)
    }

    /// A `data:` URL in either encoding, with Detail markdown's sizing query appended.
    static func inlineDataURLsDecode() async {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" \
            fill="none" stroke="currentColor"><path d="M2 12 L22 12"/></svg>
            """
        let escaped = CharacterSet(charactersIn: "<>\"# %{}|\\^~[]`").inverted
        guard let encoded = svg.addingPercentEncoding(withAllowedCharacters: escaped) else {
            return expect(false, "the fixture encodes")
        }

        for suffix in ["", "?raycast-width=200&raycast-height=200"] {
            let url = URL(string: "data:image/svg+xml,\(encoded)\(suffix)")!
            let image = await ExtensionIconCache.loadInlineAsync(url, palette: [:])
            expect(image?.size == NSSize(width: 24, height: 24), "percent-encoded SVG\(suffix)")
        }

        let pngURL = writePNG("inline", inset: 0)
        defer { pngURL.map { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }
        let png = pngURL.flatMap { try? Data(contentsOf: $0) }
        guard let png else { return expect(false, "the PNG fixture writes") }
        let base64 = URL(string: "data:image/png;base64,\(png.base64EncodedString())")!
        let decoded = await ExtensionIconCache.loadInlineAsync(base64, palette: [:])
        expect(decoded != nil, "base64 payload decodes")

        let broken = URL(string: "data:image/png;base64,not-base-64")!
        let rejected = await ExtensionIconCache.loadInlineAsync(broken, palette: [:])
        expect(rejected == nil, "a broken payload is nil")
    }

    /// A red square on a transparent canvas, `inset` pixels in from each edge.
    static func writePNG(_ name: String, inset: Int) -> URL? {
        let side = 512
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.red.setFill()
        NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-icon-test-\(UUID().uuidString)")
        guard let data = rep.representation(using: .png, properties: [:]),
            (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true))
                != nil
        else { return nil }
        let url = dir.appendingPathComponent("\(name).png")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// The larger side of the alpha bounding box, as a share of the canvas.
    static func inkExtent(_ image: NSImage) -> CGFloat? {
        rasterize(image).flatMap { rep in
            var minX = 96, maxX = -1, minY = 96, maxY = -1
            for y in 0..<96 {
                for x in 0..<96 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.06 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return CGFloat(max(maxX - minX + 1, maxY - minY + 1)) / 96
        }
    }

    /// The most opaque pixel drawn; a palette ramp strokes below opaque.
    static func inkColor(_ image: NSImage) -> NSColor? {
        guard let rep = rasterize(image) else { return nil }
        var best: NSColor?
        var strongest: CGFloat = 0.5
        for y in 0..<96 {
            for x in 0..<96 {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > strongest else {
                    continue
                }
                strongest = color.alphaComponent
                best = color.usingColorSpace(.sRGB)
            }
        }
        return best
    }

    /// The image drawn into a fixed 96pt canvas, which every pixel assertion reads from.
    static func rasterize(_ image: NSImage) -> NSBitmapImageRep? {
        let side = 96
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func main() async {
        artworkIsNormalized()
        missingFileFallsBack()
        await inlineDataURLsDecode()
        await paletteColorsInSVGResolve()

        print(failures == 0 ? "Extension icon tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
