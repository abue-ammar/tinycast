import SwiftUI

struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // The band above is the title bar; AppKit must not inset the content a second time.
        .ignoresSafeArea()
    }

    /// The hosting view covers the real title bar, so the band carries its own drag handle — and
    /// the actions sit beside it rather than under it, where the handle would eat their clicks.
    private var titleBar: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .windowDraggable(true, onBegan: {}, onEnded: {})
            NoteTitlebarActions()
        }
        .frame(height: Theme.Size.noteTitlebar)
        .overlay { title }
    }

    private var title: some View {
        Text(notes.activeTitle)
            .font(Theme.Typography.noteTitle)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Size.noteTitleInset)
            .allowsHitTesting(false)
    }

    /// The switcher is its own window now, so this window only ever shows one of two things.
    @ViewBuilder
    private var content: some View {
        if notes.hasActiveNote {
            editorSurface
        } else {
            emptyState
        }
    }

    private var editorSurface: some View {
        VStack(spacing: 0) {
            NoteEditorView(
                input: notes.editorInput,
                onSourceChange: notes.updateSource,
                onCharacterCountChange: notes.updateCharacterCount,
                onReady: notes.editorReady
            )
            .overlay(alignment: .topLeading) { placeholder }
            footer
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if notes.isActiveNoteEmpty {
            Text("Start writing…")
                .font(.body)
                .foregroundStyle(Theme.Colors.textTertiary)
                // Matches the text container inset exactly, so the caret sits on the placeholder.
                .padding(.horizontal, Theme.Size.noteEditorInset)
                .padding(.vertical, Theme.Size.noteEditorTopInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: "text.page", size: Theme.Size.noteEmptyGlyph)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No Notes")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Create Note", action: notes.createNote)
                .buttonStyle(.plain)
                .font(Theme.Typography.bar)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.barButtonHeight)
                .frosted(in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        Text(notes.characterCountLabel)
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.noteFooterHeight)
            .accessibilityLabel("\(notes.characterCountLabel) in this note")
    }
}
