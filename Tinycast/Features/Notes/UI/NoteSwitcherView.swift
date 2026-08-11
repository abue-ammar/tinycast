import SwiftUI

struct NoteSwitcherView: View {
    @Environment(NotesCoordinator.self) private var notes
    @FocusState private var searchFocused: Bool
    @State private var editingID: NoteID?
    @State private var titleDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.Colors.separator)
            results
        }
        .onAppear(perform: focusSearch)
        .onChange(of: notes.switcherFocusRevision) { _, _ in focusSearch() }
        .onKeyPress(.downArrow) {
            notes.moveSwitcherSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            notes.moveSwitcherSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard editingID == nil else { return .ignored }
            notes.selectSwitcherNote()
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("Search notes…", text: notes.searchQueryBinding)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search Notes")
            if !notes.searchQueryBinding.wrappedValue.isEmpty {
                Button {
                    notes.searchQueryBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.noteHeaderHeight)
    }

    @ViewBuilder
    private var results: some View {
        if notes.visibleNotes.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: notes.isSearching ? "clock" : "note.text")
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(notes.isSearching ? "Searching notes…" : "No notes found")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes.visibleNotes) { summary in
                            NoteSwitcherRow(
                                summary: summary,
                                excerpt: notes.searchExcerpt(for: summary.id),
                                selected: notes.switcherSelection == summary.id,
                                editing: editingID == summary.id,
                                titleDraft: $titleDraft,
                                onActivate: { notes.select(summary.id) },
                                onBeginRename: { beginRename(summary) },
                                onCommitRename: { commitRename(summary.id) },
                                onCancelRename: cancelRename,
                                onTrash: { notes.trash(summary.id) })
                                .id(summary.id)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                .onChange(of: notes.switcherSelection) { _, selected in
                    if let selected { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
    }

    private func focusSearch() {
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }

    private func beginRename(_ summary: NoteSummary) {
        editingID = summary.id
        titleDraft = summary.title
        searchFocused = false
    }

    private func commitRename(_ id: NoteID) {
        let title = titleDraft
        editingID = nil
        notes.rename(id, to: title)
        focusSearch()
    }

    private func cancelRename() {
        editingID = nil
        focusSearch()
    }
}

private struct NoteSwitcherRow: View {
    let summary: NoteSummary
    let excerpt: String?
    let selected: Bool
    let editing: Bool
    @Binding var titleDraft: String
    let onActivate: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onTrash: () -> Void
    @State private var hovered = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "note.text")
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if editing {
                    TextField("Note title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .onSubmit(onCommitRename)
                        .onExitCommand(perform: onCancelRename)
                } else {
                    Text(summary.title)
                        .font(Theme.Typography.rowTitle)
                        .lineLimit(1)
                    Text(excerpt ?? summary.modifiedAt.formatted(.relative(presentation: .numeric)))
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            if !editing, selected || hovered {
                rowButton(title: "Rename \(summary.title)", symbol: "pencil", action: onBeginRename)
                rowButton(title: "Move \(summary.title) to Trash", symbol: "trash", action: onTrash)
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            onActivate()
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: editing ? .contain : .combine)
        .accessibilityLabel(summary.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onChange(of: editing) { _, editing in
            if editing {
                Task { @MainActor in
                    await Task.yield()
                    titleFocused = true
                }
            }
        }
    }

    private func rowButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Theme.Size.noteStatus, height: Theme.Size.noteStatus)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
