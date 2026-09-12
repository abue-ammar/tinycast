import SwiftUI

extension View {
    /// A pane's `Form`: lets a search result scroll one of its sections into view and pulse it.
    /// The pane names itself because both panes are briefly alive across a swap, and by then
    /// `navigation.tab` already reads as the incoming one.
    func settingsScrollTarget(_ tab: SettingsTab) -> some View {
        modifier(SettingsScrollTarget(tab: tab))
    }

    /// A `Section` with no header of its own: still somewhere a result can scroll to, with no pulse
    /// to paint. Every section that *has* a header uses `SettingsSectionHeader` instead.
    func settingsAnchor(_ anchor: SettingsAnchor) -> some View {
        id(SettingsTarget.section(anchor))
    }
}

/// The pulse a search result leaves on arrival: a pill behind the name it matched, and nothing else.
/// A `Form` applies a `.background` to a row's whole *content* box, so lighting the row or the
/// section paints ragged blocks around every label, button and footer paragraph in it.
private struct SearchPill: ViewModifier {
    let target: SettingsTarget
    @Environment(SettingsNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(
                Capsule().fill(navigation.flashing == target ? Theme.Colors.searchFlash : .clear)
            )
            // Given back, so the pill's own padding can't shift the label off its row's edge.
            .padding(.horizontal, -Theme.Spacing.sm)
            .padding(.vertical, -Theme.Spacing.xxs)
            .id(target)
    }
}

/// A `Section`'s name, and where a result that matched the whole group lands.
struct SettingsSectionHeader<Label: View>: View {
    let anchor: SettingsAnchor
    @ViewBuilder var label: Label

    var body: some View {
        label.modifier(SearchPill(target: .section(anchor)))
    }
}

extension SettingsSectionHeader where Label == Text {
    /// The title comes from the anchor, so a section's name and its search breadcrumb are one string.
    init(_ anchor: SettingsAnchor) {
        self.init(anchor: anchor) { Text(anchor.title) }
    }
}

/// One setting's own name, in place of the `Text` a row's label would otherwise hold. This is what
/// a row-level search result scrolls to and lights up.
struct SettingsRowTitle: View {
    let anchor: SettingsAnchor
    let title: String

    init(_ anchor: SettingsAnchor, _ title: String) {
        self.anchor = anchor
        self.title = title
    }

    var body: some View {
        Text(title).modifier(SearchPill(target: .row(anchor, title)))
    }
}

private struct SettingsScrollTarget: ViewModifier {
    let tab: SettingsTab
    @Environment(SettingsNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                // Keyed on the request, so a second jump cancels the first mid-pulse.
                .task(id: navigation.scrollRequest) { await reveal(with: proxy) }
        }
    }

    private func reveal(with proxy: ScrollViewProxy) async {
        guard let request = navigation.scrollRequest, request.target.tab == tab else { return }
        // This pane may have just mounted, so let its `Form` lay the anchor out before scrolling.
        await Task.yield()
        withAnimation(.easeOut(duration: Theme.Duration.settingsReveal)) {
            proxy.scrollTo(request.target, anchor: .center)
        }
        navigation.beginFlash(request.target)
        // Cancelled means a later jump replaced this one, and it owns the light now.
        do {
            try await Task.sleep(for: .seconds(Theme.Duration.settingsFlash))
        } catch {
            return
        }
        withAnimation(.easeOut(duration: Theme.Duration.settingsFlashOut)) {
            navigation.endFlash(request.target)
        }
        // Released last: it keys this task, so clearing it earlier would cancel the reveal itself.
        navigation.clear(request)
    }
}
