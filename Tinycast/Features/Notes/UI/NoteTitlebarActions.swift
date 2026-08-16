import SwiftUI

/// The title bar's trailing controls: the launcher's footer capsule, with glyphs instead of pills.
struct NoteTitlebarActions: View {
    @Environment(NotesCoordinator.self) private var notes

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            action("plus", "Create Note", "Create Note  ⌘N", notes.createNote)
            action("rectangle.stack", "Browse Notes", "Browse Notes  ⌘P", notes.searchNotes)
            action("folder", "Open Notes Folder", "Open Notes Folder  ⌘O", notes.openNotesFolder)
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
        .padding(.trailing, Theme.Spacing.md)
    }

    private func action(
        _ symbol: String,
        _ label: String,
        _ help: String,
        _ perform: @escaping () -> Void
    ) -> some View {
        BarButton(action: perform) {
            SymbolImage(name: symbol, size: Theme.Size.noteGlyph)
        }
        .accessibilityLabel(label)
        .help(help)
    }
}
