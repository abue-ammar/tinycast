import SwiftUI

/// What the argument form shows: the command it will run, and one row per value it still wants.
/// docs/features/custom-commands.md
struct CustomCommandArgumentsView: View {
    let session: CustomCommandArgumentSession

    private static let markSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if let command = session.command {
                header(command)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(session.progress.enumerated()), id: \.offset) { index, entry in
                    row(entry.argument, value: entry.value, position: index + 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ command: CustomCommand) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(command.name)
                .font(Theme.Typography.rowTitle.weight(.semibold))
            Text(command.command)
                .font(Theme.Typography.code)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// `position` is the shell variable the value lands in, so the row explains the script it feeds.
    private func row(
        _ argument: CustomCommandArgument, value: String?, position: Int
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: value == nil ? "circle" : "checkmark.circle.fill")
                .font(.system(size: Self.markSize))
                .foregroundStyle(value == nil ? Theme.Colors.textTertiary : Theme.Colors.success)
            Text("$\(position)")
                .font(Theme.Typography.code)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(argument.name)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let value {
                Text(value.isEmpty ? "—" : value)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if argument.isOptional {
                Text("optional")
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
