import Foundation

@main
struct FileSearchPerformance {
    static func main() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let arguments = Array(CommandLine.arguments.dropFirst())
        let queries = arguments.isEmpty ? ["a", "e", "swift", "pdf", "project"] : arguments

        print("File search service latency; the palette adds a 120 ms debounce")
        print("Home: \(homeDirectory.path)")
        for query in queries {
            guard let expression = FileSearchQuery.expression(for: query) else { continue }
            var samples: [Double] = []
            var first = 0.0
            var resultCount = 0
            for run in 0..<6 {
                let start = ContinuousClock.now
                let results = try FileSearchService.search(
                    query: query, expression: expression, homeDirectory: homeDirectory)
                let elapsed = milliseconds(start.duration(to: .now))
                if run == 0 {
                    first = elapsed
                } else {
                    samples.append(elapsed)
                }
                resultCount = results.count
            }
            let ordered = samples.sorted()
            let label = query.padding(toLength: 12, withPad: " ", startingAt: 0)
            let metrics = String(
                format: "first %7.2f ms  repeat median %7.2f ms  max %7.2f ms  %3d results",
                first, ordered[ordered.count / 2], ordered.last ?? 0, resultCount)
            print("\(label) \(metrics)")
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
