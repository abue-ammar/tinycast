import SwiftUI

/// The catch-all pane. Home to currency conversion — the one feature in Tinycast that reaches the
/// network, which is why it ships off and needs an explicit yes before it can be switched on.
struct MiscellaneousSettingsView: View {
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates
    @State private var askingConsent = false
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        SettingsPane(
            title: "Miscellaneous",
            subtitle: "Options that don't belong to a single feature."
        ) {
            SettingsCard(header: "Calculator") {
                SettingsRow(
                    title: "Currency Conversion",
                    subtitle: .verbatim(conversionStatus),
                    systemImage: "dollarsign.arrow.circlepath",
                    tint: .green,
                    statusDot: currencyRates.isEnabled ? .green : nil
                ) {
                    // Deliberately not bound straight to the setting: flipping it on only opens the
                    // consent sheet, so the switch springs back until the user actually accepts.
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { currencyRates.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingConsent = true
                                } else {
                                    currencyRates.setEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if currencyRates.isEnabled {
                    SettingsDivider()
                    SettingsRow(
                        title: "Exchange Rates",
                        subtitle: .verbatim(ratesStatus),
                        systemImage: "clock.arrow.circlepath",
                        tint: .gray
                    ) {
                        Button("Update Now") {
                            refreshing = true
                            Task {
                                let landed = await currencyRates.refreshNow()
                                refreshFailed = !landed
                                refreshing = false
                            }
                        }
                        .disabled(refreshing)
                    }
                }
            }
        }
        .sheet(isPresented: $askingConsent) {
            CurrencyConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    currencyRates.setEnabled(true)
                })
        }
    }

    /// Carries the off-state promise that used to need its own callout: nothing is contacted until
    /// the switch is on.
    private var conversionStatus: String {
        let examples = String(
            localized: "Convert inline — \"100 dollars to yen\", \"€20 to GBP\".")
        return currencyRates.isEnabled
            ? examples
            : String(localized: "\(examples) Off — no service is contacted.")
    }

    private var ratesStatus: String {
        if refreshing { return String(localized: "Updating…") }
        if refreshFailed {
            return String(localized: "Couldn't reach \(CurrencyRateStore.provider). Try again.")
        }
        guard let fetched = currencyRates.rates?.fetchedAt else {
            return String(localized: "\(CurrencyRateStore.provider) · not downloaded yet.")
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return String(
            localized: "\(CurrencyRateStore.provider) · updated \(stamp). Refreshes daily.")
    }
}

/// The consent step. Three facts are the ones that actually decide the answer — who is contacted, how
/// often, and that nothing personal goes with it — plus the provider link so the claim is checkable.
private struct CurrencyConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.green)
                Text("Turn on currency conversion?")
                    .font(.headline)
            }

            Text(
                String(
                    localized:
                        "Tinycast downloads exchange rates from \(CurrencyRateStore.provider) once a day and keeps a copy on your Mac. No account, no identifiers, nothing you type. Turning it off deletes the cached rates."
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: CurrencyRateStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(CurrencyRateStore.providerURL.host() ?? "Provider")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }
}
