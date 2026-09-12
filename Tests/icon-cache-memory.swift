import AppKit

@main
@MainActor
struct IconCacheMemory {
    static let paths = [
        "/System/Library/CoreServices/Finder.app", "/System/Applications/Calculator.app",
        "/System/Applications/Calendar.app", "/System/Applications/Notes.app",
        "/System/Applications/System Settings.app", "/System/Applications/Preview.app"
    ]

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / 4)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        return info.phys_footprint
    }

    static func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    static func bitmapBytes(_ image: NSImage) -> Int {
        autoreleasepool {
            guard let rep = image.representations.first as? NSBitmapImageRep else { fatalError("Missing bitmap") }
            return rep.bytesPerRow * rep.pixelsHigh
        }
    }

    static func load(_ index: Int, size: IconSize?) -> NSImage {
        autoreleasepool {
            IconCache.icon(forFile: paths[index % paths.count], stamp: index + 1, size: size)
        }
    }

    static func measure(count: Int, points: CGFloat, transitions: Bool) -> [String: Any] {
        autoreleasepool { for index in paths.indices { _ = load(index, size: nil) } }
        IconCache.invalidateStyled()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let before = footprint()
        let size = points == 0 ? nil : IconSize(points: points, scale: 2)
        let started = ContinuousClock.now
        var held = (0..<count).map { load($0, size: size) }
        let cold = milliseconds(started)
        let open = footprint()
        let allocation = held.reduce(0) { $0 + bitmapBytes($1) }
        let warmStart = ContinuousClock.now
        autoreleasepool {
            for index in 0..<count {
                let warm = IconCache.cached(forFile: paths[index % paths.count], stamp: index + 1, size: size)
                precondition(warm === held[index])
            }
        }
        let warm = milliseconds(warmStart)
        var sizes: [[String: Any]] = []
        if transitions {
            for next: CGFloat in [26, 29, 24] {
                let nextSize = points == 0 ? nil : IconSize(points: next, scale: 2)
                let start = ContinuousClock.now
                for index in held.indices { held[index] = load(index, size: nextSize) }
                sizes.append([
                    "points": next, "footprint": footprint(),
                    "milliseconds": milliseconds(start),
                    "bitmapBytes": held.reduce(0) { $0 + bitmapBytes($1) }
                ])
            }
        }
        weak let sample = held.first
        weak var bitmap: NSBitmapImageRep?
        autoreleasepool { bitmap = held.first?.representations.first as? NSBitmapImageRep }
        IconCache.invalidateStyled()
        held.removeAll()
        precondition(sample == nil && bitmap == nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return [
            "points": points, "count": count, "before": before, "open": open,
            "bitmapBytes": allocation, "coldMilliseconds": cold, "warmMilliseconds": warm,
            "settled": footprint(), "imageAndBitmapReleased": true, "transitions": sizes
        ]
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3, let points = Double(args[1]), [0, 24, 26, 29].contains(points),
            let count = Int(args[2]), (1...500).contains(count)
        else {
            FileHandle.standardError.write(
                Data("Usage: icon-cache-memory 0|24|26|29 1...500 [switch]\n".utf8))
            exit(2)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        let appearance = NSAppearance(named: .aqua)!
        NSApplication.shared.appearance = appearance
        IconCache.setDarkSurface(false)
        for path in paths { precondition(FileManager.default.fileExists(atPath: path)) }
        var result: [String: Any] = [:]
        appearance.performAsCurrentDrawingAppearance {
            result = measure(count: count, points: CGFloat(points), transitions: args.contains("switch"))
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(bytes: data, encoding: .utf8)!)
    }
}
