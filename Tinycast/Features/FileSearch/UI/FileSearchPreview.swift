import AppKit
import SwiftUI

/// The right-side preview and metadata panel for the selected file search result.
struct FileSearchPreview: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let result: FileSearchResult?

    @State private var probe: FileMetadataProbe?
    @State private var thumbnail: NSImage?

    var body: some View {
        if let result {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    previewStage(for: result)
                        .frame(maxWidth: .infinity)
                        .padding(.top, metrics.spacing.md)
                        .padding(.bottom, metrics.spacing.lg)

                    metadataSection(for: result)
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.bottom, metrics.spacing.lg)
            }
            .edgeDissolve()
            .thinScrollbar()
            .task(id: result.id) {
                thumbnail = FilePreviewThumbnail.cached(
                    result.url, maxPixel: metrics.size.clipboardPreviewPixel)
                if thumbnail == nil {
                    thumbnail = await FilePreviewThumbnail.loadAsync(
                        result.url, maxPixel: metrics.size.clipboardPreviewPixel)
                }
                probe = await Task.detached(priority: .userInitiated) {
                    FileMetadataProbe.probe(url: result.url)
                }.value
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func previewStage(for result: FileSearchResult) -> some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: previewMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            } else {
                VStack(spacing: metrics.spacing.sm) {
                    Image(systemName: result.isDirectory ? "folder" : "doc")
                        .font(.system(size: placeholderIconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: previewMaxHeight)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
            }
        }
    }

    private var previewMaxHeight: CGFloat {
        metrics.scaled(settings.fileSearchPreviewSize.maxHeight)
    }

    private var placeholderIconSize: CGFloat {
        metrics.scaled(settings.fileSearchPreviewSize.placeholderIconSize)
    }

    private struct MetadataRowItem: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    @ViewBuilder
    private func metadataSection(for result: FileSearchResult) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Metadata")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                let items = metadataItems(for: result)
                ForEach(items) { item in
                    if item.id != items.first?.id {
                        Divider()
                    }
                    HStack(spacing: metrics.spacing.md) {
                        Text(item.label)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(item.value)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
    }

    private func metadataItems(for result: FileSearchResult) -> [MetadataRowItem] {
        var items: [MetadataRowItem] = [
            MetadataRowItem(label: "Name", value: result.name),
            MetadataRowItem(label: "Where", value: result.parentPath),
            MetadataRowItem(
                label: "Type",
                value: probe?.typeName ?? (result.isDirectory ? "Folder" : "File")
            ),
        ]

        if !result.isDirectory, let bytes = probe?.fileBytes {
            items.append(MetadataRowItem(label: "Size", value: FileMetadataProbe.formatBytes(bytes)))
        }

        if let created = probe?.creationDate {
            items.append(MetadataRowItem(label: "Created", value: FileMetadataProbe.formatDate(created)))
        }

        if let modified = probe?.modificationDate {
            items.append(MetadataRowItem(label: "Modified", value: FileMetadataProbe.formatDate(modified)))
        }

        if let accessed = probe?.accessDate {
            items.append(
                MetadataRowItem(label: "Accessed", value: FileMetadataProbe.formatAccessedDate(accessed))
            )
        }

        return items
    }
}
