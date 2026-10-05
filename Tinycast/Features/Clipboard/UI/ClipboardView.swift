import AppKit
import SwiftUI

struct ClipboardList: View {

    @Environment(\.metrics) private var metrics
    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem) -> Void
    /// Nil when the entry has nothing left to hand over, which is reported rather than dragged.
    let onDragPayload: (ClipboardItem) -> ClipDragPayload?
    let onDropped: () -> Void
    @Environment(ClipboardStore.self) private var store

    private enum Row: Identifiable {
        case header(String)
        case item(ClipboardItem, slot: Character?)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .item(let item, _): return item.id.uuidString
            }
        }
    }

    /// Whether the selection sits on flat index 0, whose section header should stay visible.
    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    /// Pins share one header; the rest are newest-first, a header per date bucket.
    private var rows: [Row] {
        var rows: [Row] = []
        var currentTitle: String?
        var pinnedSlot = 0
        for item in results {
            let title = item.isPinned ? "Pinned" : DateBucket(for: item.createdAt).title
            if title != currentTitle {
                rows.append(.header(title))
                currentTitle = title
            }
            let slot = item.isPinned ? FavoriteSlots.digit(at: pinnedSlot) : nil
            if item.isPinned { pinnedSlot += 1 }
            rows.append(.item(item, slot: slot))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .item(let item, let slot):
                            ClipboardRow(
                                item: item, selected: item.id == selectedID,
                                imageURL: store.imageURL(for: item), slot: slot,
                                onHoverSelect: { onSelect(item) }
                            )
                            .selectionFrame(item.id == selectedID)
                            .contentShape(Rectangle())
                            // The light catcher: `.contextMenu` stalls.
                            .onRightClick { onActions(item) }
                            .onRowClick(
                                select: { onSelect(item) },
                                activate: {
                                    onSelect(item)
                                    onActivate()
                                },
                                drag: RowDrag(
                                    item: { onDragPayload(item)?.dragItem }, dropped: onDropped)
                            )
                        }
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
            // Snap to the origin on the first row so its section header shows too.
            .scrollFollowsSelection(
                scroll, row: selectedID?.uuidString, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

/// Coarse date buckets for sectioning, ordered newest-first by raw value.
enum DateBucket: Int {
    case today, yesterday, thisWeek, thisMonth, earlier

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .earlier: return "Earlier"
        }
    }

    init(for date: Date, now: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }
}

private struct ClipboardRow: View {

    @Environment(\.metrics) private var metrics
    let item: ClipboardItem
    let selected: Bool
    let imageURL: URL?
    /// This row's ⌘-digit, or nil when it is not among the first ten visible pins.
    let slot: Character?
    let onHoverSelect: () -> Void
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            thumbnail(item.colorValue)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(previewText)
                .font(metrics.typography.menuRow)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let slot, palette.commandHeld {
                HStack(spacing: metrics.spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .onHover { isHovered in
            if isHovered, palette.hoverHighlightArmed, !selected {
                onHoverSelect()
            }
        }
    }

    private var previewText: String {
        switch item.kind {
        // Cap before trimming: never walk a multi-MB clipboard string per row.
        case .text:
            return String((item.text ?? "").prefix(200)).trimmingCharacters(
                in: .whitespacesAndNewlines)
        case .image: return "Image"
        case .file:
            return item.filePath.map {
                URL(filePath: $0, directoryHint: .inferFromPath).lastPathComponent
            } ?? "File"
        }
    }

    @ViewBuilder
    private func thumbnail(_ color: ColorValue?) -> some View {
        switch item.kind {
        case .text:
            // A colour states itself, so it takes the tile a glyph would otherwise fill.
            if let color {
                ColorSwatch(color: color)
                    .frame(width: artworkSize, height: artworkSize)
            } else if item.textForm == .link {
                if let url = item.webURL, let image = LinkOGImageStore.cached(url, maxPixel: 64) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(
                            RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
                } else {
                    Image(nsImage: IconCache.symbolIcon(named: "link")).resizable()
                }
            } else if item.textForm == .email {
                Image(nsImage: IconCache.symbolIcon(named: "at")).resizable()
            } else {
                Image(nsImage: IconCache.symbolIcon(named: "doc.text")).resizable()
            }
        case .image:
            AsyncThumbnail(url: imageURL, maxPixel: 64) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(
                        RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
            } placeholder: {
                Image(nsImage: IconCache.symbolIcon(named: "photo")).resizable()
            }
        case .file:
            AsyncThumbnail(url: fileURL, maxPixel: 64, source: .file) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(
                        RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
            } placeholder: {
                Image(nsImage: IconCache.symbolIcon(named: fileKind.systemImage)).resizable()
            }
        }
    }

    // Not `fileURLWithPath:`, which stats the path: on a network mount that stalls the render.
    private var fileURL: URL? {
        item.filePath.map { URL(filePath: $0, directoryHint: .inferFromPath) }
    }

    private var fileKind: ClipboardFileKind {
        item.filePath.map { ClipboardFileKind.of(path: $0) } ?? .other
    }

    private var artworkSize: CGFloat { metrics.size.resultRowIcon * IconCache.appIconExtent }
}

/// ImageIO for a blob we hold; QuickLook for a referenced file, which may be any type.
private enum ThumbnailSource {
    case image
    case file

