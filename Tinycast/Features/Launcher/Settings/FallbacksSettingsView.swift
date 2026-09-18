import SwiftUI

/// Settings ▸ Fallbacks: which commands a typed query is offered to, and in what order.
struct FallbacksSettingsView: View {
    @Environment(AppCore.self) private var core
    /// Observed so a reorder or a checkbox redraws the list under the button that moved it.
    @Environment(FallbackStore.self) private var store

    private var fallbacks: [Fallback] { core.fallbackCoordinator.available }

    var body: some View {
        Form {
            Section {
                Text(
                    "Every search offers these below its results, under “Use … with”. "
                        + "Each one takes what you typed as its input."
                )
                .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(.fallbacksFallbacks)
            }

            Section {
                let fallbacks = fallbacks
                if fallbacks.isEmpty {
                    Text("Nothing to offer — the features these belong to are switched off.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // One row holding a lazy stack: a `Form` realizes every row it is handed.
                    LazyVStack(spacing: 0) {
                        ForEach(Array(fallbacks.enumerated()), id: \.element) { index, fallback in
                            if index > 0 { Divider() }
                            FallbackRow(fallback: fallback, order: fallbacks, index: index)
                                .padding(.vertical, Self.rowPadding)
                        }
                    }
                    .padding(.vertical, -Self.rowPadding)
                }
            } footer: {
                Text(
                    "A quicklink appears here once its link contains an {argument}, "
                        + "which the query fills in."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fallbacks)
        .releasesFocusOnOutsideClick()
    }

    /// A grouped `Form` row's own vertical padding.
    private static let rowPadding: CGFloat = 15
}

private struct FallbackRow: View {
    let fallback: Fallback
    /// The visible order, so a move stores every id rather than only the two that swapped.
    let order: [Fallback]
    let index: Int

    @Environment(AppCore.self) private var core
    @Environment(FallbackStore.self) private var store

    var body: some View {
        if let entry = core.fallbackCoordinator.entry(for: fallback) {
            SettingsRow(title: entry.name, subtitle: entry.kindLabel) {
                AppIconView(app: entry)
                    .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
            } trailing: {
                Button {
                    move(by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .accessibilityLabel("Move \(entry.name) up")
                Button {
                    move(by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == order.count - 1)
                .accessibilityLabel("Move \(entry.name) down")
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Offer \(entry.name) as a fallback")
            }
        }
    }

    private func move(by delta: Int) {
        guard order.indices.contains(index + delta) else { return }
        store.exchange(fallback, with: order[index + delta], in: order)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(fallback) },
            set: { store.setEnabled($0, for: fallback) }
        )
    }
}
