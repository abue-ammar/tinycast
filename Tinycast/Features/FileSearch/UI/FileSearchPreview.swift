import SwiftUI

/// The pane beside the results: a QuickLook still over what the filesystem says about the file.
struct FileSearchPreview: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult?

    var body: some View {
        if let result {
            VStack(alignment: .leading, spacing: 0) {
                FileSearchPreviewStage(result: result)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                FileSearchInfoSection(result: result)
            }
            .padding(.horizontal, metrics.spacing.xl)
        } else {
            Color.clear
        }
    }
}

/// One still for every kind: `representationTypes: .all` falls back to the file's own type icon.
private struct FileSearchPreviewStage: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            } else {
                Image(systemName: result.isDirectory ? "folder" : "doc")
                    .font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, metrics.spacing.xl)
        .task(id: result.id) {
            let maxPixel = metrics.size.clipboardPreviewPixel
            if let hit = FilePreviewThumbnail.cached(result.url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            image = await FilePreviewThumbnail.loadAsync(result.url, maxPixel: maxPixel)
        }
    }
}

/// The "Information" block; every disk read is gathered once, off the main actor.
private struct FileSearchInfoSection: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    @State private var details = Details()

    private struct Details: Equatable, Sendable {
        var typeName: String?
        var bytes: Int?
        var created: Date?
        var modified: Date?
    }

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// Relative day plus the time; shared, `DateFormatter` being expensive to build.
    @MainActor private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
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
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.callout)
                    .padding(.vertical, metrics.spacing.sm)
                }
            }
        }
        .padding(.top, metrics.spacing.xl)
        .task(id: result.id) { await loadDetails() }
    }

    private var rows: [InfoRow] {
        var rows = [
            InfoRow(label: "Name", value: result.name),
            InfoRow(label: "Where", value: result.parentPath),
            InfoRow(
                label: "Type",
                value: details.typeName ?? (result.isDirectory ? "Folder" : "File"))
        ]
        if let bytes = details.bytes {
            rows.append(
                InfoRow(label: "Size", value: Int64(bytes).formatted(.byteCount(style: .file))))
        }
        if let created = details.created {
            rows.append(InfoRow(label: "Created", value: Self.stampFormatter.string(from: created)))
        }
        if let modified = details.modified {
            rows.append(
                InfoRow(label: "Modified", value: Self.stampFormatter.string(from: modified)))
        }
        return rows
    }

    /// The type database spells a folder "folder"; the Type row reads like Finder's Kind.
    private nonisolated static func sentenceCased(_ name: String) -> String {
        name.prefix(1).localizedUppercase + name.dropFirst()
    }

    private func loadDetails() async {
        // Cleared first: the previous file's size must not sit under this one's name.
        details = Details()
        let url = result.url
        let isDirectory = result.isDirectory
        details = await Task.detached(priority: .userInitiated) {
            let values = try? url.resourceValues(forKeys: [
                .contentTypeKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
            ])
            return Details(
                typeName: values?.contentType?.localizedDescription.map(Self.sentenceCased),
                // A folder's own record is a few bytes, which is never what the row means.
                bytes: isDirectory ? nil : values?.fileSize,
                created: values?.creationDate,
                modified: values?.contentModificationDate)
        }.value
    }
}
