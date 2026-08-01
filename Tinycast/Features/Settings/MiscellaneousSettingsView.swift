import SwiftUI

/// The catch-all pane, and the app's network pane: software update and currency conversion both reach
/// out, which is why each ships off and needs an explicit yes before it can be switched on.
struct MiscellaneousSettingsView: View {
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates
    @ObservedObject private var updates = AppCore.shared.updates
    @State private var askingConsent = false
    @State private var askingUpdateConsent = false
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        SettingsPane(
            title: "Miscellaneous",
            subtitle: "Options that don't belong to a single feature."
        ) {
            // The dev channel has no feed, so it gets no update affordance at all rather than a dead switch.
            if updates.isSupported {
                SettingsCard(header: "Software Update") {
                    SettingsRow(
                        title: "Check for updates automatically",
                        subtitle: automaticChecksStatus,
                        systemImage: "arrow.down.circle",
                        tint: .blue,
                        statusDot: updates.isEnabled ? .green : nil
                    ) {
                        // Same springs-back shape as the currency switch: on only opens the consent sheet.
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { updates.isEnabled },
                                set: { wantsOn in
                                    if wantsOn {
                                        askingUpdateConsent = true
                                    } else {
                                        updates.setEnabled(false)
                                    }
                                })
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    SettingsDivider()
                    SettingsRow(
                        title: "Version \(updates.currentVersion)",
                        subtitle: updateStatus,
                        systemImage: "sparkles",
                        tint: .gray
                    ) {
                        Button("Check Now") { updates.checkNow() }
                            .disabled(isUpdateBusy)
                    }
                }
                // Attached here, not to the pane, so it never contends with the currency sheet.
                .sheet(isPresented: $askingUpdateConsent) {
                    UpdateConsentSheet(
                        onCancel: { askingUpdateConsent = false },
                        onAccept: {
                            askingUpdateConsent = false
                            updates.setEnabled(true)
                        })
                }
            }

            SettingsCard(header: "Calculator") {
                SettingsRow(
                    title: "Currency Conversion",
                    subtitle: conversionStatus,
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

    private var automaticChecksStatus: String {
        let cadence = "Looks for a new version once a day, in the background."
        return updates.isEnabled ? cadence : "\(cadence) Off — nothing is contacted."
    }

    /// Mirrors `ratesStatus`, including the off-state promise: with the switch off only this row's
    /// button reaches the network, and only when pressed.
    private var updateStatus: String {
        switch updates.state {
        case .checking:
            return "Checking…"
        case .downloading(let fraction):
            guard let fraction else { return "Downloading…" }
            return "Downloading… \(Int((fraction * 100).rounded()))%"
        case .extracting:
            return "Extracting…"
        case .readyToRelaunch:
            return "Update ready to install."
        case .failed(let reason):
            return reason.isEmpty ? "Couldn't reach \(UpdateStore.provider). Try again." : reason
        case .idle:
            guard updates.isEnabled else { return "Off — nothing is contacted." }
            guard let checked = updates.lastCheckDate else {
                return "\(UpdateStore.provider) · not checked yet."
            }
            let stamp = checked.formatted(date: .abbreviated, time: .shortened)
            return "Up to date · checked \(stamp)."
        }
    }

    private var isUpdateBusy: Bool {
        switch updates.state {
        case .idle, .failed: return false
        default: return true
        }
    }

    /// Carries the off-state promise that used to need its own callout: nothing is contacted until
    /// the switch is on.
    private var conversionStatus: String {
        let examples = "Convert inline — \"100 dollars to yen\", \"€20 to GBP\"."
        return currencyRates.isEnabled ? examples : "\(examples) Off — no service is contacted."
    }

    private var ratesStatus: String {
        if refreshing { return "Updating…" }
        if refreshFailed { return "Couldn't reach \(CurrencyRateStore.provider). Try again." }
        guard let fetched = currencyRates.rates?.fetchedAt else {
            return "\(CurrencyRateStore.provider) · not downloaded yet."
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return "\(CurrencyRateStore.provider) · updated \(stamp). Refreshes daily."
    }
}

/// The update consent step, same three deciding facts as `CurrencyConsentSheet` — who is contacted, how
/// often, and that nothing about the machine goes with it — plus the provider link so it's checkable.
private struct UpdateConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.blue)
                Text("Check for updates automatically?")
                    .font(.headline)
            }

            Text(
                "Once a day, Tinycast asks \(UpdateStore.provider) for a small static XML file listing "
                + "the latest version. That HTTPS request is all that leaves your Mac — no account, no "
                + "identifiers, nothing about this machine or how you use it. You can turn it off at "
                + "any time."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: UpdateStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(UpdateStore.providerURL.host() ?? "Provider")
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
                "Tinycast downloads exchange rates from \(CurrencyRateStore.provider) once a day and "
                + "keeps a copy on your Mac. No account, no identifiers, nothing you type. "
                + "Turning it off deletes the cached rates."
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
