import SwiftUI

struct NoteSwitcherView: View {
    let onContentHeight: (CGFloat) -> Void
    @Environment(NotesCoordinator.self) private var notes
    @FocusState private var searchFocused: Bool

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            results
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: surface)
        .clipShape(surface)
        .onAppear(perform: focusSearch)
        .onChange(of: notes.switcherFocusRevision) { _, _ in focusSearch() }
        .onChange(of: notes.visibleNotes) { _, _ in
            notes.reconcileSwitcherSelection()
        }
        .onKeyPress(.downArrow) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.moveSwitcherSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.moveSwitcherSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
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
                .onExitCommand { notes.closeSwitcher() }
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
        .frame(height: Theme.Size.noteSearchHeight)
    }

    @ViewBuilder
    private var results: some View {
        if notes.visibleNotes.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                SymbolImage(
                    name: notes.isSearching ? "clock" : "text.page",
                    size: Theme.Size.noteGlyph
                )
                .foregroundStyle(Theme.Colors.textSecondary)
                Text(notes.isSearching ? "Searching notes…" : "No notes found")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.noteSwitcherEmptyHeight)
            .measuredHeight(onContentHeight)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes.visibleNotes) { summary in
                            NoteSwitcherRow(
                                summary: summary,
                                selected: notes.switcherSelection == summary.id,
                                editing: notes.switcherEditingID == summary.id,
                                titleDraft: notes.switcherTitleDraftBinding,
                                onActivate: { notes.activateSwitcherNote(summary.id) },
                                onBeginRename: {
                                    notes.beginSwitcherRename(summary)
                                    searchFocused = false
                                },
                                onCommitRename: notes.commitSwitcherRename,
                                onCancelRename: notes.cancelSwitcherRename,
                                onTrash: { notes.trash(summary.id) }
                            )
                            .id(summary.id)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .measuredHeight(onContentHeight)
                }
                // The search row is a sibling, not a floating bar, so only the bottom edge fades.
                .overflowFade()
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
}

extension View {
    fileprivate func measuredHeight(_ report: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            report($0)
        }
    }
}

private struct NoteSwitcherRow: View {
    let summary: NoteSummary
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

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: "text.page", size: Theme.Size.noteGlyph)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            if editing {
                TextField("Note title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit(onCommitRename)
                    .onExitCommand(perform: onCancelRename)
            } else {
                Text(summary.displayTitle)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.md)
            if !editing, selected || hovered {
                rowButton(title: "Rename \(summary.displayTitle)", symbol: "pencil", action: onBeginRename)
                rowButton(title: "Move \(summary.displayTitle) to Trash", symbol: "trash", action: onTrash)
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            onActivate()
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction {
            guard !editing else { return }
            onActivate()
        }
        .accessibilityAction(named: "Rename \(summary.displayTitle)") {
            guard !editing else { return }
            onBeginRename()
        }
        .accessibilityAction(named: "Move \(summary.displayTitle) to Trash") {
            guard !editing else { return }
            onTrash()
        }
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
                .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
        }
        .buttonStyle(.plain)
        .help(title)
        // The row publishes both as accessibility actions, so the buttons stay out of the tree.
        .accessibilityHidden(true)
    }
}
