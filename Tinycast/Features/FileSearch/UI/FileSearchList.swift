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
    let onDropped: () -> Void

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
                            .onRowClick(
                                select: { onSelect(result) }, activate: { onActivate(result) },
                                drag: result.rowDrag(dropped: onDropped)
                            )
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

extension FileSearchResult {
    /// The row's own fitted tile, which is warm by the time a pointer can reach it.
    func rowDrag(dropped: @escaping () -> Void) -> RowDrag {
        RowDrag(item: { .file(url, image: IconCache.cachedFitted(forFile: id)) }, dropped: dropped)
    }
}

struct FileSearchRow: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    let selected: Bool
    let showsLocation: Bool
    @State private var image: NSImage?
    @State private var hovered = false

    init(result: FileSearchResult, selected: Bool, showsLocation: Bool = false) {
        self.result = result
        self.selected = selected
        self.showsLocation = showsLocation
        _image = State(initialValue: IconCache.cachedFitted(forFile: result.id))
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// A folder is named by where it sits: half the hits are some `src` or `Tinycast`.
    private var label: Text {
        guard !showsLocation, result.isDirectory, !result.parentName.isEmpty else {
            return Text(result.name)
        }
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
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            label
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if showsLocation {
                Text(result.parentPath)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if showsLocation {
                Text(result.isDirectory ? "Folder" : "File")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
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
