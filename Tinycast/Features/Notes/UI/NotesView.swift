import SwiftUI

struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // The band above is the title bar; AppKit must not inset the content a second time.
        .ignoresSafeArea()
        .onChange(of: notes.showsFormattingBar && notes.hasActiveNote) { _, shown in
            if !shown { notes.closeHeadingMenu() }
        }
    }

    /// Lies over the real title bar and leaves its presses alone, so the system drags the window.
    private var titleBar: some View {
        HStack(spacing: 0) {
            Color.clear
                .overlay { NoteTitlebarDragRegion(onDoubleClick: notes.moveToTopRight) }
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
                onSourceChange: notes.updateSource,
                onCharacterCountChange: notes.updateCharacterCount,
                onFormattingChange: notes.updateFormatting,
                onReady: notes.editorReady
            )
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
        characterCount
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.noteFooterHeight)
    }

    private var characterCount: some View {
        Text(notes.characterCountLabel)
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textTertiary)
            .lineLimit(1)
            .accessibilityLabel("\(notes.characterCount) characters in this note")
    }
}

private struct NoteTitlebarDragRegion: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NoteTitlebarDragView {
        let view = NoteTitlebarDragView()
        view.onDoubleClick = onDoubleClick
        return view
    }
    func updateNSView(_ view: NoteTitlebarDragView, context: Context) {
        view.onDoubleClick = onDoubleClick
    }
}

/// Measures the band only: macOS 27.2 starts no move from `performDrag(with:)`.
private final class NoteTitlebarDragView: NSView {
    var onDoubleClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        (window as? NotesPanel)?.claimsTitleBarDoubleClick = { [weak self] event in
            self?.claimDoubleClick(event) ?? false
        }
    }

    private func claimDoubleClick(_ event: NSEvent) -> Bool {
        guard let window, bounds.contains(convert(event.locationInWindow, from: nil)),
            // The traffic lights sit inside the band; a double-click on one stays theirs.
            !(window.contentView?.superview?.hitTest(event.locationInWindow) is NSButton)
        else { return false }
        onDoubleClick?()
        return true
    }
}

/// The title bar's trailing controls: the launcher's footer capsule, with glyphs instead of pills.
private struct NoteTitlebarActions: View {
    @Environment(NotesCoordinator.self) private var notes

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            action(
                "plus", String(localized: "Create Note"), String(localized: "Create Note  ⌘N"),
                notes.createNote)
            action(
                "rectangle.stack", String(localized: "Browse Notes"),
                String(localized: "Browse Notes  ⌘P"), notes.searchNotes)
            action(
                "folder", String(localized: "Open Notes Folder"),
                String(localized: "Open Notes Folder  ⌘O"), notes.openNotesFolder)
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
