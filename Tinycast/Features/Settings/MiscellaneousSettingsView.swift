import SwiftUI

/// The catch-all pane. Home to currency conversion — the one feature in Tinycast that reaches the
/// network, which is why it ships off and needs an explicit yes before it can be switched on.
struct MiscellaneousSettingsView: View {
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates
    @State private var askingConsent = false
    @State private var refreshing = false

    var body: some View {
        SettingsPane(
            title: "Miscellaneous",
            subtitle: "Options that don't belong to a single feature."
        ) {
            SettingsCard(header: "Calculator") {
                SettingsRow(
                    title: "Currency Conversion",
                    subtitle:
                        "Convert currencies inline — \"100 dollars to yen\", \"€20 to GBP\". "
                        + "Needs exchange rates from an external service.",
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
                        subtitle: ratesStatus,
                        systemImage: "clock.arrow.circlepath",
                        tint: .gray
                    ) {
                        Button("Update Now") {
                            refreshing = true
                            Task {
                                await currencyRates.refreshNow()
                                refreshing = false
                            }
                        }
                        .disabled(refreshing)
                    }
                }
            }

            if currencyRates.isEnabled {
                SettingsCallout(
                    title: "Rates come from \(CurrencyRateStore.provider).",
                    message:
                        "Tinycast requests the published rate table roughly every six hours and "
                        + "caches it locally. The request carries nothing about you or what you type.",
                    systemImage: "network",
                    tint: .green
                ) {
                    Link("Learn More", destination: CurrencyRateStore.providerURL)
                }
            } else {
                SettingsCallout(
                    title: "Currency conversion is off.",
                    message:
                        "Tinycast won't contact the exchange-rate service until you turn this on, "
                        + "and the calculator simply won't answer currency questions.",
                    systemImage: "wifi.slash",
                    tint: .secondary
                )
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

    private var ratesStatus: String {
        guard let fetched = currencyRates.rates?.fetchedAt else {
            return "Not downloaded yet — conversions will say so until the first update lands."
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return "Last updated \(stamp). Refreshes automatically every six hours."
    }
}

/// The consent step. Spells out what enabling actually does — which service is contacted, how often,
/// what leaves the machine — and links to the provider so the claim is checkable before agreeing.
private struct CurrencyConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                    Text("Turn on currency conversion?")
                        .font(.headline)
                    Text("It needs an internet connection to fetch exchange rates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ConsentPoint(
                    systemImage: "arrow.down.circle",
                    text:
                        "Tinycast will download exchange rates from \(CurrencyRateStore.provider), "
                        + "an open-source service that publishes rates from central banks.")
                ConsentPoint(
                    systemImage: "clock",
                    text:
                        "It asks for the published rate table about every six hours while Tinycast "
                        + "is running, and keeps a copy on your Mac so it still answers offline.")
                ConsentPoint(
                    systemImage: "eye.slash",
                    text:
                        "The request contains no account, no identifier, and nothing you type into "
                        + "the calculator — the whole table is fetched and the maths happens locally.")
                ConsentPoint(
                    systemImage: "arrow.uturn.backward",
                    text:
                        "Turning this off later stops all requests and deletes the cached rates.")
            }

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
        .frame(width: 460)
    }
}

/// One bullet in the consent sheet: symbol plus a line of plain-language explanation.
private struct ConsentPoint: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
