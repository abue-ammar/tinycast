import AppKit

/// Where a task's checkbox sits, shared by drawing and hit testing so what shows is what clicks.
enum NoteCheckboxGeometry {
    /// One list level's marker slot: the shared marker width, grown with the body text size.
    static func slot(bodyPointSize: CGFloat) -> CGFloat {
        (Theme.Size.markdownListMarker * bodyPointSize / NSFont.systemFontSize).rounded()
    }

    /// The box in fragment-local coordinates whose x origin is the container's left edge.
    static func rect(level: Int, firstLineHeight: CGFloat, bodyPointSize: CGFloat) -> CGRect {
        let side = bodyPointSize.rounded()
        let slot = slot(bodyPointSize: bodyPointSize)
        return CGRect(
            x: CGFloat(level) * slot + (slot - side) / 2, y: (firstLineHeight - side) / 2,
            width: side, height: side)
    }
}
