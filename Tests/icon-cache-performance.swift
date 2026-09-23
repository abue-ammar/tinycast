import AppKit
import Darwin
import Foundation

@main
struct IconCachePerformance {
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        return info.phys_footprint
    }

    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 4,
            let entries = Int(arguments[1]), entries > 0,
            let points = Int(arguments[2]), points > 0,
            let scale = Int(arguments[3]), scale > 0
        else {
            fatalError("Usage: icon-cache-performance <entries> <points> <scale>")
        }
        let size = IconSize(points: CGFloat(points), scale: CGFloat(scale))
        let paths = [
            "/System/Library/CoreServices/Finder.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app",
            "/System/Applications/System Settings.app",
            "/System/Applications/Preview.app",
            "/System/Applications/Safari.app"
        ]

        let initialFootprint = footprint()
        var rowBytes = 0
        for index in 0..<entries {
            autoreleasepool {
                let image = IconCache.icon(
                    forFile: paths[index % paths.count], stamp: index + 1, size: size)
                guard let bitmap = image.representations.first as? NSBitmapImageRep else {
                    fatalError("Row icon did not rasterize")
                }
                rowBytes += bitmap.bytesPerRow * bitmap.pixelsHigh
            }
        }

        let finalFootprint = footprint()
        var heldRows = 0
        var heldFull = 0
        var heldFullBytes = 0
        for index in 0..<entries {
            let path = paths[index % paths.count]
            let stamp = index + 1
            if IconCache.cached(forFile: path, stamp: stamp, size: size) != nil { heldRows += 1 }
            if let image = IconCache.cached(forFile: path, stamp: stamp) {
                heldFull += 1
                for case let bitmap as NSBitmapImageRep in image.representations {
                    heldFullBytes += bitmap.bytesPerRow * bitmap.pixelsHigh
                }
            }
        }
        print("entries=\(entries) pixels=\(size.pixels) rowBytes=\(rowBytes) "
            + "heldRows=\(heldRows) heldFull=\(heldFull) heldFullBytes=\(heldFullBytes) "
            + "initialFootprint=\(initialFootprint) finalFootprint=\(finalFootprint)")
    }
}
