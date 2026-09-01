import CoreGraphics
import Foundation

@main
@MainActor
struct WorkspaceTests {
    private static var passes = 0
    private static var failures = 0

    static func main() {
        testNormalizedFrameUsesVisibleScreenCoordinates()
        testRestoredFrameScalesAndStaysReachable()
        testWorkspaceRoundTripsThroughJSON()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static func expect(_ actual: CGRect?, _ expected: CGRect, _ message: String) {
        guard actual == expected else {
            failures += 1
            print("FAIL: \(message) — got \(String(describing: actual)), expected \(expected)")
            return
        }
        passes += 1
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func testNormalizedFrameUsesVisibleScreenCoordinates() {
        let visible = CGRect(x: -1600, y: 24, width: 1600, height: 1000)
        let frame = CGRect(x: -1440, y: 124, width: 800, height: 500)

        let normalized = WindowWorkspace.NormalizedFrame(frame: frame, in: visible)

        expect(normalized?.x == 0.1, "capture stores x as a visible-frame fraction")
        expect(normalized?.y == 0.1, "capture stores y as a visible-frame fraction")
        expect(normalized?.width == 0.5, "capture stores width as a visible-frame fraction")
        expect(normalized?.height == 0.5, "capture stores height as a visible-frame fraction")
    }

    private static func testRestoredFrameScalesAndStaysReachable() {
        let normalized = WindowWorkspace.NormalizedFrame(x: 0.8, y: 0.8, width: 0.4, height: 0.4)
        let visible = CGRect(x: 100, y: -50, width: 1000, height: 500)

        expect(
            normalized.frame(in: visible), CGRect(x: 700, y: 250, width: 400, height: 200),
            "restore rescales the saved frame and clamps its trailing edges")
    }

    private static func testWorkspaceRoundTripsThroughJSON() {
        let workspace = WindowWorkspace(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!, name: "Writing",
            windows: [
                .init(
                    bundleID: "com.apple.TextEdit", screenID: 42,
                    frame: .init(x: 0.125, y: 0.25, width: 0.5, height: 0.5))
            ])

        let decoded = try? JSONDecoder().decode(
            WindowWorkspace.self, from: JSONEncoder().encode(workspace))

        expect(decoded == workspace, "workspace serialization preserves its selected app and geometry")
    }
}
