import SwiftUI

struct CustomCommandPreview: View {
    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    let command: CustomCommand?

    private struct InfoRow: Identifiable {
        let label: String
        let value: Text
        var id: String { label }

        init(label: String, value: String) {
            self.label = label
            self.value = Text(value)
        }

        init(label: String, keycaps: [String]) {
            self.label = label
            value = KeyCapChip.inlineText(keycaps)
        }
    }

    private func information(for command: CustomCommand) -> [InfoRow] {
        var rows = [
            InfoRow(
                label: String(localized: "Run In"),
                value: command.workingDirectory ?? String(localized: "Home folder")),
            InfoRow(
                label: String(localized: "Output"),
                value: command.showsOutput ? String(localized: "Show output") : String(localized: "Silent"))
        ]
        if !command.arguments.isEmpty {
            let arguments = command.arguments.enumerated().map { index, argument in
                let name = "\(CustomCommandArgument.fieldID(at: index)) · \(argument.name)"
                return argument.isOptional ? String(localized: "\(name) (optional)") : name
            }
            rows.append(
                InfoRow(label: String(localized: "Arguments"), value: arguments.joined(separator: ", ")))
        }
        if command.requiresConfirmation {
            rows.append(
                InfoRow(
                    label: String(localized: "Confirmation"),
                    value: String(localized: "Required before running")))
        }
        if let keycaps = hotKeys.binding(for: .customCommand(id: command.id))?.keycaps {
            rows.append(InfoRow(label: String(localized: "Shortcut"), keycaps: keycaps))
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
                                row.value.lineLimit(1).truncationMode(.middle)
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
