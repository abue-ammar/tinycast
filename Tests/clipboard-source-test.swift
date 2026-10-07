import AppKit

@main
@MainActor
struct ClipboardSourceTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        generationsStaySeparate()
        malformedEventsAreIgnored()
        historyIsBoundedAndResettable()
        unbundledWritersStayUnknown()
        excludedParentsCoverTheirHelpers()
        liveStreamTracksOnlyItsBoard()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func message(_ generation: Int, pid: Int32, board: String = "Apple CFPasteboard general") -> String {
        "\(board) has new generation \(generation) with owner <client> - process: fixture - pid: \(pid) - uuid: fixture"
    }

    static func generationsStaySeparate() {
        var history = ClipboardSourceHistory()
        let board = "Apple CFPasteboard general"
        history.record(message(42, pid: 100), pasteboardName: board)
        history.record(message(41, pid: 200), pasteboardName: board)
        expect(history.writers[42] == 100, "a late event never replaces the latest generation's writer")
        expect(history.writers[41] == 200, "out-of-order generations retain their own writers")
        expect(history.writers[43] == nil, "an unseen generation never borrows the previous writer")
        history.record(message(42, pid: 300, board: "other"), pasteboardName: board)
        expect(history.writers[42] == 100, "another pasteboard cannot change the general board's writer")
    }

    static func malformedEventsAreIgnored() {
        var history = ClipboardSourceHistory()
        let board = "Apple CFPasteboard general"
        for value in [
            message(1, pid: 0), message(1, pid: -1),
            "\(board) has new generation 1 - pid: 999999999999999999999 - uuid: x",
            "\(board) has new generation 999999999999999999999 - pid: 1 - uuid: x",
            "\(board) has new generation 1 without a writer",
            "\(board) has new generation text - pid: 1 - uuid: x"
        ] {
            history.record(value, pasteboardName: board)
        }
        expect(history.writers.isEmpty, "missing, malformed, overflowing and invalid writer fields are ignored")
    }

    static func historyIsBoundedAndResettable() {
        var history = ClipboardSourceHistory()
        let board = "Apple CFPasteboard general"
        for generation in 0...ClipboardSourceHistory.capacity {
            history.record(message(generation, pid: 100), pasteboardName: board)
        }
        expect(history.writers.count == ClipboardSourceHistory.capacity, "writer metadata has a fixed memory bound")
        expect(history.writers[0] == nil, "the oldest generation is evicted")
        expect(history.writers[ClipboardSourceHistory.capacity] == 100, "the current writer survives eviction")
        history.reset()
        expect(history.writers.isEmpty, "a new capture session starts without stale writer metadata")
    }

    static func excludedParentsCoverTheirHelpers() {
        guard let helper = ClipboardSourceMonitor.source(
            bundleID: "com.apple.Passwords.MenuBarExtra",
            bundleURL: URL(fileURLWithPath:
                "/System/Applications/Passwords.app/Contents/Library/LoginItems/PasswordsMenuBarExtra.app"))
        else {
            expect(false, "the Passwords helper resolves its bundle identity")
            return
        }
        expect(helper.bundleID == "com.apple.Passwords.MenuBarExtra", "attribution keeps the actual helper's ID")
        expect(helper.bundleIDs.contains("com.apple.Passwords"), "the helper also identifies its containing app")
        expect(
            helper.isDisabled(in: ["com.apple.Passwords"], explicitBundleID: nil),
            "excluding Passwords blocks its menu helper")
        expect(
            helper.isDisabled(in: ["com.apple.Passwords.MenuBarExtra"], explicitBundleID: nil),
            "a helper can also be excluded directly")
        expect(
            helper.isDisabled(in: ["com.apple.Passwords"], explicitBundleID: "com.apple.finder"),
            "an explicit source cannot bypass a writer exclusion")
        expect(
            !helper.isDisabled(in: ["com.apple.finder"], explicitBundleID: nil),
            "the app in front does not become the writer")
        let finder = ClipboardSource(bundleIDs: ["com.apple.finder"])
        expect(
            finder.isDisabled(in: ["com.apple.Passwords"], explicitBundleID: "com.apple.Passwords"),
            "explicit source exclusions still apply")
    }

    static func unbundledWritersStayUnknown() {
        expect(
            ClipboardSourceMonitor.source(bundleID: nil, bundleURL: nil) == nil,
            "a process with no bundle identity is unknown")
        expect(
            ClipboardSourceMonitor.source(
                bundleID: nil, bundleURL: URL(fileURLWithPath: "/private/tmp/tinycast-unbundled-writer")) == nil,
            "a registered unbundled executable is still unknown")
        let helper = ClipboardSourceMonitor.source(
            bundleID: nil,
            bundleURL: URL(fileURLWithPath:
                "/System/Applications/Passwords.app/Contents/Library/LoginItems/PasswordsMenuBarExtra.app"))
        expect(
            helper?.bundleIDs.contains("com.apple.Passwords") == true,
            "a containing app supplies identity when the process has no bundle ID")
    }

    static func liveStreamTracksOnlyItsBoard() {
        let board = NSPasteboard.withUniqueName()
        let other = NSPasteboard.withUniqueName()
        defer {
            board.releaseGlobally()
            other.releaseGlobally()
        }
        let monitor = ClipboardSourceMonitor(pasteboardName: board.name.rawValue)
        monitor.start()
        expect(monitor.isActive, "the native live stream is available")
        guard monitor.isActive else { return }
        defer { monitor.stop() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        board.clearContents()
        board.setString("source fixture", forType: .string)
        let generation = board.changeCount
        waitForWriter(monitor, generation: generation)
        expect(
            monitor.writerPID(for: generation) == ProcessInfo.processInfo.processIdentifier,
            "a real pasteboard generation resolves to its actual writer PID")
        for _ in 0..<3 {
            other.clearContents()
            other.setString("other board fixture", forType: .string)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        expect(
            monitor.writerPID(for: other.changeCount) == nil
                && monitor.writerPID(for: generation) == ProcessInfo.processInfo.processIdentifier,
            "a different board cannot populate the monitored board's generations")
        board.clearContents()
        board.setString("queued fixture", forType: .string)
        monitor.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        expect(
            !monitor.isActive && monitor.writerPID(for: generation) == nil,
            "stop invalidates the stream and clears its metadata")
        expect(monitor.writerPID(for: board.changeCount) == nil, "callbacks queued before stop cannot repopulate history")
        monitor.start()
        expect(monitor.isActive && monitor.writerPID(for: generation) == nil, "restart does not revive old generations")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        board.clearContents()
        board.setString("restarted fixture", forType: .string)
        waitForWriter(monitor, generation: board.changeCount)
        expect(
            monitor.writerPID(for: board.changeCount) == ProcessInfo.processInfo.processIdentifier,
            "restart tracks fresh generations")
    }

    static func waitForWriter(_ monitor: ClipboardSourceMonitor, generation: Int) {
        for _ in 0..<40 {
            if monitor.writerPID(for: generation) != nil { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
