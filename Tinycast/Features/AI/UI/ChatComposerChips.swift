import AppKit
import SwiftUI

/// The MCP `@server` pill: its glyph alone, since the handle it confirms is already in the text.
struct ComposerChip: View {
    @Environment(\.metrics) private var metrics
    let symbol: String
    let label: String

    /// Load-bearing: part of the strip width that `searchFieldWidth(for:)` takes out of the field.
    static func width(_ metrics: InterfaceMetrics) -> CGFloat {
        metrics.size.chatAttachmentGlyph + metrics.spacing.sm * 2
    }

    var body: some View {
        Image(systemName: symbol)
            .font(metrics.typography.chip)
            .symbolRenderingMode(.hierarchical)
            .frame(width: metrics.size.chatAttachmentGlyph)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(Capsule().fill(Theme.Colors.controlSurface))
            .tooltip("Offers only \(label)'s tools", edge: .bottom)
            .accessibilityLabel("Addressed to \(label)")
    }
}

/// The window composer's staged file: an image shows itself, a document its name, both an ✕.
struct AttachmentChip: View {
    @Environment(\.metrics) private var metrics
    let attachment: ChatAttachment
    let onRemove: () -> Void

    @State private var hovered = false

    /// Past this a name is middle-truncated, so a row of chips stays readable at a glance.
    private static let nameLimit = 16

    /// Every kind is labelled: a bare thumbnail beside an ✕ reads as two stray marks, not a pill.
    private static func shortened(_ name: String) -> String {
        guard name.count > nameLimit else { return name }
        return "\(name.prefix(nameLimit - 7))…\(name.suffix(6))"
    }

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            leading
            Text(Self.shortened(attachment.name))
                .font(metrics.typography.chip)
                .lineLimit(1)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(
                        width: metrics.size.chatAttachmentRemove,
                        height: metrics.size.chatAttachmentRemove
                    )
                    .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(attachment.name)")
        }
        // Inset under the inner gap, so the thumbnail reads as filling the pill.
        .padding(.horizontal, metrics.size.chatAttachmentInset)
        .padding(.vertical, metrics.size.chatAttachmentInset)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.attachmentChip, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attached \(attachment.name)")
    }

    @ViewBuilder private var leading: some View {
        switch attachment.kind {
        case .image:
            ComposerThumbnail(data: attachment.preview, id: attachment.id)
        case .pdf, .text:
            Image(systemName: attachment.glyph)
                .font(metrics.typography.chip)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(
                    width: metrics.size.chatAttachmentThumb,
                    height: metrics.size.chatAttachmentThumb)
        }
    }
}

/// Decoded once per attachment: `ForEach` keys on its id, so a per-keystroke re-render reuses it.
private struct ComposerThumbnail: View {
    @Environment(\.metrics) private var metrics
    let data: Data?
    let id: UUID

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(metrics.typography.chip)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: metrics.size.chatAttachmentThumb, height: metrics.size.chatAttachmentThumb)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
        .task(id: id) { image = data.flatMap(NSImage.init(data:)) }
    }
}
