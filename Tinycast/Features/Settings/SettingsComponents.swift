import Combine
import SwiftUI

/// Reusable building blocks for the Settings window; all metrics come from `Theme` so Settings shares one vocabulary with the palette.

// MARK: - Pane scaffold

/// Standard layout for a settings pane (title + subtitle header, then scrollable content) so headers, insets and scroll behaviour stay identical across the app.
struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                SettingsHeader(title: title, subtitle: subtitle)
                content
            }
            // Ignore the transparent-titlebar safe area and use one fixed `xxl` inset every side instead (the titlebar band is taller than the rhythm we want; traffic lights sit over the sidebar, so nothing collides).
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Settings use the native thin overlay scroller (not the palette's SwiftUI `thinScrollbar`), matching the other windowed setting lists.
            .overlayScroller()
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// The title + subtitle block at the top of every pane.
struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Grouped card

/// A rounded, hairline-bordered container grouping related rows — the macOS System Settings "card" (rows split by inset dividers via `SettingsRow`/`SettingsDivider`).
struct SettingsCard<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let header {
                Text(header)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.Spacing.xs)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
        }
    }
}

/// Inset divider between rows inside a `SettingsCard`, aligned under the row's title (past the icon).
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.xl + Theme.Size.settingsRowIcon + Theme.Spacing.lg)
    }
}

// MARK: - Row

/// A single settings line (optional SF Symbol, title with optional subtitle, trailing control); fixed vertical rhythm keeps every card aligned regardless of the control.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = .secondary
    /// Optional state indicator rendered after the title (green = active, orange = attention).
    var statusDot: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: Theme.Size.settingsRowIcon)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.body)
                    if let statusDot {
                        Circle()
                            .fill(statusDot)
                            .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

// MARK: - Callout

/// A tinted inset box for a notice or warning inside a `SettingsCard` — SF Symbol + title + optional message, with an optional trailing control (e.g. a fix-it button).
struct SettingsCallout<Trailing: View>: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "info.circle"
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title).font(.body)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

extension SettingsCallout where Trailing == EmptyView {
    init(title: String, message: String? = nil, systemImage: String = "info.circle", tint: Color = .secondary) {
        self.init(title: title, message: message, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

// MARK: - Status badge

/// Capsule state pill for a settings row (permission granted, keyword listener active) — the wordier sibling of `SettingsRow`'s `statusDot`.
struct SettingsStatusBadge: View {
    let title: String
    let tint: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: - Permission card

/// A macOS permission Tinycast asks for. Bundling the probe, deep link and copy keeps a card from pairing one permission's title with another's System Settings pane.
enum AppPermission {
    case accessibility
    case inputMonitoring

    var isGranted: Bool {
        switch self {
        case .accessibility: return Permissions.isAccessibilityTrusted()
        case .inputMonitoring: return Permissions.isInputMonitoringTrusted()
        }
    }

    var name: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .inputMonitoring: return "keyboard"
        }
    }

    var tint: Color {
        switch self {
        case .accessibility: return .blue
        case .inputMonitoring: return .purple
        }
    }

    @MainActor
    func openSystemSettings() {
        switch self {
        case .accessibility: Permissions.openAccessibilitySettings()
        case .inputMonitoring: Permissions.openInputMonitoringSettings()
        }
    }
}

/// One permission's status plus a way to manage it, shown by the pane whose feature needs it. Re-probes once a second so a grant made in System Settings lands without reopening Settings.
struct PermissionCard: View {
    let permission: AppPermission
    /// What the owning feature uses the permission for.
    let explanation: String

    @State private var isGranted: Bool
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(permission: AppPermission, explanation: String) {
        self.permission = permission
        self.explanation = explanation
        // Seeded rather than resolved in `onAppear`, so the badge never paints "Not granted" for a frame.
        _isGranted = State(initialValue: permission.isGranted)
    }

    var body: some View {
        SettingsCard(header: permission.name) {
            SettingsRow(
                title: permission.name,
                subtitle: explanation,
                systemImage: permission.symbol,
                tint: permission.tint
            ) {
                SettingsStatusBadge(
                    title: isGranted ? "Granted" : "Not granted",
                    tint: isGranted ? .green : .orange,
                    systemImage: isGranted
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            }
            SettingsDivider()
            SettingsRow(
                title: isGranted ? "Manage in System Settings" : "Grant access",
                subtitle: "Opens Privacy & Security › \(permission.name).",
                systemImage: "arrow.up.forward.app",
                tint: .secondary
            ) {
                Button(isGranted ? "Open…" : "Open Settings…") {
                    permission.openSystemSettings()
                }
            }
        }
        .onReceive(refreshTimer) { _ in
            let granted = permission.isGranted
            if granted != isGranted { isGranted = granted }
        }
    }
}
