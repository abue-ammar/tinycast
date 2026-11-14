import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(AppCore.self) private var core

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "Version \(short) (\(build))")
    }

    // Cached, and read from the bundle: the app icon is generic until LaunchServices registers.
    @MainActor private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()

    private static let iconSize: CGFloat = 88
    private static let tileSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    hero
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                }
                .settingsAnchor(.aboutAbout)
                updates
                links
                support
            }
            .formStyle(.grouped)
            .settingsScrollTarget(.about)

            // Outside the form, so the copyright stays pinned to the bottom edge.
            footer
                .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Bundle.main.appDisplayName)
                    .font(.title.weight(.bold))
                Text(Self.version)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        Capsule().fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text("A native macOS launcher for everyday productivity. Lightweight and open source.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var updates: some View {
        let updates = core.updateCoordinator
        return Section {
            HStack(spacing: Theme.Spacing.xl) {
                tile("arrow.down.circle.fill", tint: Theme.Colors.progress)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.aboutAbout, "Check for Updates")
                        .font(.body.weight(.medium))
                    updateStatus(updates)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.lg)
                Button("Check Now") { updates.checkForUpdates() }
                    .disabled(updates.isChecking)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private func updateStatus(_ updates: UpdateCoordinator) -> Text {
        guard updates.updatesItself else {
            return Text("This is a local build — rebuild it to move it forward.")
        }
        if updates.isChecking {
            return Text("Checking for updates…")
        }
        if let version = updates.availableVersion {
            return Text("Version \(version.description) is available")
        }
        guard let lastCheckedAt = updates.lastCheckedAt else {
            return Text("Not checked yet")
        }
        return Text("Last checked \(.currentDate, format: Self.elapsed(since: lastCheckedAt))")
    }

    /// Minutes at the finest, so the line re-renders once a minute rather than every second.
    private static func elapsed(since date: Date) -> SystemFormatStyle.DateReference {
        .reference(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: 1)
    }

    private var links: some View {
        Section {
            ForEach(AboutLink.all) { link in
                AboutLinkRow(link: link)
            }
        } header: {
            SettingsSectionHeader(.aboutLinks)
        }
    }

    private var support: some View {
        Section {
            HStack(spacing: Theme.Spacing.xl) {
                tile("heart.fill", tint: Theme.Colors.brand)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.aboutLinks, "Support")
                        .font(.body.weight(.medium))
                    Text("Free and open source. Your support sustains its development.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.lg)
                Button("Support…") { core.supportCoordinator.showSupport() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.brand)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    /// Both tints are fixed hues, so an alpha on them holds up in both appearances.
    private func tile(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }

    private var footer: some View {
        Text("© 2026 Abue Ammar · Released under AGPL-3.0")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

private struct AboutLink: Identifiable {
    enum Glyph {
        case symbol(String)
        /// A brand mark from the asset catalog; SF Symbols ships no such logo.
        case brand(String)
    }

    let id: String
    let glyph: Glyph
    let title: String
    let detail: String
    let url: URL

    static let all: [AboutLink] = [
        AboutLink(
            id: "website", glyph: .symbol("globe"), title: String(localized: "Website"),
            detail: "tinycast.dev",
            url: URL(string: "https://tinycast.dev/")!),
        AboutLink(
            id: "github", glyph: .brand("BrandGitHub"), title: "GitHub",
            detail: "github.com/abue-ammar/tinycast",
            url: URL(string: "https://github.com/abue-ammar/tinycast")!),
        AboutLink(
            id: "discord", glyph: .brand("BrandDiscord"), title: "Discord",
            detail: String(localized: "Join the Tinycast community"),
            url: URL(string: "https://discord.gg/v2Eeb4QQy3")!),
        AboutLink(
            id: "x", glyph: .brand("BrandX"), title: "X", detail: "@abue_ammar",
            url: URL(string: "https://x.com/abue_ammar")!),
        AboutLink(
            id: "email", glyph: .symbol("envelope"), title: String(localized: "Email"),
            detail: "hello@tinycast.dev", url: URL(string: "mailto:hello@tinycast.dev")!)
    ]
}

private struct AboutLinkRow: View {
    let link: AboutLink

    @State private var hovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(link.detail)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hovered ? .secondary : .tertiary)
                }
            } label: {
                Label {
                    Text(link.title)
                } icon: {
                    glyph
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var glyph: some View {
        switch link.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
        case .brand(let name):
            // Brand marks paint edge to edge, so they sit under the symbol box to match.
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
    }
}
