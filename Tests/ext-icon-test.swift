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

    /// Extension artwork is normalized, so how much transparent margin a source ships cannot change
    /// the size it draws at — and it lands below an app icon on purpose. See docs/features/extensions.md.
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

    /// An extension drawing its own SVG writes a Raycast colour name straight into `stroke`, which
    /// no SVG renderer understands — left alone the shape draws nothing at all.
    static func paletteColorsInSVGResolve() async {
        // The usage-ring shape every quota extension draws: a track and an arc, each named.
        let ring = """
            <svg xmlns="http://www.w3.org/2000/svg" width="100px" height="100px"><circle cx="50" \
            cy="50" r="40" stroke-width="10" stroke="raycast-secondary-text" fill="none" />\
            <path d="M 50 10 A 40 40 0 0 0 20 25" stroke="raycast-green" stroke-width="10" \
            fill="none" /></svg>
            """
        guard let url = inlineSource(ring, isDark: true) else {
            return expect(false, "a data: URL resolves to an inline source")
        }
        expect(!url.absoluteString.contains("raycast-"), "every colour name is rewritten")

        let image = await ExtensionIconCache.loadInlineAsync(url)
        expect(image.flatMap(inkExtent) != nil, "the rewritten ring draws ink")

        // A known name occurring inside a longer unknown one may not be substituted there: the
        // rewrite has to walk whole names rather than search for the ones it knows.
        let shadowed =
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><circle stroke=\"raycast-green\" "
            + "fill=\"raycast-green-invented\" /></svg>"
        let left = inlineSource(shadowed, isDark: true)?.absoluteString.removingPercentEncoding
        expect(left?.contains("raycast-green-invented") == true, "an unknown name is left whole")
        expect(left?.contains("\"raycast-green\"") == false, "the known name beside it resolves")

        // Light and dark disagree on every ramp, so the pick has to follow the surface drawn on.
        let ramp =
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><circle "
            + "stroke=\"raycast-primary-text\" /></svg>"
        let dark = inlineSource(ramp, isDark: true)?.absoluteString.removingPercentEncoding
        let light = inlineSource(ramp, isDark: false)?.absoluteString.removingPercentEncoding
        expect(dark != nil && dark != light, "a ramp resolves per appearance")
    }

    /// The `data:` URL an SVG resolves to, as a row would ask for it.
    static func inlineSource(_ svg: String, isDark: Bool) -> URL? {
        let allowed = CharacterSet(charactersIn: "<>\"# %{}|\\^~[]`").inverted
        guard let encoded = svg.addingPercentEncoding(withAllowedCharacters: allowed),
            case .inline(let url)? = ExtensionImage.resolve(
                .string("data:image/svg+xml,\(encoded)"), assetsPath: nil, isDark: isDark)?.source
        else { return nil }
        return url
    }

    /// Extensions that render their own artwork hand it over as a `data:` URL rather than a file,
    /// in either encoding, and Detail markdown appends Raycast's sizing query to it.
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
            let image = await ExtensionIconCache.loadInlineAsync(url)
            expect(image?.size == NSSize(width: 24, height: 24), "percent-encoded SVG\(suffix)")
        }

        let png = writePNG("inline", inset: 0).flatMap { try? Data(contentsOf: $0) }
        guard let png else { return expect(false, "the PNG fixture writes") }
        let base64 = URL(string: "data:image/png;base64,\(png.base64EncodedString())")!
        let decoded = await ExtensionIconCache.loadInlineAsync(base64)
        expect(decoded != nil, "base64 payload decodes")

        let broken = URL(string: "data:image/png;base64,not-base-64")!
        let rejected = await ExtensionIconCache.loadInlineAsync(broken)
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

        var minX = side, maxX = -1, minY = side, maxY = -1
        for y in 0..<side {
            for x in 0..<side where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.06 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGFloat(max(maxX - minX + 1, maxY - minY + 1)) / CGFloat(side)
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
