import Foundation

/// One replacement and where the selection lands afterwards, both in source coordinates.
struct NoteEditPlan: Sendable, Equatable {
    let range: NSRange
    let replacement: String
    /// Expressed against the source after the replacement.
    let selection: NSRange
}
