// Standalone test for the extension host bridge's clipboard behaviour, compiling the real
// sources rather than copies. The ordering regression: a "paste in active app" host call
// must hide the palette before ⌘V is synthesised, or the text lands in the palette's own
// search field instead of the app the palette displaced.
import AppKit

@main
@MainActor
struct ExtHostTests {
    static var failures = 0
    static var passes = 0

    static func main() async {
        await textPasteRecordsHideBeforePaste()
        await filePasteRecordsHideBeforePaste()
        await copyLeavesTheWindowAlone()
        checkPasteboardCarriesTheText()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Recording context

    /// Protocol-conformant stub; only `closeMainWindow` and the storage namespace are live.
    final class RecordingContext: ExtensionHostContext {
        var activeExtensionName: String? { "fixture" }
        var activeLaunchType: ExtensionLaunchType { .userInitiated }
        var pasteTarget: NSRunningApplication?
        var applicationURLs: [URL] { [] }
        let storage = ExtensionStorage(directory: FileManager.default.temporaryDirectory)

        private(set) var events: [String] = []

        func closeMainWindow(clearRootSearch: Bool) { events.append("closeWindow") }
        func reopenPalette() {}
        func popToRoot() {}
        func clearSearchBar() {}
        func openPreferences(scope: String) {}
        func updateCommandMetadata(subtitle: String?) {}
        func present(toast: ExtensionToast) -> Int { return 1 }
        func update(toast id: Int, with toast: ExtensionToast) {}
        func hide(toast id: Int) {}
        func showHUD(_ text: String) {}
        func confirmAlert(_ alert: ExtensionAlert) async -> Bool { true }
        func openWithPicker(path: String) async {}
        func launch(
            command: String, extensionName: String?, arguments: [String: String],
            fallbackText: String?, launchType: ExtensionLaunchType,
            launchContext: [String: RenderValue]
        ) throws {}
        func launch(_ link: ExtensionDeepLink) throws {}
        func authorizeOAuth(options: ExtensionOAuthAuthorizeOptions) async throws
            -> ExtensionOAuthAuthorizeResult
        {
            ExtensionOAuthAuthorizeResult(authorizationCode: "", accessToken: nil, state: nil)
        }
        func getOAuthTokens(providerId: String) -> String? { nil }
        func setOAuthTokens(providerId: String, tokens: String) {}
        func removeOAuthTokens(providerId: String) {}
    }

    static func scopedBridge() -> (ExtensionHostBridge, RecordingContext) {
        let context = RecordingContext()
        let store = ClipboardStore(directory: FileManager.default.temporaryDirectory)
        return (ExtensionHostBridge(clipboardStore: store).scoped(to: context), context)
    }

    static func pasteArguments(_ payload: [String: RenderValue]) -> [RenderValue] {
        [.object(payload)]
    }

    // MARK: - Checks

    /// The regression: paste must hide the palette (handing focus back) before ⌘V.
    static func textPasteRecordsHideBeforePaste() async {
        let (bridge, context) = scopedBridge()
        do {
            _ = try await bridge.perform(
                api: "clipboard", method: "paste",
                arguments: pasteArguments(["text": .string("€")]))
        } catch {
            check("a text paste performs without error", false, "\(error)")
            return
        }
        // Drain the deferred ⌘V (a no-op without Accessibility in CI) before judging order.
        try? await Task.sleep(for: .milliseconds(200))
        check(
            "a text paste hides the palette window",
            context.events.contains("closeWindow"),
            "events: \(context.events.joined(separator: ","))")
        check(
            "a text paste hides the window before any keystroke can land",
            context.events.first == "closeWindow",
            "events: \(context.events.joined(separator: ","))")
    }

    static func filePasteRecordsHideBeforePaste() async {
        let (bridge, context) = scopedBridge()
        do {
            _ = try await bridge.perform(
                api: "clipboard", method: "paste",
                arguments: pasteArguments(["file": .string("/")]))
        } catch {
            check("a file paste performs without error", false, "\(error)")
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        check(
            "a file paste hides the palette window before any keystroke",
            context.events.first == "closeWindow",
            "events: \(context.events.joined(separator: ","))")
    }

    static func copyLeavesTheWindowAlone() async {
        let (bridge, context) = scopedBridge()
        do {
            _ = try await bridge.perform(
                api: "clipboard", method: "copy",
                arguments: pasteArguments(["text": .string("kept")]))
        } catch {
            check("a copy performs without error", false, "\(error)")
            return
        }
        check(
            "a copy leaves the palette window alone",
            !context.events.contains("closeWindow"),
            "events: \(context.events.joined(separator: ","))")
    }

    static func checkPasteboardCarriesTheText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("€", forType: .string)
        check(
            "the pasteboard round-trips the pasted text",
            pasteboard.string(forType: .string) == "€")
    }

    static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : "\n      \(detail)")")
        }
    }
}
