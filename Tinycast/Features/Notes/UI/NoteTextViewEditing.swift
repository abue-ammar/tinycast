import Foundation

@MainActor
protocol NoteTextViewEditing: AnyObject {
    var rendersMarkdown: Bool { get }
    var markdown: NoteMarkdown { get }
    func focusChanged()
    func appearanceChanged()
    func dragSelectionEnded()
}
