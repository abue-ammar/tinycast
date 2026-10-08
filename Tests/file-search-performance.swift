import Darwin
import Foundation

@main
struct FileSearchPerformance {
    static func main() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let arguments = Array(CommandLine.arguments.dropFirst())
        let queries =
            arguments.isEmpty
            ? ["a", "e", "swift", "pdf", "project", "main", "readme", "agents md", "ext:swift palette"]
            : arguments
        // The second list is deliberately heavy, so the run prices pattern matching during the walk.
        let policies = [
            (
                "shipped",
                FileSearchPolicy(
                    scopes: FileSearchScope.defaultScopes, ignorePatterns: [],
                    homeDirectory: homeDirectory)
            ),
            (
                "+patterns",
                FileSearchPolicy(
                    scopes: FileSearchScope.defaultScopes,
                    ignorePatterns: ["*.tmp", "*.log", "**/[Cc]ache/**", "**/Logs/**", "vendor"],
                    homeDirectory: homeDirectory)
            )
        ]

        print("File search latency; the palette adds a 120 ms debounce before a typed query")
        print("Home: \(homeDirectory.path)")
        for (label, policy) in policies {
            let plan = FileIndexScanner.plan(for: policy)
            let before = footprint()
            var index = FileNameIndex()
            let walk = milliseconds { index = FileIndexScanner.build(plan) }
            print(
                String(
                    format: "%@ walk %7.1f ms  %7d entries  %6d folders  footprint +%.1f MB",
                    label.padding(toLength: 10, withPad: " ", startingAt: 0), walk,
                    index.entryCount, index.directoryCount, (footprint() - before) / 1_048_576))
            let relist = [FileIndexScanner.Change(path: plan.roots[0], isRecursive: false)]
            var copy = index
            let refresh = milliseconds { _ = FileIndexScanner.refresh(&copy, changes: relist, plan: plan) }
            print(String(format: "%@ refresh of a root folder %.2f ms", label, refresh))

            measure("\(label) (recents)") {
                (try? FileSearchService.recent(policy: policy).count) ?? 0
            }
            for raw in queries {
                measure("\(label) \(raw)") {
                    let now = Date()
                    let query = FileNameQuery(raw, homeDirectory: homeDirectory, now: now)
                    return index.search(
                        query, filter: .all, now: UInt32(now.timeIntervalSince1970),
                        limit: FileNameQuery.resultLimit, homeDirectory: homeDirectory
                    ).count
                }
            }
        }
    }

    private static func measure(_ name: String, _ run: () -> Int) {
        var samples: [Double] = []
        var first = 0.0
        var resultCount = 0
        for attempt in 0..<6 {
            let elapsed = milliseconds { resultCount = run() }
            if attempt == 0 { first = elapsed } else { samples.append(elapsed) }
        }
        let ordered = samples.sorted()
        let metrics = String(
            format: "first %7.2f ms  repeat median %7.2f ms  max %7.2f ms  %3d results",
            first, ordered[ordered.count / 2], ordered.last ?? 0, resultCount)
        print("\(name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(metrics)")
    }

    private static func milliseconds(_ work: () -> Void) -> Double {
        let start = ContinuousClock.now
        work()
        let components = start.duration(to: .now).components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) : 0
    }
}
