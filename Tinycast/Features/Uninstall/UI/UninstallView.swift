import AppKit
import SwiftUI

struct UninstallList: View {
    let results: [UninstallCandidate]
    let selectedID: UninstallCandidate.ID?
    let summary: String
    /// Changes only on keyboard nav / reset, so mouse selection never yanks the scroll position.
    let scroll: ScrollIntent
    let onSelect: (UninstallCandidate) -> Void
    let onToggle: (UninstallCandidate) -> Void
    let onActions: (UninstallCandidate) -> Void
    @Environment(UninstallSession.self) private var session

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: summary, isFirst: true)
                    ForEach(results) { candidate in
                        UninstallRow(
                            candidate: candidate,
                            selected: candidate.id == selectedID,
                            checked: session.selection?.isChecked(candidate.id) ?? false,
                            onToggle: { onToggle(candidate) }
                        )
                        .id(candidate.id)
                        .selectionFrame(candidate.id == selectedID)
                        .contentShape(Rectangle())
                        // Simultaneous, so single-click select never waits on the double-click.
                        .onTapGesture { onSelect(candidate) }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                onSelect(candidate)
                                onToggle(candidate)
                            }
                        )
                        .onRightClick { onActions(candidate) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            // On the first row, snap to the origin so the summary header shows too.
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
        .onDisappear { IconCache.purgeFitted() }
    }
}

private struct UninstallRow: View {
    let candidate: UninstallCandidate
    let selected: Bool
    let checked: Bool
    let onToggle: () -> Void
    @State private var hovered = false

    /// Selection wins over hover when a row is both.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var glyph: String {
        if candidate.isLocked { return "lock.fill" }
        return checked ? "checkmark.square.fill" : "square"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // Smaller glyph, same `rowIcon` slot, so titles line up at one x across modes.
            SymbolImage(name: glyph, size: Theme.Size.checkbox)
                .foregroundStyle(candidate.isLocked ? Theme.Colors.textTertiary : .primary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .contentShape(Rectangle())
                // Only the checkbox toggles; the rest of the row selects.
                .onTapGesture(perform: onToggle)
                .tooltip(candidate.lockReason)
            Text(candidate.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                .layoutPriority(1)
            Text(candidate.locationLabel)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let label = candidate.evidence.label {
                Text(label)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.md)
            Text(candidate.size?.formatted ?? "")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
            FileIconView(path: candidate.path)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
        }
        .opacity(candidate.isLocked ? 0.55 : 1)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

private struct FileIconView: View {
    let path: String
    @State private var image: NSImage?

    init(path: String) {
        self.path = path
        _image = State(initialValue: IconCache.cachedFitted(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        .task(id: IconRequest(path)) {
            if let warm = IconCache.cachedFitted(forFile: path) {
                image = warm
                return
            }
            image = await IconCache.loadFittedAsync(forFile: path)
        }
    }
}
