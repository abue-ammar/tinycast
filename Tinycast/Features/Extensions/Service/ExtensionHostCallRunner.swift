import AppKit

/// What an extension asks the main app to do, for calls that need no macOS permission.
@MainActor
struct ExtensionHostCallRunner {
    let closePalette: () -> Void
    let openPermissionSettings: () -> Void
    let showMessage: (String) -> Void

    /// `showsUI` is false for a run the user didn't start, which may not touch the screen.
    func perform(
        _ call: ExtensionWire.HostCall, showsUI: Bool
    ) -> Result<String?, ExtensionWire.HostCallError> {
        guard showsUI || !Self.touchesScreen(call) else {
            return failure("A run the user didn't start shows no UI.")
        }
        switch call {
        case .copy(let text):
            return Paster.copyPlainText(text) ? .success(nil) : failure("The clipboard refused the text.")
        case .readClipboard:
            return .success(NSPasteboard.general.string(forType: .string))
        case .showHUD(let text):
            showMessage(text)
            return .success(nil)
        case .open(let url):
            guard url.scheme?.lowercased() == "https" else { return failure("Only https URLs open.") }
            return NSWorkspace.shared.open(url) ? .success(nil) : failure("The URL didn't open.")
        case .closePalette:
            closePalette()
            return .success(nil)
        case .openPermissionSettings:
            openPermissionSettings()
            return .success(nil)
        case .paste, .selectedText:
            return failure("This Tinycast can't paste or read selected text for an extension yet.")
        }
    }

    private static func touchesScreen(_ call: ExtensionWire.HostCall) -> Bool {
        switch call {
        case .showHUD, .open, .closePalette, .openPermissionSettings: true
        case .copy, .readClipboard, .paste, .selectedText: false
        }
    }

    /// Diagnostics for the extension, not text Tinycast shows, so they stay unlocalized.
    private func failure(_ message: String) -> Result<String?, ExtensionWire.HostCallError> {
        .failure(.failure(message: message))
    }
}
