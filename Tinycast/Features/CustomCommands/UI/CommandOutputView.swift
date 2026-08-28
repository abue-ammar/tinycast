import AppKit
import SwiftUI

/// The output window: what ran, what it is printing, and how it ended. One flat surface with no
/// rules — the log is the page, and the chrome is separated by space and weight rather than lines.
struct CommandOutputView: View {
    let presenter: CommandOutputPresenter

    static let initialSize = CGSize(width: 720, height: 460)

    var body: some View {
        Group {
            if let run = presenter.run {
                VStack(alignment: .leading, spacing: 0) {
                    header(run)
                    TerminalLogView(run: run)
                    footer(run)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.terminalSurface)
    }

    // MARK: - Header

    private func header(_ run: CommandRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(run.name)
                    .font(.headline)
                Text(run.commandText)
                    .font(Theme.Typography.code)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Spacing.md)
            actions(run)
        }
        // Less on top: the transparent title bar already contributes its own height above this.
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.lg)
    }

    /// Copy always; the second slot is Stop while it runs and Run Again once it has — one control
    /// for one job, so the header never has to fit both.
    private func actions(_ run: CommandRun) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            CopyLogButton(log: run.log)
            if run.isRunning {
                iconButton("stop.fill", help: "Stop") { presenter.stopRunning() }
            } else {
                iconButton("arrow.clockwise", help: "Run Again") { presenter.runAgain() }
            }
        }
    }

    private func iconButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        BarButton(chrome: .rounded, action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .tooltip(help)
    }

    // MARK: - Footer

    private func footer(_ run: CommandRun) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(statusTint(run))
                .frame(width: Self.statusDot, height: Self.statusDot)
            if let outcome = run.outcome {
                Text(outcome.summary)
                Text("·")
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(CommandDuration.text(from: run.startedAt, to: outcome.finishedAt))
            } else {
                Text("Running")
                Text("·")
                    .foregroundStyle(Theme.Colors.textTertiary)
                elapsed(from: run.startedAt)
            }
            Spacer(minLength: Theme.Spacing.md)
            if let outcome = run.outcome {
                Text(outcome.finishedAt, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.Colors.textSecondary)
        .overlay(alignment: .topLeading) { hint(run) }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    /// Ticks itself rather than being driven by a timer the window would have to own.
    private func elapsed(from start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(CommandDuration.text(from: start, to: context.date))
                .monospacedDigit()
        }
    }

    /// Sits above the footer rather than in it: the nudge is a sentence, and the bar is a line.
    @ViewBuilder
    private func hint(_ run: CommandRun) -> some View {
        if let hint = run.outcome?.hint {
            HStack(spacing: Theme.Spacing.sm) {
                Text(hint)
                Button("Open Settings") { presenter.showCommandSettings() }
                    .buttonStyle(.link)
            }
            .font(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize()
            .alignmentGuide(.top) { $0[.bottom] + Theme.Spacing.md }
        }
    }

    private static let statusDot: CGFloat = 7

    private func statusTint(_ run: CommandRun) -> Color {
        guard let outcome = run.outcome else { return Theme.Colors.progress }
        return outcome.succeeded ? Theme.Colors.success : Theme.Colors.destructive
    }
}

/// Copies the whole log, then shows a checkmark long enough to be believed.
private struct CopyLogButton: View {
    let log: String
    @State private var copiedAt: Date?

    var body: some View {
        BarButton(chrome: .rounded) {
            Paster.copyPlainText(log)
            copiedAt = Date()
        } label: {
            Image(systemName: copiedAt == nil ? "square.on.square" : "checkmark")
                .font(Theme.Typography.bar)
                .foregroundStyle(copiedAt == nil ? Theme.Colors.textSecondary : Theme.Colors.success)
        }
        .tooltip("Copy Output")
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            copiedAt = nil
        }
    }
}

/// Elapsed time, in the one place a duration becomes text.
enum CommandDuration {
    static func text(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        if seconds < 10 { return String(format: "%.1fs", seconds) }
        if seconds < 60 { return "\(Int(seconds))s" }
        let whole = Int(seconds)
        return "\(whole / 60)m \(whole % 60)s"
    }
}
