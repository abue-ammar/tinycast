import AppKit

@main
@MainActor
enum ClipboardSelectionBenchmark {
    static let cap = ClipboardManager.maxCapturedFiles

    static func board(_ urls: [URL], legacy: Bool) -> NSPasteboard {
        let board = NSPasteboard.withUniqueName()
        if urls.isEmpty { return board }
        if legacy {
            let type = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            board.declareTypes([type], owner: nil)
            precondition(board.setPropertyList(urls.map(\.path), forType: type))
        } else {
            precondition(board.writeObjects(urls as [NSURL]))
        }
        return board
    }

    static func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let time = start.duration(to: .now).components
        return Double(time.seconds) * 1_000 + Double(time.attoseconds) / 1e15
    }

    static func cpu() -> Double {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
    }

    static func verify(_ urls: [URL], expected: [String]?, roots: [String], legacy: Bool) {
        let pasteboard = board(urls, legacy: legacy)
        defer { pasteboard.releaseGlobally() }
        precondition(ClipboardManager.fileURLs(on: pasteboard, volatileRoots: roots) == expected)
    }

    static func fixtures() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-file-benchmark-\(UUID().uuidString)", isDirectory: true)
        let durable = directory.appendingPathComponent("durable", isDirectory: true)
        let volatile = directory.appendingPathComponent("volatile", isDirectory: true)
        try FileManager.default.createDirectory(at: durable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: volatile, withIntermediateDirectories: true)
        for index in 0..<10_000 {
            try Data([120]).write(to: durable.appendingPathComponent("f\(index).txt"))
        }
        let staged = volatile.appendingPathComponent("staged.txt")
        try Data([120]).write(to: staged)
        for (name, target) in [
            ("durable-link", durable.appendingPathComponent("f0.txt")),
            ("volatile-link", staged),
            ("broken-link", directory.appendingPathComponent("absent.txt"))
        ] {
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent(name), withDestinationURL: target)
        }
        return directory
    }

    static func main() throws {
        let directory = try fixtures()
        defer { try? FileManager.default.removeItem(at: directory) }
        let durable = (0..<10_000).map { directory.appendingPathComponent("durable/f\($0).txt") }
        let volatile = directory.appendingPathComponent("volatile/staged.txt")
        var volatileRoot = directory.appendingPathComponent("volatile").resolvingSymlinksInPath().path
        if volatileRoot.hasPrefix("/private/") { volatileRoot.removeFirst("/private".count) }
        let roots = [volatileRoot + "/"]
        let missing = directory.appendingPathComponent("missing.txt")
        let durableLink = directory.appendingPathComponent("durable-link")
        let volatileLink = directory.appendingPathComponent("volatile-link")
        let brokenLink = directory.appendingPathComponent("broken-link")
        for legacy in [false, true] {
            verify([], expected: nil, roots: roots, legacy: legacy)
            verify([missing, volatile, volatileLink, brokenLink], expected: nil, roots: roots, legacy: legacy)
            let valid = [durableLink] + Array(durable.prefix(40))
            let mixed = Array(repeating: missing, count: 40) + [volatile, volatileLink, brokenLink] + valid
            verify(
                mixed, expected: Array(valid.prefix(cap).map(\.standardizedFileURL.path).reversed()),
                roots: roots, legacy: legacy)
            for count in [1, cap - 1, cap, cap + 1] {
                let urls = Array(durable.prefix(count))
                verify(
                    urls, expected: Array(urls.prefix(cap).map(\.path).reversed()), roots: roots,
                    legacy: legacy)
            }
        }
        let text = NSPasteboard.withUniqueName()
        text.declareTypes([.string], owner: nil)
        text.setString("https://example.com/report.pdf", forType: .string)
        precondition(ClipboardManager.fileURLs(on: text, volatileRoots: roots) == nil)
        text.releaseGlobally()

        var results: [[String: Any]] = []
        for legacy in [false, true] {
            for (workload, count) in [
                ("durable", cap), ("durable", 1_000), ("durable", 10_000),
                ("missing", 10_000), ("rejected-prefix", 1_000)
            ] {
                let urls =
                    workload == "missing"
                    ? Array(repeating: missing, count: count)
                    : (workload == "rejected-prefix" ? Array(repeating: missing, count: 40) : [])
                        + Array(durable.prefix(count))
                let pasteboard = board(urls, legacy: legacy)
                let expected: [String]? =
                    workload == "missing"
                    ? nil
                    : Array(durable.prefix(min(count, cap)).map(\.path).reversed())
                precondition(ClipboardManager.fileURLs(on: pasteboard, volatileRoots: roots) == expected)
                let iterations = 5
                let startCPU = cpu()
                let start = ContinuousClock.now
                for _ in 0..<iterations {
                    autoreleasepool {
                        precondition(
                            ClipboardManager.fileURLs(on: pasteboard, volatileRoots: roots) == expected)
                    }
                }
                let wall = milliseconds(start) / Double(iterations)
                let cpuTime = (cpu() - startCPU) / Double(iterations)
                pasteboard.releaseGlobally()
                results.append([
                    "workload": workload, "files": count, "format": legacy ? "legacy" : "file-url",
                    "iterations": iterations, "wall_ms_per_call": wall,
                    "cpu_ms_per_call": cpuTime, "exact_output_passed": true
                ])
            }
        }
        for legacy in [false, true] {
            for count in [cap, 10_000] {
                let urls = Array(durable.prefix(count))
                let pasteboard = board(urls, legacy: legacy)
                precondition(PasteboardFiles.urls(on: pasteboard) == urls)
                let iterations = 5
                let startCPU = cpu()
                let start = ContinuousClock.now
                for _ in 0..<iterations {
                    autoreleasepool { precondition(PasteboardFiles.urls(on: pasteboard) == urls) }
                }
                let wall = milliseconds(start) / Double(iterations)
                let cpuTime = (cpu() - startCPU) / Double(iterations)
                pasteboard.releaseGlobally()
                results.append([
                    "workload": "uncapped-reader", "files": count,
                    "format": legacy ? "legacy" : "file-url", "iterations": iterations,
                    "wall_ms_per_call": wall, "cpu_ms_per_call": cpuTime,
                    "exact_output_passed": true
                ])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data([10]))
    }
}

@MainActor
final class AppSettings {
    var clipboardDisabledApps: Set<String> = []
}

final class NotificationToken {
    init(_ observer: Any, center: NotificationCenter) {}
}
