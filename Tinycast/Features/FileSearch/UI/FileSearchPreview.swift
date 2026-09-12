import SwiftUI

/// The pane beside the results: the file itself over what the filesystem says about it.
struct FileSearchPreview: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult?

    var body: some View {
        if let result {
            VStack(alignment: .leading, spacing: 0) {
                // Sized before the block below it, which then scrolls in whatever is left.
                FileSearchPreviewStage(result: result)
                    .aspectRatio(Theme.Size.previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                ScrollView {
                    FileSearchInfoSection(result: result)
                }
            }
            .padding(.horizontal, metrics.spacing.xl)
        } else {
            Color.clear
        }
    }
}

/// The file itself, once the selection has held long enough to be worth opening.
private struct FileSearchPreviewStage: View {

    @Environment(\.metrics) private var metrics
    @Environment(PaletteState.self) private var palette
    let result: FileSearchResult
    @State private var isLive = false

    /// Long enough that arrow-keying a list never opens a preview it is about to drop.
    private static let settle = Duration.milliseconds(150)

    /// Every teardown trigger in one key, so no `onChange` races the task.
    private struct LiveKey: Equatable {
        let id: FileSearchResult.ID
        let isVisible: Bool
        let isCovered: Bool
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
    }

    var body: some View {
        stage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, metrics.spacing.xl)
            .task(
                id: LiveKey(
                    id: result.id, isVisible: palette.isVisible,
                    isCovered: palette.fileSearchQuickLook)
            ) {
                isLive = false
                guard palette.isVisible, !palette.fileSearchQuickLook else { return }
                try? await Task.sleep(for: Self.settle)
                isLive = !Task.isCancelled
            }
    }

    @ViewBuilder private var stage: some View {
        if result.isDirectory {
            Image(systemName: "folder")
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
        } else if isLive {
            if FileSearchMediaPlayer.plays(result.url) {
                FileSearchMediaPlayer(url: result.url).clipShape(card)
            } else {
                QuickLookSurface(url: result.url)
                    .clipShape(card)
                    .overlay(card.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            }
        } else {
            Color.clear
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
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
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
