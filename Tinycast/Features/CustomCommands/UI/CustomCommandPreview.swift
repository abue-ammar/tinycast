import SwiftUI

struct CustomCommandPreview: View {
    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    let command: CustomCommand?

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private func information(for command: CustomCommand) -> [InfoRow] {
        var rows = [
            InfoRow(label: "Run In", value: command.workingDirectory ?? "Home folder"),
            InfoRow(label: "Output", value: command.showsOutput ? "Show output" : "Silent")
        ]
        if !command.arguments.isEmpty {
            let arguments = command.arguments.enumerated().map { index, argument in
                let name = "\(CustomCommandArgument.fieldID(at: index)) · \(argument.name)"
                return argument.isOptional ? name + " (optional)" : name
            }
            rows.append(InfoRow(label: "Arguments", value: arguments.joined(separator: ", ")))
        }
        if command.requiresConfirmation {
            rows.append(InfoRow(label: "Confirmation", value: "Required before running"))
        }
        if let keycaps = hotKeys.binding(for: .customCommand(id: command.id))?.keycaps {
            rows.append(InfoRow(label: "Shortcut", value: keycaps.joined()))
        }
        return rows
    }

    var body: some View {
        if let command {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    Text(command.command)
                        .font(metrics.typography.rowTitle.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(metrics.spacing.xl)
                }
                .id(command.id)
                .edgeDissolve()
                .thinScrollbar()
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text("Information")
                        .font(metrics.typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    VStack(spacing: 0) {
                        let rows = information(for: command)
                        ForEach(rows) { row in
                            if row.id != rows.first?.id { Divider() }
                            HStack(spacing: metrics.spacing.sm) {
                                Text(row.label).foregroundStyle(Theme.Colors.textSecondary)
                                Spacer(minLength: metrics.spacing.lg)
                                Text(row.value).lineLimit(1).truncationMode(.middle)
                            }
                            .font(metrics.typography.keyCap)
                            .padding(.vertical, metrics.spacing.xs)
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}
