import AppKit
import Combine
import SwiftUI

/// The first-launch wizard, built from the app's own controls; re-runnable from Settings.
struct OnboardingView: View {
    @Environment(\.locale) private var localizationLocale
    @State private var step = 0
    @State private var model = OnboardingModel()
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys

    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let lastStep = 3
    /// Fixed content size, so `NSHostingView` can't size the window to its ideal height.
    static let windowSize = CGSize(width: 520, height: 400)

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            hero
            stepContent
                .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(.top, Theme.Spacing.xxl)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear],
                startPoint: .top, endPoint: .center)
        )
        // Extend under the titlebar, so window height equals the fixed content height.
        .ignoresSafeArea()
        // Onboarding's shortcut step has a recorder too, and it isn't inside a `SettingsPane`.
        .shortcutRecorderPopoverHost()
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }

    // MARK: - Hero (icon/glyph + title + subtitle)

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            heroMark
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var heroMark: some View {
        if step == 0 {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 60, height: 60)
        } else {
            Image(systemName: heroSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(heroTint)
                .frame(width: 60, height: 60)
                .background(Circle().fill(heroTint.opacity(0.14)))
        }
    }

    private var title: String {
        switch step {
        case 0: String(localized: "Welcome to Tinycast", bundle: .appLanguage)
        case 1: String(localized: "Enable Pasting", bundle: .appLanguage)
        case 2: String(localized: "Import from Raycast", bundle: .appLanguage)
        default: String(localized: "You're all set", bundle: .appLanguage)
        }
    }

    private var subtitle: String {
        switch step {
        case 0: String(localized: "Set a shortcut to summon the launcher from anywhere.", bundle: .appLanguage)
        case 1: String(localized: "Let Tinycast paste items back into the app you were using.", bundle: .appLanguage)
        case 2: String(localized: "Bring your shortcuts, favorites, and clipboard history along.", bundle: .appLanguage)
        default: readyMessage
        }
    }

    private var heroSymbol: String {
        switch step {
        case 1: "accessibility"
        case 2: "wand.and.stars"
        default: "checkmark"
        }
    }

    private var heroTint: Color {
        switch step {
        case 1: .blue
        case 2: .orange
        default: .green
        }
    }

    private var readyMessage: String {
        if let caps = hotKeys.binding(for: .togglePalette)?.keycaps {
            return String(localized: "Press \(caps.joined()) anytime to start using Tinycast.", bundle: .appLanguage)
        }
        return String(localized: "Tinycast is ready. Set a shortcut in Settings to summon it.", bundle: .appLanguage)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: shortcutStep
        case 1: accessibilityStep
        case 2: raycastStep
        default: doneStep
        }
    }

    private var shortcutStep: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: String(localized: "App Launcher", bundle: .appLanguage),
                    subtitle: String(localized: "Press this shortcut to open Tinycast.", bundle: .appLanguage),
                    systemImage: "magnifyingglass", tint: .blue
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
                OnboardingDivider()
                OnboardingRow(
                    title: String(localized: "Launch at login", bundle: .appLanguage),
                    subtitle: String(localized: "Start Tinycast automatically when you log in.", bundle: .appLanguage),
                    systemImage: "power", tint: .green
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            caption(String(localized: "You can change these anytime in Settings.", bundle: .appLanguage))
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: String(localized: "Accessibility", bundle: .appLanguage),
                    subtitle:
                        String(
                            localized: "Allows pasting clipboard items and expanded snippets into active apps.",
                            bundle: .appLanguage),
                    systemImage: "accessibility", tint: .blue
                ) {
                    statusBadge
                }
            }
            caption(String(localized: "Optional — you can enable this later in Settings › Permissions.", bundle: .appLanguage))
        }
    }

    private var raycastStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: String(localized: "Raycast Export", bundle: .appLanguage),
                    subtitle: model.fileSubtitle,
                    systemImage: "doc.badge.gearshape", tint: .orange
                ) {
                    Button("Choose…") { model.chooseFile() }.controlSize(.small)
                }
                OnboardingDivider()
                OnboardingRow(
                    title: String(localized: "Passphrase", bundle: .appLanguage),
                    subtitle: String(localized: "The password you set when exporting from Raycast.", bundle: .appLanguage),
                    systemImage: "key", tint: .gray
                ) {
                    SecureField("Passphrase", text: $model.passphrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit { model.run(core: core) }
                }
            }
            RaycastImportSelection(selection: $model.selection)
                .padding(.horizontal, Theme.Spacing.xs)
            if let status = model.status {
                importStatus(status)
            } else {
                caption(String(localized: "Optional — you can import later in Settings › Backup.", bundle: .appLanguage))
            }
        }
    }

    private var doneStep: some View {
        caption(String(localized: "Everything's ready. Hit Get Started to open the launcher.", bundle: .appLanguage))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Footer (step dots + navigation)

    private var footer: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(0...Self.lastStep, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            HStack {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if showsSkip {
                    Button("Skip") { advance() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                if step == 2 && model.importing {
                    Button {
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("Importing…")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                } else {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(primaryDisabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var showsSkip: Bool {
        (step == 1 && !accessibilityTrusted) || (step == 2 && !model.didImport)
    }

    private var primaryTitle: String {
        switch step {
        case 0: String(localized: "Continue", bundle: .appLanguage)
        case 1: accessibilityTrusted ? String(
            localized: "Continue",
            bundle: .appLanguage) : String(
            localized: "Grant Access",
            bundle: .appLanguage)
        case 2:
            if model.didImport {
                String(localized: "Continue", bundle: .appLanguage)
            } else if model.importing {
                String(localized: "Importing…", bundle: .appLanguage)
            } else {
                String(localized: "Import", bundle: .appLanguage)
            }
        default: String(localized: "Get Started", bundle: .appLanguage)
        }
    }

    private var primaryDisabled: Bool {
        step == 2 && !model.didImport && !model.canImport
    }

    private func primaryAction() {
        switch step {
        case 1 where !accessibilityTrusted:
            Permissions.openAccessibilitySettings()
        case 2 where !model.didImport:
            model.run(core: core)
        case Self.lastStep:
            core.onboardingCoordinator.finishOnboarding()
        default:
            advance()
        }
    }

    private func advance() {
        step = min(step + 1, Self.lastStep)
    }

    // MARK: - Shared bits

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    @ViewBuilder
    private func importStatus(_ status: OnboardingModel.ImportStatus) -> some View {
        switch status {
        case .success(let message):
            statusLine(message, systemImage: "checkmark.circle.fill", tint: .green)
        case .failure(let message):
            statusLine(message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func statusLine(_ message: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private var statusBadge: some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(
                systemName: accessibilityTrusted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(accessibilityTrusted ? String(
                localized: "Granted",
                bundle: .appLanguage) : String(
                localized: "Not granted",
                bundle: .appLanguage))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill((accessibilityTrusted ? Color.green : Color.orange).opacity(0.14)))
    }

    // Read the bundle directly: the app icon is generic until LaunchServices registers.
    private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()
}

/// The import step's state and async call, off the view so the body stays declarative.
@MainActor
@Observable
final class OnboardingModel {
    enum ImportStatus {
        case success(String)
        case failure(String)
    }

    var file: URL?
    var passphrase = ""
    var importing = false
    var status: ImportStatus?
    var selection: RaycastImportOptions = .all
    var isRaycastExport = false

    var canImport: Bool {
        isRaycastExport && !passphrase.isEmpty && !selection.isEmpty && !importing
    }
    var didImport: Bool {
        if case .success = status { return true }
        return false
    }

    var fileSubtitle: String {
        guard let name = file?.lastPathComponent else {
            return String(localized: "Choose a .rayconfig file exported from Raycast.", bundle: .appLanguage)
        }
        return "\(name) — \(isRaycastExport ? "Raycast export" : "not a Raycast export")"
    }

    func chooseFile() {
        guard let url = BackupActions.pickRaycastFile() else { return }
        file = url
        isRaycastExport = BackupActions.isRaycastExport(url)
        status = nil
    }

    func run(core: AppCore) {
        guard canImport, let file else { return }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(
                    core: core, file: file, passphrase: passphrase, options: selection)
                status = .success(BackupActions.raycastText(outcome))
                passphrase = ""
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
