import SwiftUI

/// Raycast-style progress and interactive transformation screen inside Tinycast's palette.
struct AITransformScreenView: View {
    let session: AITransformSession
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onRetry: () -> Void

    @State private var isShowingDiff: Bool = true
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

                    if case .completed = session.phase {
                        if !session.originalSelection.isEmpty {
                            Button(action: { session.toggleDiff() }) {
                                HStack(spacing: 3) {
                                    Image(
                                        systemName: session.isShowingDiff
                                            ? "text.badge.checkmark" : "plusminus"
                                    )
                                    .font(.caption2)
                                    Text(session.isShowingDiff ? "Diff" : "Text")
                                        .font(.caption2.weight(.medium))
                                }
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    session.isShowingDiff
                                        ? Theme.Colors.selection : Theme.Colors.controlSurface,
                                    in: .capsule
                                )
                                .foregroundStyle(
                                    session.isShowingDiff ? Theme.Colors.textPrimary : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle differences (⌘D)")
                        }

                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy output (⌘C)")
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
                        if session.isShowingDiff && !session.originalSelection.isEmpty {
                            diffView(original: session.originalSelection, modified: output)
                        } else {
                            Text(formattedOutput(output))
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Theme.Spacing.xs)
                        }
                    }
                    .transition(.opacity)
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
                    shortcutChip("Insert", keys: ["↵"])
                    shortcutChip("Copy", keys: ["⌘", "C"])
                    if !session.originalSelection.isEmpty {
                        shortcutChip(session.isShowingDiff ? "Text View" : "Diff View", keys: ["⌘", "D"])
                    }
                    shortcutChip("Regenerate", keys: ["⌘", "R"])
                case .failed:
                    shortcutChip("Retry", keys: ["↵"])
                case .idle:
                    shortcutChip("Transform", keys: ["↵"])
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
        .onAppear {
            isShowingDiff = session.preset?.showDiff ?? true
        }
    }
    private func shortcutChip(_ label: String, keys: [String]) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(keys, id: \.self) { key in
                    KeyCapChip(text: key, style: .outline)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Markdown formatting preserving whitespace and inline bold/code/italics.
    @ViewBuilder
    private func diffView(original: String, modified: String) -> some View {
        let chunks = AIDiffEngine.diff(original: original, modified: modified)
        renderChunks(chunks)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.xs)
    }

    private func renderChunks(_ chunks: [AIDiffEngine.Chunk]) -> Text {
        var combined = Text("")
        for (index, chunk) in chunks.enumerated() {
            switch chunk {
            case .equal(let text):
                combined = combined + Text(text).foregroundColor(Theme.Colors.textPrimary)

            case .deleted(let text):
                combined =
                    combined
                    + Text(text)
                    .strikethrough(true, color: Color.red.opacity(0.85))
                    .foregroundColor(Color.red.opacity(0.85))

                if index + 1 < chunks.count {
                    if case .inserted(let nextText) = chunks[index + 1],
                        !text.hasSuffix(" ") && !nextText.hasPrefix(" ")
                    {
                        combined = combined + Text(" ")
                    }
                }

            case .inserted(let text):
                combined =
                    combined
                    + Text(text)
                    .bold()
                    .foregroundColor(Color.green)
            }
        }
        return combined
    }
    private func formattedOutput(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
