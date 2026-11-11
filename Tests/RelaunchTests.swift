import AppKit

@main
@MainActor
struct RelaunchTests {
    private static var failures = 0

    static func main() {
        if Bundle.main.infoDictionary?["RelaunchFixtureRoot"] != nil {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.prohibited)
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        Task {
            do {
                try await testTermination(relaunch: false)
                try await testTermination(relaunch: true)
            } catch {
                check("fixture completed", false)
                print(error)
            }
            print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
            exit(failures == 0 ? 0 : 1)
        }
        RunLoop.main.run()
    }

    private static func check(_ name: String, _ condition: Bool) {
        if !condition { failures += 1; print("FAIL: \(name)") }
    }

    private static func testTermination(relaunch: Bool) async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("tinycast-relaunch-\(UUID())")
        let app = root.appendingPathComponent("Fixture's App.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let bundleID = "com.tinycast.relaunch-test.\(UUID().uuidString.lowercased())"
        let process = Process()
        try files.createDirectory(at: macOS, withIntermediateDirectories: true)
        defer {
            if process.isRunning { process.terminate() }
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                running.forceTerminate()
            }
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            try? files.removeItem(at: root)
        }
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleExecutable": "Fixture",
            "CFBundleName": "Relaunch Fixture", "CFBundlePackageType": "APPL",
            "LSUIElement": true, "NSPrincipalClass": "NSApplication",
            "RelaunchFixtureRoot": root.path, "RelaunchFixtureEnabled": relaunch
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = macOS.appendingPathComponent("Fixture")
        guard let source = Bundle.main.executableURL else { throw CocoaError(.fileReadNoSuchFile) }
        try files.copyItem(at: source, to: executable)
        guard try await runProgram("/usr/bin/codesign", ["--force", "--sign", "-", app.path]) == 0
        else { throw CocoaError(.fileReadCorruptFile) }
        process.executableURL = executable
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let exited = await waitUntil { !process.isRunning }
        check("the original process terminates after async cleanup", exited)
        guard exited else { return }
        check("the original process exits successfully", process.terminationStatus == 0)
        func events() -> [String] {
            (try? String(contentsOf: root.appendingPathComponent("events"), encoding: .utf8))?
                .split(separator: "\n").map(String.init) ?? []
        }
        let first = events().filter { $0.hasPrefix("first.") }
        check(
            "repeated termination runs cleanup and teardown once",
            first == [
                "first.start", "first.request-returned", "first.cleanup-start", "first.repeat-deferred",
                "first.heartbeat", "first.cleanup-end", "first.flush-start", "first.flush-end",
                "first.teardown"
            ])
        guard relaunch else { return }
        let responsive = await waitUntil { events().contains("second.heartbeat") }
        check("the relaunched process responds on the main actor", responsive)
        guard responsive else { return }
        check("the old process exited before the new process started", !events().contains("second.overlap"))
        check(
            "reopening the same bundle succeeds",
            try await runProgram("/usr/bin/open", [app.path]) == 0)
        let completed = await waitUntil { events().contains("second.teardown") }
        check("the new process handles reopen and terminates normally", completed)
        let second = events().filter { $0.hasPrefix("second.") }
        check("the helper launches one new process", second.filter { $0 == "second.start" }.count == 1)
        check("the relaunch counts as a user launch", second.contains("second.user-launch"))
        check("the new process handles an AppKit reopen event", second.contains("second.reopen"))
        let stopped = await waitUntil {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
        check("the relaunched fixture leaves no running application", stopped)
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(6)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private static func runProgram(_ executable: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

@MainActor
final class AppCore {
    static let shared = AppCore()
    let activationPolicy = ActivationPolicy()
    private let root: URL
    private var stage = "first"

    private init() {
        guard let path = Bundle.main.infoDictionary?["RelaunchFixtureRoot"] as? String
        else { preconditionFailure("Missing fixture root") }
        root = URL(fileURLWithPath: path)
    }

    func start(launchedByUser: Bool) {
        let pidFile = root.appendingPathComponent("first.pid")
        if let value = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(value) {
            stage = "second"
            if kill(pid, 0) == 0 { record("overlap") }
        } else {
            do {
                try String(getpid()).write(to: pidFile, atomically: true, encoding: .utf8)
            } catch { preconditionFailure("Could not record fixture PID: \(error)") }
        }
        record("start")
        if stage == "first" {
            Task { @MainActor in
                RunLoop.main.perform(inModes: [.common]) {
                    MainActor.assumeIsolated { NSApp.terminate(nil) }
                }
                record("request-returned")
            }
        } else {
            if launchedByUser { record("user-launch") }
            Task { @MainActor in record("heartbeat") }
        }
    }

    func stopDictationForTermination() async {
        record("cleanup-start")
        if stage == "first" {
            Task { @MainActor in
                let reply = NSApp.delegate?.applicationShouldTerminate?(NSApp)
                record(reply == .terminateLater ? "repeat-deferred" : "repeat-rejected")
                record("heartbeat")
            }
        }
        try? await Task.sleep(for: .milliseconds(150))
        record("cleanup-end")
    }

    func flushNotesForTermination() async {
        record("flush-start")
        try? await Task.sleep(for: .milliseconds(50))
        record("flush-end")
    }

    func prepareForTermination() {
        record("teardown")
        if stage == "first", Bundle.main.infoDictionary?["RelaunchFixtureEnabled"] as? Bool == true {
            RelaunchRunner.relaunchAfterExit(Bundle.main.bundleURL)
        }
    }

    func handleReopen() {
        record("reopen")
        if stage == "second" { NSApp.terminate(nil) }
    }

    func handleOpenURL(_ url: URL) {}

    private func record(_ event: String) {
        let file = root.appendingPathComponent("events")
        if !FileManager.default.fileExists(atPath: file.path) {
            _ = FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\(stage).\(event)\n".utf8))
        } catch { preconditionFailure("Could not record fixture event: \(error)") }
    }
}

@MainActor
final class ActivationPolicy {
    let hasOpenWindows = false
    func closeAll() {}
}
