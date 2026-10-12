import Foundation

/// The default roots never raise a privacy prompt; any others are given as arguments.
@main
struct FileSearchPerformance {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let scopes = arguments.isEmpty ? ["/System", "/Applications", "/Library", "/usr"] : arguments
        let policy = FileSearchPolicy(
            scopes: scopes, ignorePatterns: [],
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        let url = FileManager.default.temporaryDirectory.appending(path: "file-search-performance.bin")
        defer { try? FileManager.default.removeItem(at: url) }

        let roots = FileIndexCrawler.roots(of: policy)
        var start = ContinuousClock.now
        let listings = FileIndexCrawler.Crawl(roots: roots, policy: policy)
            .run(workers: min(ProcessInfo.processInfo.activeProcessorCount, 8))
        let crawled = milliseconds(start.duration(to: .now))
        start = .now
        try FileIndexSnapshot.write(
            listings, roots: roots, eventID: 0, fingerprint: policy.fingerprint, to: url)
        let written = milliseconds(start.duration(to: .now))
        guard let snapshot = FileIndexSnapshot(contentsOf: url) else { fatalError("unreadable index") }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let index = FileIndex()
        index.replace(with: snapshot, policy: policy)

        print("Roots: \(roots.map(\.path).joined(separator: " "))")
        print(
            String(
                format: "%d entries  crawl %.0f ms  write %.0f ms  index %.1f MB",
                index.itemCount, crawled, written, Double(size) / 1_048_576))
        measure("(recent)") { index.recent(filter: .all).count }
        for query in ["a", "e", "swift", "pdf", "project", "main.rs", "info plist", "résumé"] {
            let prepared = FileSearchQuery.prepare(query)!
            measure(query) { index.search(prepared, filter: .all).count }
        }
        let images = FileSearchQuery.prepare("icon")!
        measure("icon [Images]") { index.search(images, filter: .images).count }
    }

    private static func measure(_ label: String, _ run: () -> Int) {
        var samples: [Double] = []
        var count = 0
        for _ in 0..<10 {
            let start = ContinuousClock.now
            count = run()
            samples.append(milliseconds(start.duration(to: .now)))
        }
        let first = samples.removeFirst()
        samples.sort()
        print(
            label.padding(toLength: 16, withPad: " ", startingAt: 0)
                + String(
                    format: "first %6.2f ms  median %6.2f ms  max %6.2f ms  %3d results",
                    first, samples[samples.count / 2], samples.last ?? 0, count))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
