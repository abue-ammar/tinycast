import SwiftUI

struct SnippetTagChip: View {
    let tag: SnippetTag
    var isBadge = false
    var remove: (() -> Void)?
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(tag.name).lineLimit(1).truncationMode(.tail)
            .font(metrics.typography.keyCap)
            .foregroundStyle(isBadge && tag.color != .gray ? tag.color.tint : Theme.Colors.textPrimary)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.trailing, remove == nil ? 0 : metrics.spacing.lg + metrics.spacing.xs)
            .padding(.vertical, isBadge ? metrics.spacing.xxs / 2 : metrics.spacing.xxs)
            .frame(height: metrics.size.keyCap + (isBadge ? 0 : metrics.spacing.xs))
            .background(
                isBadge ? tag.color.tint.opacity(Theme.Colors.tagFillOpacity) : Theme.Colors.controlSurface,
                in: RoundedRectangle(
                    cornerRadius: isBadge ? metrics.radius.keyCap : metrics.radius.barControl,
                    style: .continuous)
            )
            .overlay(alignment: .trailing) {
                if let remove {
                    Button(action: remove) {
                        SymbolImage(name: "xmark", size: metrics.spacing.md, monochrome: true)
                            .frame(width: metrics.size.keyCap, height: metrics.size.keyCap)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.trailing, metrics.spacing.xxs)
                    .accessibilityLabel("Remove tag \(tag.name)")
                }
            }
    }
}
