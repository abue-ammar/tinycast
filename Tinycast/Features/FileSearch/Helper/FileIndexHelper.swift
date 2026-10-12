import CoreServices
import Foundation

/// A process of its own, so every byte the crawl allocates leaves when it exits.
@main
nonisolated enum FileIndexHelper {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3,
            let request = try? JSONDecoder().decode(
                FileSearchPolicy.Request.self, from: Data(arguments[2].utf8))
        else { exit(2) }
        let policy = FileSearchPolicy(request)
        let roots = FileIndexCrawler.roots(of: policy)
        guard !roots.isEmpty else { exit(2) }

        let eventID = FSEventsGetCurrentEventId()
        let crawl = FileIndexCrawler.Crawl(roots: roots, policy: policy)
        let reporter = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        reporter.schedule(deadline: .now(), repeating: .milliseconds(100))
        reporter.setEventHandler { @Sendable in report(crawl.listed) }
        reporter.resume()
        let listings = crawl.run(workers: min(ProcessInfo.processInfo.activeProcessorCount, 8))
        reporter.cancel()

        do {
            try FileIndexSnapshot.write(
                listings, roots: roots, eventID: eventID, fingerprint: policy.fingerprint,
                to: URL(filePath: arguments[1]))
        } catch {
            exit(1)
        }
        report(crawl.listed)
    }

    private static func report(_ count: Int) {
        try? FileHandle.standardOutput.write(contentsOf: Data("\(count)\n".utf8))
    }
}
