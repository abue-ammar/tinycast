import SwiftUI

struct PlanUsageSection: View {
    let provider: PlanUsage.Provider
    let entry: PlanUsageEntry
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            if let usage = entry.usage {
                VStack(alignment: .leading, spacing: Theme.Spacing.planUsageRow) {
                    ForEach(usage.windows) { WindowRow(window: $0, now: now) }
                }
            } else {
                (entry.failed ? Text("Couldn't read usage") : Text("Checking usage…"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Size.planUsageMenuInset)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.planUsageSectionBottom)
        .frame(width: Theme.Size.planUsageMenuWidth, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(provider.brand.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: Theme.Size.menuBrandIcon, height: Theme.Size.menuBrandIcon)
                .accessibilityHidden(true)
            Text(verbatim: provider.title)
                .font(.headline)
            if let plan = entry.usage?.plan {
                Text(verbatim: plan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            if let note {
                Text(verbatim: note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var note: String? {
        switch entry.note(at: now) {
        case .refreshFailed?:
            return String(localized: "Couldn't refresh")
        case .updated(let age)?:
            let duration = PlanUsageFormat.duration(age, locale: .current)
            return String(localized: "Updated \(duration) ago")
        case nil:
            return nil
        }
    }
}

private struct WindowRow: View {
    let window: PlanUsage.Window
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(verbatim: window.title)
                    .lineLimit(1)
                if let reset {
                    Text(verbatim: reset)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.md)
                Text("\(PlanUsageFormat.percent(window.usedPercent, locale: .current)) used")
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .layoutPriority(1)
            }
            Meter(
                fraction: window.fraction, pace: window.elapsedFraction(at: now),
                tint: window.level.tint)
            if let exhaustion = window.exhaustion(at: now) {
                let duration = PlanUsageFormat.duration(exhaustion.timeIntervalSince(now), locale: .current)
                Text("At this pace, runs out in \(duration)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reset: String? {
        guard let resetsAt = window.resetsAt else { return nil }
        guard resetsAt > now else { return String(localized: "Reset due") }
        let countdown = PlanUsageFormat.duration(resetsAt.timeIntervalSince(now), locale: .current)
        let time = PlanUsageFormat.resetTime(resetsAt, now: now, calendar: .current, locale: .current)
        return "\(countdown) · \(time)"
    }
}

/// The share used, with a mark at the share of the window already gone: fill past it is ahead.
private struct Meter: View {
    let fraction: Double
    let pace: Double?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.controlSurface)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * fraction)
                if let pace {
                    let mark = Theme.Size.planUsagePaceMark
                    Capsule()
                        .fill(.secondary)
                        .frame(width: mark.width, height: mark.height)
                        .offset(x: proxy.size.width * pace - mark.width / 2)
                }
            }
        }
        .frame(height: Theme.Size.planUsageMeter)
        .accessibilityHidden(true)
    }
}
