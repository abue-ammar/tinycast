import SwiftUI

/// A dictionary page: headword, then numbered senses hung off a shared gutter, then its sections.
struct DictionaryEntryView: View {
    @Environment(\.metrics) private var metrics
    let entry: DictionaryEntry

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.spacing.md) {
                ForEach(entry.blocks.indices, id: \.self) { index in
                    DictionaryBlockView(block: entry.blocks[index], leadsPage: index == 0)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, metrics.spacing.xxl)
            .padding(.top, metrics.spacing.md)
            .padding(.bottom, metrics.spacing.xxl)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        // A new term starts at its headword, not wherever the last one was scrolled to.
        .id(entry.term)
    }
}

private struct DictionaryBlockView: View {
    @Environment(\.metrics) private var metrics
    let block: DictionaryEntry.Block
    let leadsPage: Bool

    /// Sense numbers hang in it, so every definition, bullet and note starts on one line.
    private var gutter: CGFloat { metrics.spacing.xxl }
    private var textColumn: CGFloat { gutter + metrics.spacing.sm }

    var body: some View {
        switch block {
        case .headword(let word, let homograph, let pronunciation):
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.xxs) {
                    Text(word)
                        .font(metrics.typography.calcResult.weight(.bold))
                    if let homograph {
                        Text(homograph)
                            .font(metrics.typography.keyCap)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .baselineOffset(metrics.spacing.md)
                    }
                }
                if let pronunciation {
                    Text("| \(pronunciation) |")
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            // A homograph's page follows the one before it, so it needs the room of a new entry.
            .padding(.top, leadsPage ? 0 : metrics.spacing.xxxl)
        case .partOfSpeech(let runs):
            Text(runs.attributed(base: Theme.Colors.textSecondary))
                .font(metrics.typography.rowTrailing)
                .padding(.top, metrics.spacing.xs)
        case .sense(let number, let runs):
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                Text(number ?? "")
                    .font(metrics.typography.rowTitle.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: gutter, alignment: .trailing)
                Text(runs.attributed())
                    .font(metrics.typography.rowTitle)
            }
        case .subsense(let runs):
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                Text("•")
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(runs.attributed())
            }
            .font(metrics.typography.rowTitle)
            .padding(.leading, textColumn)
        case .note(let runs):
            Text(runs.attributed(base: Theme.Colors.textSecondary))
                .font(metrics.typography.rowTrailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.md)
                .background(noteShape.fill(Theme.Colors.cardFill))
                .overlay(noteShape.strokeBorder(Theme.Colors.cardStroke))
                .padding(.leading, textColumn)
        case .section(let title):
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(title)
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
            }
            .padding(.top, metrics.spacing.xl)
        case .phrase(let runs):
            Text(runs.attributed())
                .font(metrics.typography.rowTitle)
                .padding(.top, metrics.spacing.xs)
        case .paragraph(let runs):
            Text(runs.attributed())
                .font(metrics.typography.rowTitle)
                .padding(.leading, textColumn)
        }
    }

    private var noteShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
    }
}

extension [DictionaryEntry.Run] {
    /// Styles by intent rather than by font, so each run keeps the size its block sets.
    fileprivate func attributed(base: Color = Theme.Colors.textPrimary) -> AttributedString {
        reduce(into: AttributedString()) { result, run in
            var piece = AttributedString(run.text)
            piece.foregroundColor = base
            switch run.style {
            case .plain: break
            case .example:
                piece.inlinePresentationIntent = .emphasized
                piece.foregroundColor = Theme.Colors.textSecondary
            case .label: piece.foregroundColor = Theme.Colors.textSecondary
            case .strong:
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = Theme.Colors.textPrimary
            case .italic: piece.inlinePresentationIntent = .emphasized
            }
            result.append(piece)
        }
    }
}
