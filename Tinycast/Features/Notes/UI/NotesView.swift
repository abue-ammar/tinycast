import SwiftUI

struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                header
                    .frame(height: Theme.Size.noteHeaderHeight)
                if notes.isSwitcherPresented {
                    NoteSwitcherView()
                } else {
                    NoteEditorView(
                        input: notes.editorInput,
                        onSourceChange: notes.updateSource,
                        onContentHeightChange: notes.updateEditorHeight,
                        onReady: notes.editorReady,
                        onOpenLink: notes.openLink)
                }
            }
            if notes.isFormattingPresented {
                NoteFormattingMenu(
                    selectedCommands: notes.activeFormattingCommands,
                    onSelect: notes.applyFormatting)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("notes-window"))
                    } action: { frame in
                        notes.updateFormattingFrame(frame)
                    }
                    .padding(.top, Theme.Size.noteHeaderHeight - Theme.Spacing.sm)
                    .padding(.trailing, Theme.Spacing.xl)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .coordinateSpace(name: "notes-window")
        .animation(.easeOut(duration: 0.12), value: notes.isFormattingPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.note, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: "note.text", size: Theme.Size.noteStatus)
                .foregroundStyle(Color.primary)
                .frame(width: Theme.Size.headerIconSlot)
            Button(action: notes.openSwitcher) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(notes.activeTitle)
                        .font(Theme.Typography.noteTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose Note")
            Spacer(minLength: Theme.Spacing.md)
                .windowDraggable(
                    true,
                    onBegan: {},
                    onEnded: notes.dragEnded)
            statusView
            headerButton(
                title: "Format Note",
                symbol: "textformat",
                action: notes.toggleFormatting)
            headerButton(
                title: "Create Note",
                symbol: "plus",
                action: notes.createNote)
            headerButton(
                title: "Reveal in Finder",
                symbol: "folder",
                action: notes.revealInFinder)
            headerButton(
                title: "Hide Notes",
                symbol: "xmark",
                action: notes.hide)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    @ViewBuilder
    private var statusView: some View {
        if status.actionable {
            Button(action: notes.showCurrentIssue) {
                statusSymbol
            }
            .buttonStyle(.plain)
        } else {
            statusSymbol
        }
    }

    private var statusSymbol: some View {
        SymbolImage(name: status.symbol, size: Theme.Size.noteStatus)
            .foregroundStyle(status.color)
            .frame(width: Theme.Size.noteStatus, height: Theme.Size.noteStatus)
            .accessibilityLabel(status.label)
    }

    private func headerButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Circle())
                .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
        .frosted(in: Circle())
    }

    private var status: NoteStatus {
        switch notes.state {
        case .idle, .loading:
            return NoteStatus(symbol: "clock", label: "Loading", color: Theme.Colors.textSecondary)
        case .ready:
            if notes.isDirty {
                return NoteStatus(
                    symbol: "circle.dotted",
                    label: "Waiting to Save",
                    color: Theme.Colors.textSecondary)
            }
            return NoteStatus(
                symbol: "checkmark.circle",
                label: "Saved",
                color: Theme.Colors.textSecondary)
        case .saving:
            return NoteStatus(
                symbol: "arrow.triangle.2.circlepath",
                label: "Saving",
                color: Theme.Colors.textSecondary)
        case .conflict:
            return NoteStatus(
                symbol: "exclamationmark.triangle.fill",
                label: "Save Conflict",
                color: Theme.Colors.destructive,
                actionable: true)
        case .failed:
            return NoteStatus(
                symbol: "exclamationmark.circle.fill",
                label: "Note Error",
                color: Theme.Colors.destructive,
                actionable: true)
        }
    }
}

private struct NoteStatus {
    let symbol: String
    let label: String
    let color: Color
    var actionable = false
}
