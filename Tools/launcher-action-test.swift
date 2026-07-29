import Foundation

@main
private enum LauncherActionTest {
    private static func expect(
        _ actual: LauncherModifiedReturnAction?, _ expected: LauncherModifiedReturnAction?,
        _ label: String, passed: inout Int, failed: inout Int
    ) {
        if actual == expected {
            passed += 1
        } else {
            failed += 1
            print(
                "❌ \(label): expected \(String(describing: expected)), got \(String(describing: actual))"
            )
        }
    }

    static func main() {
        var passed = 0
        var failed = 0
        expect(
            LauncherActionPolicy.modifiedReturnAction(for: .application), .showInFinder,
            "applications reveal in Finder", passed: &passed, failed: &failed)
        expect(
            LauncherActionPolicy.modifiedReturnAction(for: .systemSettings), .showInFinder,
            "System Settings panes reveal in Finder", passed: &passed, failed: &failed)
        expect(
            LauncherActionPolicy.modifiedReturnAction(for: .command), nil,
            "synthetic commands have no Finder shortcut", passed: &passed, failed: &failed)

        print("Launcher action policy: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
