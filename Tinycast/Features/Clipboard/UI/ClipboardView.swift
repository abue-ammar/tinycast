import AppKit
import SwiftUI

struct ClipboardList: View {
    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem) -> Void
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
                                imageURL: store.imageURL(for: item), slot: slot
                            )
                            .selectionFrame(item.id == selectedID)
                            .contentShape(Rectangle())
                            // Simultaneous gestures, and the light catcher: `.contextMenu` stalls.
                            .onTapGesture { onSelect(item) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(item)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(item) }
                        }
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
    let item: ClipboardItem
    let selected: Bool
    let imageURL: URL?
    /// This row's ⌘-digit, or nil when it is not among the first ten visible pins.
    let slot: Character?
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            thumbnail(item.colorValue)
            Text(previewText)
                .font(Theme.Typography.menuRow)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let slot, palette.commandHeld {
                HStack(spacing: Theme.Spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }

    private var previewText: String {
        switch item.kind {
        // Cap before trimming: never walk a multi-MB clipboard string per row.
        case .text:
            return String((item.text ?? "").prefix(200)).trimmingCharacters(
                in: .whitespacesAndNewlines)
        case .image: return "Image"
        case .file: return item.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "File"
        }
    }

    @ViewBuilder
    private func thumbnail(_ color: ColorValue?) -> some View {
        switch item.kind {
        case .text:
            // A colour states itself, so it takes the tile a glyph would otherwise fill.
            if let color {
                ColorSwatch(color: color)
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            } else {
                glyphTile("doc.text")
            }
        case .image:
            AsyncThumbnail(url: imageURL, maxPixel: 64) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            } placeholder: {
                glyphTile("photo")
            }
        case .file:
            AsyncThumbnail(url: fileURL, maxPixel: 64, source: .file) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            } placeholder: {
                glyphTile(fileKind.systemImage)
            }
        }
    }

    private var fileURL: URL? { item.filePath.map { URL(fileURLWithPath: $0) } }

    private var fileKind: ClipboardFileKind {
        item.filePath.map { ClipboardFileKind.of(path: $0) } ?? .other
    }

    /// A symbol on a rounded tile, sized so text and image rows share one shape.
    private func glyphTile(_ systemName: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
            .fill(Theme.Colors.controlSurface)
            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 12))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            )
    }
}

/// A downsampled thumbnail, decoding misses off the main thread.
private struct AsyncThumbnail<Content: View, Placeholder: View>: View {
    /// ImageIO for a blob we hold; QuickLook for a referenced file, which may be any type.
    enum Source {
        case image
        case file

        func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
            switch self {
            case .image: return ImageThumbnail.cached(url, maxPixel: maxPixel)
            case .file: return FilePreviewThumbnailer.cached(url, maxPixel: maxPixel)
            }
        }

        func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
            switch self {
            case .image: return await ImageThumbnail.loadAsync(url, maxPixel: maxPixel)
            case .file: return await FilePreviewThumbnailer.loadAsync(url, maxPixel: maxPixel)
            }
        }
    }

    let url: URL?
    let maxPixel: CGFloat
    var source: Source = .image
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
    /// The preview pane is ~460pt wide, so 900px stays crisp at 2× without over-decoding.
    private static let previewMaxPixel: CGFloat = 900

    let item: ClipboardItem?
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                ClipboardInfoSection(item: item, imageURL: store.imageURL(for: item))
            }
            .padding(.horizontal, 12)
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
            } else {
                ScrollView {
                    Text(item.text ?? "")
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        case .image:
            AsyncThumbnail(url: store.imageURL(for: item), maxPixel: Self.previewMaxPixel) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
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
    let item: ClipboardItem
    let imageURL: URL?

    @State private var details = Details()

    private struct Details: Equatable, Sendable {
        var characters: Int?
        var words: Int?
        var pixelSize: CGSize?
        var fileBytes: Int?
        var typeName: String?
        var fileExists = true
    }

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var icon: NSImage?
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Information")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: Theme.Spacing.lg)
                        if let icon = row.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.callout)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .padding(.top, Theme.Spacing.xl)
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
            let isColor = item.colorValue != nil
            rows.append(InfoRow(label: "Type", value: isColor ? "Color" : "Text"))
            // A colour's own notations are the pane above; its length is not what you came for.
            if !isColor {
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
        details = await Task.detached(priority: .userInitiated) {
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
                details.fileExists = FileManager.default.fileExists(atPath: filePath)
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                details.fileBytes = values?.fileSize
                details.typeName = values?.contentType?.localizedDescription
            }
            return details
        }.value
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
