import Foundation

@main
struct FileViewerPolicyTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            failures += 1
            print("FAIL: \(message)")
            return
        }
        print("PASS: \(message)")
    }

    static func main() {
        let finder = FileViewerPolicy.finderBundleID
        let qspace = "com.jinghaoshe.qspace.pro"
        let forkLift = "com.binarynights.ForkLift"

        expect(
            FileViewerPolicy.target(configuredBundleID: qspace, systemBundleID: forkLift)
                == .application(bundleID: qspace),
            "an explicit file manager outranks the system viewer")
        expect(
            FileViewerPolicy.target(configuredBundleID: "  \n", systemBundleID: qspace)
                == .application(bundleID: qspace),
            "a blank override follows the system viewer")
        expect(
            FileViewerPolicy.target(configuredBundleID: nil, systemBundleID: nil) == .finder,
            "no choice at either level falls back to Finder")
        expect(
            FileViewerPolicy.target(configuredBundleID: finder, systemBundleID: qspace) == .finder,
            "choosing Finder explicitly outranks the system viewer")
        expect(
            FileViewerPolicy.resolvedTarget(
                configuredBundleID: qspace, systemBundleID: forkLift,
                isAvailable: { $0 != qspace }) == .application(bundleID: forkLift),
            "a missing override falls back to the system viewer")
        expect(
            FileViewerPolicy.resolvedTarget(
                configuredBundleID: qspace, systemBundleID: forkLift,
                isAvailable: { $0 == finder }) == .finder,
            "a missing override and system viewer fall back to Finder")
        expect(
            FileViewerPolicy.isConfiguredApplicationMissing(
                configuredBundleID: qspace, isAvailable: { $0 != qspace }),
            "a missing explicit application is reported to Settings")
        expect(
            !FileViewerPolicy.isConfiguredApplicationMissing(
                configuredBundleID: finder, isAvailable: { $0 != finder }),
            "Finder is built in, never reported missing")

        print(
            failures == 0
                ? "File viewer tests passed" : "\(failures) file viewer tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
