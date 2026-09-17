import Foundation

/// What `NoteTextView` asks of the editor that owns it: rendering state and lifecycle calls.
@MainActor
protocol NoteTextViewEditing: AnyObject {
    func focusChanged()
    func appearanceChanged()
}
