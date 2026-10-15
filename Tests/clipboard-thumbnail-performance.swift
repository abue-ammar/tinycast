import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
@MainActor
enum ClipboardThumbnailBenchmark {
    static let rowPixel: CGFloat = 64
    static let previewPixel: CGFloat = 900

    static func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    }

    static func megabytes() -> [String: Double] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        return [
            "footprint_mb": Double(info.phys_footprint) / 1_048_576,
            "peak_mb": Double(info.ledger_phys_footprint_peak) / 1_048_576
        ]
    }

    /// A seeded Display P3 "screenshot": a gradient under grain, which PNG can't compress away.
    static func writeFixture(_ index: Int, to url: URL) {
        let (width, height) = [(3456, 2234), (3248, 2122), (3024, 1964)][index % 3]
        var state = UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let grain = Int(state >> 59) - 16
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(clamping: x * 255 / width + grain)
                pixels[offset + 1] = UInt8(clamping: y * 255 / height + grain)
                pixels[offset + 2] = UInt8(clamping: (index * 37) % 256 + grain)
            }
        }
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
    }

    static func main() async {
        let arguments = CommandLine.arguments
        guard let path = arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) else {
            print("usage: clipboard-thumbnail-performance <dir> [--fixtures | --original | --copies]")
            exit(2)
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        if arguments.contains("--fixtures") {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for index in 0..<10 {
                writeFixture(index, to: directory.appendingPathComponent(String(format: "%02d.png", index)))
            }
            return
        }
        let derived = !arguments.contains("--original")
        let helper =
            derived ? Bundle.main.bundleURL.appending(path: "Contents/Helpers/ClipboardTextHelper") : nil
        let urls =
            ((try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
        precondition(!urls.isEmpty, "run --fixtures first")
        let copiesBefore =
            (try? FileManager.default.contentsOfDirectory(
                atPath: directory.appendingPathComponent(".thumbnails").path
            ).count) ?? 0

        // Opening history: every visible row asks for its tile at once, as the list does.
        let rowsStart = ContinuousClock.now
        let rowsLoaded = await withTaskGroup(of: Bool.self) { group in
            for url in urls {
                group.addTask {
                    await ImageThumbnail.loadAsync(url, maxPixel: rowPixel, copyingWith: helper) != nil
                }
            }
            var all = true
            for await loaded in group { all = all && loaded }
            return all
        }
        let rows = milliseconds(rowsStart)
        let previewsStart = ContinuousClock.now
        var previewsLoaded = true
        for url in urls {
            let image = await ImageThumbnail.loadAsync(url, maxPixel: previewPixel, copyingWith: helper)
            previewsLoaded = previewsLoaded && image != nil
        }
        let previews = milliseconds(previewsStart)
        // A silent fall back to the original would time the old path under the new name.
        let copiesMade = urls.allSatisfy { url in
            [rowPixel, previewPixel].allSatisfy { pixel in
                ImageDerivative.covering(url, maxPixel: Int(pixel)).map {
                    FileManager.default.fileExists(atPath: $0.url.path)
                } ?? false
            }
        }
        guard rowsLoaded, previewsLoaded, !derived || copiesMade else {
            print("FAIL: a load returned nil or a copy is missing; the helper must sit at Contents/Helpers")
            exit(1)
        }
        ImageThumbnail.purgePreviews()

        var output: [String: Any] = megabytes()
        output["mode"] = derived ? (copiesBefore == 0 ? "copies, first view" : "copies") : "original"
        output["images"] = urls.count
        output["rows_ms"] = rows.rounded()
        output["previews_ms"] = previews.rounded()
        guard let json = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
            let line = String(bytes: json, encoding: .utf8)
        else { exit(1) }
        print(line)
    }
}