    func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        switch self {
        case .image: return ImageThumbnail.cached(url, maxPixel: maxPixel)
        case .file: return FilePreviewThumbnail.cached(url, maxPixel: maxPixel)
        }
    }

    func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        switch self {
        case .image: return await ImageThumbnail.loadAsync(url, maxPixel: maxPixel)
        case .file: return await FilePreviewThumbnail.loadAsync(url, maxPixel: maxPixel)
        }
    }
}

/// A downsampled thumbnail, decoding misses off the main thread.
private struct AsyncThumbnail<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    /// Not nested here: the off-main decode would carry this view's isolated `View` conformances.
    var source: ThumbnailSource = .image
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = source.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil  // show the placeholder while a new image decodes
            image = await source.loadAsync(url, maxPixel: maxPixel)
        }
    }
}

struct ClipboardPreview: View {

    @Environment(\.metrics) private var metrics
    let item: ClipboardItem?
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        if let item {
            if item.textForm == .link {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        content(for: item)
                            .frame(maxWidth: .infinity, alignment: .top)
                        ClipboardInfoSection(item: item, imageURL: store.imageURL(for: item))
                    }
                    .padding(.bottom, metrics.spacing.md)
                }
                .scrollBounceBehavior(.basedOnSize)
                .padding(.horizontal, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    content(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    ClipboardInfoSection(item: item, imageURL: store.imageURL(for: item))
                }
                .padding(.horizontal, 12)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            if let color = item.colorValue {
                ColorPreview(color: color, text: item.text ?? "")
            } else if item.textForm == .link, let text = item.text {
                LinkPreviewStage(text: text)
            } else {
                ScrollView {
                    Text(item.text ?? "")
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        case .image:
            AsyncThumbnail(url: store.imageURL(for: item), maxPixel: metrics.size.clipboardPreviewPixel) {
                image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            } placeholder: {
                Image(systemName: "photo").font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            }
        case .file:
            if let path = item.filePath { FilePreviewStage(path: path) }
        }
    }
}

/// The "Information" block; disk-touching details are gathered off the main actor.
private struct ClipboardInfoSection: View {
    @Environment(\.metrics) private var metrics
    let item: ClipboardItem
    let imageURL: URL?

    @State private var details: Details

    init(item: ClipboardItem, imageURL: URL?) {
        self.item = item
        self.imageURL = imageURL
        var initial = Details()
        if let webURL = item.webURL, let cached = LinkOGImageStore.cachedMetadata(webURL) {
            initial.linkTitle = cached.title
            initial.linkDescription = cached.description
        }
        _details = State(initialValue: initial)
    }

    private struct Details: Equatable, Sendable {
        var characters: Int?
        var words: Int?
        var pixelSize: CGSize?
        var fileBytes: Int?
        var typeName: String?
        var linkTitle: String?
        var linkDescription: String?
    }

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var icon: NSImage?
        var lineLimit: Int = 1
        var truncationMode: Text.TruncationMode = .middle
        var id: String { label }
    }

