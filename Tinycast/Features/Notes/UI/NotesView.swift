import SwiftUI

struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(AppSettings.self) private var settings

    private var metrics: InterfaceMetrics { settings.unscaledMetrics }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // The band above is the title bar; AppKit must not inset the content a second time.
        .ignoresSafeArea()
        .onChange(of: notes.showsFormattingBar && notes.hasActiveNote) { _, shown in
            if !shown { notes.closeHeadingMenu() }
        }
    }

    /// The hosting view hides the real title bar, so this band drags the window itself.
    private var titleBar: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .windowDraggable(true)
            NoteTitlebarActions()
        }
        .frame(height: Theme.Size.noteTitlebar)
        .overlay { title }
    }

    private var title: some View {
        Text(notes.activeTitle)
            .font(metrics.typography.noteTitle)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Size.noteTitleInset)
            .allowsHitTesting(false)
    }

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
                rendersMarkdown: notes.rendersMarkdown,
                typography: settings.noteTypography,
                onSourceChange: notes.updateSource,
                onCharacterCountChange: notes.updateCharacterCount,
                onFormattingChange: notes.updateFormatting,
                onReady: notes.editorReady
            )
            .overlay(alignment: .topLeading) { placeholder }
            if notes.showsFormattingBar {
                formattingBand
            } else {
                footer
            }
        }
    }

    /// The count hides first, and the band keeps the offered width so the bar never widens a note.
    private var formattingBand: some View {
        HStack(spacing: Theme.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                characterCount
                Color.clear.frame(width: 0, height: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NoteFormattingBar()
                .fixedSize()
        }
        .padding(.leading, Theme.Size.noteEditorInset)
        .padding(.trailing, Theme.Spacing.md)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        .frame(height: Theme.Size.bottomBarHeight)
    }

    @ViewBuilder
    private var placeholder: some View {
        if notes.isActiveNoteEmpty {
            Text("Start writing…")
                .font(Font(settings.noteTypography.body))
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
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Create Note", action: notes.createNote)
                .buttonStyle(.plain)
                .font(metrics.typography.bar)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.barButtonHeight)
                .frosted(in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        characterCount
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.noteFooterHeight)
    }

    private var characterCount: some View {
        Text(notes.characterCountLabel)
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textTertiary)
            .lineLimit(1)
            .accessibilityLabel("\(notes.characterCountLabel) in this note")
    }
}

/// The title bar's trailing controls: the launcher's footer capsule, with glyphs instead of pills.
private struct NoteTitlebarActions: View {
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
