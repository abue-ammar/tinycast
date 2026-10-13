import SwiftUI

struct FallbacksSettingsView: View {
    @Environment(AppCore.self) private var core
    /// Observed so a reorder or a checkbox redraws the list under the button that moved it.
    @Environment(FallbackStore.self) private var store

    private var fallbacks: [Fallback] { core.fallbackCoordinator.available }

    var body: some View {
        Form {
            Section {
                let fallbacks = fallbacks
                if fallbacks.isEmpty {
                    Text("Nothing to offer — their features are off.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(Array(fallbacks.enumerated()), id: \.element) { index, fallback in
                        FallbackRow(fallback: fallback, order: fallbacks, index: index)
                    }
                }
            } header: {
                SettingsSectionHeader(.fallbacksFallbacks)
            } footer: {
                Text("Shown below every search as “Use … with”. Includes quicklinks with an {argument}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fallbacks)
        .releasesFocusOnOutsideClick()
    }
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
                    .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
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
