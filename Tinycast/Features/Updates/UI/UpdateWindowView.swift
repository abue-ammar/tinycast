import AppKit
import SwiftUI

/// The whole update surface: prompt, release notes, progress and report, in one window.
struct UpdateWindowView: View {
    @Environment(UpdateCoordinator.self) private var updates

    static let width: CGFloat = 460
    /// Only until the first layout measures the real one, which is what the window then takes.
    static let initialSize = CGSize(width: width, height: 158)

    private static let iconSize: CGFloat = 52
    /// macOS bakes a transparent margin into an app icon; bleeding it out is what lets the artwork
    /// line up with the padding instead of floating a few points inside it.
    private static let iconBleed: CGFloat = 6
    /// A fixed reading area: notes run from one line to fifty, and the window may not track that.
    private static let cardHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            hero
            detail
            actions
        }
        // Less on top: the title bar already contributes its own 32pt above this, and clearing the
        // traffic lights is the only reason the hero cannot start at the inset the other edges use.
        .padding(.top, Theme.Spacing.sm)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        // Take the ideal height rather than the window's, so the measurement is the content's own
        // and sizing the window to it converges instead of feeding back.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            updates.fit(height: $0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Only the gradient reaches under the transparent titlebar; the content stays inside the
        // safe area, so the padding it measures is the padding the window ends up with.
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear], startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: Self.iconSize + Self.iconBleed * 2,
                    height: Self.iconSize + Self.iconBleed * 2
                )
                .padding(-Self.iconBleed)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch updates.stage {
        case .checking: return "Checking for updates…"
        case .upToDate: return "\(Bundle.main.appDisplayName) is up to date"
        case .localBuild: return "\(Bundle.main.appDisplayName) doesn't update itself"
        case .available(let release), .blocked(_, let release), .installing(let release, _):
            return "\(Bundle.main.appDisplayName) \(release.version) is available"
        case .readyToRelaunch: return "Update installed"
        case .failed: return "Update failed"
        }
    }

    private var subtitle: String {
        switch updates.stage {
        case .checking, .upToDate, .failed:
            return "Version \(updates.runningVersion)"
        case .localBuild:
            return "This is a local build — rebuild it to move it forward."
        case .available, .blocked, .installing:
            return "You have \(updates.runningVersion)."
        case .readyToRelaunch:
            return "Relaunch to start using it."
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch updates.stage {
        case .checking, .upToDate, .localBuild, .readyToRelaunch:
            EmptyView()
        case .available(let release):
            card { notes(release) }
        case .blocked(let blocker, _):
            Label(blocker.message, systemImage: "clock")
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .installing(_, let phase):
            progress(phase)
        case .failed(let failure):
            card { report(failure) }
        }
    }

    private func notes(_ release: AvailableRelease) -> some View {
        ReleaseNotesView(text: release.notes)
    }

    private func report(_ failure: UpdateFailure) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(failure.errorDescription ?? "Something went wrong.")
                .font(.callout)
            if let recovery = failure.recoverySuggestion {
                Text(recovery)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ phase: UpdateInstaller.Phase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let fraction = phase.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(phase.message)
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .textSelection(.enabled)
                .padding(Theme.Spacing.xl)
                .hideNativeScrollers()
        }
        .frame(height: Self.cardHeight)
        .thinScrollbar()
        .background(Theme.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: 0)
            switch updates.stage {
            case .checking:
                ProgressView().controlSize(.small)
                Button("Cancel") { updates.dismiss() }
                    .keyboardShortcut(.cancelAction)
            case .upToDate, .localBuild:
                Button("OK") { updates.dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .available:
                Button("Later") { updates.skip() }
                    .keyboardShortcut(.cancelAction)
                Button("Update Now") { updates.install() }
                    .keyboardShortcut(.defaultAction)
            case .blocked:
                Button("Later") { updates.skip() }
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { updates.retry() }
                    .keyboardShortcut(.defaultAction)
            case .installing:
                Button("Cancel") { updates.cancelInstall() }
                    .keyboardShortcut(.cancelAction)
            case .readyToRelaunch:
                Button("Later") { updates.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Relaunch") { updates.relaunch() }
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Close") { updates.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
