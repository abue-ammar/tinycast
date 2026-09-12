import AppKit

/// Where injected text is going — another app over events, or one of our own editors in process.
enum InjectionTarget {
    case external(NSRunningApplication)
    case ownEditor(any InjectableTextView)

    /// Where the keystrokes land: our panels never activate, so the frontmost app is not it.
    @MainActor
    static func current() -> InjectionTarget? {
        guard let keyWindow = NSApp.keyWindow else {
            return NSWorkspace.shared.frontmostApplication.map(InjectionTarget.external)
        }
        return (keyWindow.firstResponder as? any InjectableTextView).map(InjectionTarget.ownEditor)
    }

    /// What the palette covered when it was summoned: one of our editors, or the app behind it.
    @MainActor
    static func behindPalette(
        ownWindow: NSWindow?, app: NSRunningApplication?
    ) -> InjectionTarget? {
        if let editor = ownWindow?.firstResponder as? any InjectableTextView {
            return .ownEditor(editor)
        }
        return app.map(InjectionTarget.external)
    }

    /// Hands the caret back — after a modal argument prompt, or an expansion that went nowhere.
    @MainActor
    func restoreFocus() {
        switch self {
        case .external(let app):
            guard !app.isTerminated else { return }
            app.activate()
        case .ownEditor(let editor):
            editor.window?.makeFirstResponder(editor)
        }
    }

    var externalApp: NSRunningApplication? {
        guard case .external(let app) = self else { return nil }
        return app
    }

    var ownEditor: (any InjectableTextView)? {
        guard case .ownEditor(let editor) = self else { return nil }
        return editor
    }
}
