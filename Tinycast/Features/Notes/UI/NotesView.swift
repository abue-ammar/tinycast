import SwiftUI

struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Theme.Size.noteHeaderHeight)
            editorRegion
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.note, style: .continuous))
    }

    /// The editor stays mounted while the switcher overlays it, so undo history, the caret and the
    /// scroll position survive a switcher round trip.
    private var editorRegion: some View {
        NoteEditorView(
            input: notes.editorInput,
            onSourceChange: notes.updateSource,
            onContentHeightChange: notes.updateEditorHeight,
            onReady: notes.editorReady
        )
        .opacity(notes.isSwitcherPresented ? 0 : 1)
        .allowsHitTesting(!notes.isSwitcherPresented)
        .accessibilityHidden(notes.isSwitcherPresented)
        .overlay {
            if notes.isSwitcherPresented {
                NoteSwitcherView()
            }
        }
    }

    private var header: some View {
        ZStack {
            headerDragRegion(Color.clear)
            HStack(spacing: Theme.Spacing.md) {
                headerDragRegion(
                    SymbolImage(name: "text.page", size: Theme.Size.noteStatus)
                        .foregroundStyle(Color.primary)
                        .frame(width: Theme.Size.headerIconSlot))
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
                .clickableDraggable(
                    onClick: notes.openSwitcher,
                    onEnded: notes.dragEnded)
                Spacer(minLength: Theme.Spacing.md)
                if !notes.isSwitcherPresented || status.showsInSwitcher {
                    statusView
                }
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
            .padding(.leading, Theme.Spacing.xl)
            .padding(.trailing, Theme.Spacing.md)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if status.actionable {
            Button(action: notes.showCurrentIssue) {
                statusSymbol
            }
            .buttonStyle(.plain)
        } else {
            headerDragRegion(statusSymbol)
        }
    }

    private func headerDragRegion<Content: View>(_ content: Content) -> some View {
        content.windowDraggable(
            true,
            onBegan: {},
            onEnded: notes.dragEnded)
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
                    height: Theme.Size.noteHeaderButton
                )
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
                color: Theme.Colors.textSecondary,
                showsInSwitcher: false)
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
    var showsInSwitcher = true
}
