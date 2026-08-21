import SwiftUI

/// Raycast-style progress and interactive transformation screen inside Tinycast's palette.
struct AITransformScreenView: View {
    let session: AITransformSession
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Source Input Card
            if !session.originalSelection.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Label("Input", systemImage: "text.quote")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Text(session.originalSelection)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.cardFill, in: .rect(cornerRadius: Theme.Radius.row))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
            }

            // Transformation Output / Progress Card
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label(session.presetName, systemImage: AITransform.sfSymbol)
                        .font(.caption.weight(.bold))

                    Spacer()

                    if !session.currentModel.isEmpty {
                        Text(session.currentModel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.controlSurface, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                switch session.phase {
                case .idle:
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: AITransform.sfSymbol)
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text(
                            session.originalSelection.isEmpty
                                ? "Type or paste text above, then press ↵ to \(session.presetName.lowercased())."
                                : "Press ↵ to \(session.presetName.lowercased())."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.xl)
                case .processing(let model):
                    HStack(spacing: Theme.Spacing.md) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Transforming with \(model)…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                case .completed(let output, _):
                    ScrollView(.vertical) {
                        Text(formattedOutput(output))
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .failed(let error, _):
                    VStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .lineLimit(3)
                        }

                        Button("Retry", action: onRetry)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.cardFill, in: .rect(cornerRadius: Theme.Radius.row))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            )

            // Bottom Shortcuts Bar
            HStack(spacing: Theme.Spacing.md) {
                switch session.phase {
                case .completed:
                    HStack(spacing: Theme.Spacing.xs) {
                        KeyCapChip(text: "↵", style: .outline)
                        Text("Insert")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "C", style: .outline)
                        }
                        Text("Copy")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "R", style: .outline)
                        }
                        Text("Regenerate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .failed:
                    HStack(spacing: Theme.Spacing.xs) {
                        KeyCapChip(text: "↵", style: .outline)
                        Text("Retry")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .idle:
                    HStack(spacing: Theme.Spacing.xs) {
                        KeyCapChip(text: "↵", style: .outline)
                        Text("Transform")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .processing:
                    EmptyView()
                }

                Spacer()

                if case .completed = session.phase {
                    Text("Type query to refine")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Markdown formatting preserving whitespace and inline bold/code/italics.
    private func formattedOutput(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
