import SwiftUI

struct FileSearchList: View {

    @Environment(\.metrics) private var metrics
    let title: String
    let results: [FileSearchResult]
    let selectedID: FileSearchResult.ID?
    let scroll: ScrollIntent
    let onSelect: (FileSearchResult) -> Void
    let onActivate: (FileSearchResult) -> Void
    let onActions: (FileSearchResult) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: title, isFirst: true)
                    ForEach(results) { result in
                        FileSearchRow(result: result, selected: result.id == selectedID)
                            .selectionFrame(result.id == selectedID)
                            .contentShape(Rectangle())
                            // A click moves the preview; opening takes the second one.
                            .onTapGesture(count: 2) { onActivate(result) }
                            .onTapGesture { onSelect(result) }
                            .onRightClick { onActions(result) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
        .onDisappear { IconCache.purgeFitted() }
    }
}

private struct FileSearchRow: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    let selected: Bool
    @State private var image: NSImage?
    @State private var hovered = false

    init(result: FileSearchResult, selected: Bool) {
        self.result = result
        self.selected = selected
        _image = State(initialValue: IconCache.cachedFitted(forFile: result.id))
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// A folder is named by where it sits: half the hits are some `src` or `Tinycast`.
    private var label: Text {
        guard result.isDirectory, !result.parentName.isEmpty else { return Text(result.name) }
        let parent = Text("\(result.parentName)/").foregroundStyle(.secondary)
        return Text("\(parent)\(result.name)")
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.iconPlaceholder)
                }
            }
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            // The column is too narrow for a path beside the name; the preview states it instead.
            label
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.name)
        .accessibilityValue(result.parentPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: IconRequest(result.id)) {
            if let warm = IconCache.cachedFitted(forFile: result.id) {
                image = warm
                return
            }
            image = await IconCache.loadFittedAsync(forFile: result.id)
        }
    }
}
