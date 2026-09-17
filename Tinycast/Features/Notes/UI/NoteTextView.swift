import AppKit

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?
    weak var editing: NoteTextViewEditing?
    /// True during `mouseDown`'s drag loop; revealing mid-drag would shift text under the pointer.
    private(set) var isDragSelecting = false

    /// Tracked here because the window still names this view first responder while it resigns.
    private var isFirstResponder = false
    private var keyObservers: [NotificationToken] = []

    override var undoManager: UndoManager? { editorUndoManager }

    var isFocused: Bool { isFirstResponder && window?.isKeyWindow == true }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isFirstResponder = true
        editing?.focusChanged()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isFirstResponder = false
        editing?.focusChanged()
        return true
    }

    /// The panel keeps its first responder while another app is active, so key state is focus too.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers = []
        guard let window else { return }
        let center = NotificationCenter.default
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.editing?.focusChanged() }
            }
            return NotificationToken(token, center: center)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editing?.appearanceChanged()
    }
}