    /// Relative day plus exact time; shared, `DateFormatter` being expensive to build.
    @MainActor private static let copiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(alignment: .top, spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        if let icon = row.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        Text(row.value)
                            .lineLimit(row.lineLimit)
                            .truncationMode(row.truncationMode)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
                    .padding(.vertical, metrics.spacing.sm)
                }
            }
        }
        .padding(.top, metrics.spacing.xl)
        .task(id: item.id) { await loadDetails() }
    }

    private var rows: [InfoRow] {
        var rows: [InfoRow] = []
        if let source {
            rows.append(InfoRow(label: "Source", value: source.name, icon: source.icon))
        }
        switch item.kind {
        case .text:
            // What the entry *is*, which is what the type filter files it under.
            let typeTitle: String = {
                switch item.textForm {
                case .color: return "Color"
                case .link: return "Link"
                case .email: return "Email"
                case .plain, nil: return "Text"
                }
            }()
            rows.append(InfoRow(label: "Type", value: typeTitle))
            if item.textForm == .link {
                if let urlText = item.text {
                    rows.append(InfoRow(label: "URL", value: urlText, lineLimit: 1, truncationMode: .middle))
                }
                if let title = details.linkTitle, !title.isEmpty {
                    rows.append(InfoRow(label: "Title", value: title, lineLimit: 2, truncationMode: .tail))
                }
                if let desc = details.linkDescription, !desc.isEmpty {
                    rows.append(InfoRow(label: "Description", value: desc, lineLimit: 3, truncationMode: .tail))
                }
            } else if item.textForm != .color {
                if let characters = details.characters {
                    rows.append(InfoRow(label: "Characters", value: characters.formatted()))
                }
                if let words = details.words {
                    rows.append(InfoRow(label: "Words", value: words.formatted()))
                }
            }
        case .image:
            rows.append(InfoRow(label: "Type", value: "Image"))
            if let size = details.pixelSize {
                rows.append(
                    InfoRow(label: "Dimensions", value: "\(Int(size.width))×\(Int(size.height))"))
            }
            if let bytes = details.fileBytes {
                rows.append(
                    InfoRow(
                        label: "Size", value: Int64(bytes).formatted(.byteCount(style: .file))))
            }
        case .file:
            let path = item.filePath ?? ""
            rows.append(
                InfoRow(
                    label: "Type",
                    value: details.typeName ?? ClipboardFileKind.of(path: path).title))
            rows.append(InfoRow(label: "Path", value: (path as NSString).abbreviatingWithTildeInPath))
            if let bytes = details.fileBytes {
                rows.append(
                    InfoRow(
                        label: "Size", value: Int64(bytes).formatted(.byteCount(style: .file))))
            }
        }
        rows.append(
            InfoRow(label: "Copied", value: Self.copiedFormatter.string(from: item.createdAt)))
        return rows
    }

    /// Name and icon from the recorded bundle ID, via Launch Services and `IconCache`.
    private var source: (name: String, icon: NSImage)? {
        IconCache.observeStyle()
        guard let bundleID = item.sourceBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return (url.deletingPathExtension().lastPathComponent, IconCache.icon(forFile: url.path))
    }

    private func loadDetails() async {
        // Only a text entry: a file's `text` is its path, and counting its words says nothing.
        let text = item.kind == .text ? item.text : nil
        let url = imageURL
        let filePath = item.filePath
        let webURL = item.webURL
        if let webURL, let cached = LinkOGImageStore.cachedMetadata(webURL) {
            details.linkTitle = cached.title
            details.linkDescription = cached.description
        }
        var loaded = await Task.detached(priority: .userInitiated) {
            var details = Details()
            if let text {
                details.characters = text.count
                details.words = Self.wordCount(text)
            }
            if let url {
                details.pixelSize = ImageThumbnail.pixelSize(of: url)
                details.fileBytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            }
            if let filePath {
                let fileURL = URL(fileURLWithPath: filePath)
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                details.fileBytes = values?.fileSize
                details.typeName = values?.contentType?.localizedDescription
            }
            return details
        }.value
        if let webURL {
            if let cached = LinkOGImageStore.cachedMetadata(webURL) {
                loaded.linkTitle = cached.title
                loaded.linkDescription = cached.description
            } else {
                let meta = await LinkOGImageStore.loadMetadataAsync(webURL)
                loaded.linkTitle = meta?.title
                loaded.linkDescription = meta?.description
            }
        }
        details = loaded
    }

    /// Single pass: `split(whereSeparator:)` allocates per word, which a multi-MB copy feels.
    private nonisolated static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let separator = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !separator && !inWord { count += 1 }
            inWord = !separator
        }
        return count
    }
}
