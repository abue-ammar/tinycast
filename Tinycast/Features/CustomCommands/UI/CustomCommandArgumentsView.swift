import SwiftUI

/// The command it will run, and one row per value it still wants.
struct CustomCommandArgumentsView: View {
    @Environment(\.metrics) private var metrics
    let session: CustomCommandArgumentSession

    private static let markSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            if let command = session.command {
                header(command)
            }
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                ForEach(Array(session.progress.enumerated()), id: \.offset) { index, entry in
                    row(entry.argument, value: entry.value, position: index + 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md * 2)
        .padding(.top, metrics.spacing.md)
        .padding(.bottom, metrics.spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ command: CustomCommand) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(command.name)
                .font(metrics.typography.rowTitle.weight(.semibold))
            Text(command.command)
                .font(metrics.typography.code)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// `position` is the shell variable the value lands in, so the row explains the script.
    private func row(
        _ argument: CustomCommandArgument, value: String?, position: Int
    ) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            Image(systemName: value == nil ? "circle" : "checkmark.circle.fill")
                .font(.system(size: Self.markSize))
                .foregroundStyle(value == nil ? Theme.Colors.textTertiary : Theme.Colors.success)
            Text("$\(position)")
                .font(metrics.typography.code)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(argument.name)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let value {
                Text(value.isEmpty ? "—" : value)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if argument.isOptional {
                Text("optional")
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
