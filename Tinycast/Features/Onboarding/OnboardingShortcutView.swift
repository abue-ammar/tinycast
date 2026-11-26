import SwiftUI

struct OnboardingShortcutView: View {
    let session: OnboardingShortcutSession
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: Theme.Spacing.xxxl) {
            OnboardingSetupPages.Header(
                title: session.isReady ? "Try Your Shortcut" : "Set Up Your Launcher"
            ) {
                Group {
                    if session.isReady {
                        Text(
                            "Press \(ShortcutNotice.keys(session.binding)) to open Tinycast, or type a new shortcut."
                        )
                    } else {
                        Text("Type the shortcut you want to open Tinycast with.")
                    }
                }
                .foregroundStyle(.secondary)
            }
            OnboardingKeys(session: session)
            Group {
                if let notice = session.notice {
                    ShortcutNotice(notice: notice, session: session)
                        .disabled(session.isConfirmed)
                }
            }
            .frame(minHeight: Theme.Onboarding.Notice.reservedHeight)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(session.isConfirmed)
        }
        .multilineTextAlignment(.center)
        // The listener ends whenever the window resigns key, so it starts again each time it returns.
        .onChange(of: appearsActive, initial: true) { _, active in
            guard active else { return }
            session.refresh()
            session.startListening()
        }
        .onChange(of: session.assignedBinding) { session.refresh() }
        .onChange(of: hotKeys.capture.pressedCurrentBinding) { _, pressed in
            if pressed { session.confirm() }
        }
        .onDisappear { session.stopListening() }
    }
}

private struct ShortcutNotice: View {
    let notice: OnboardingShortcutSession.Notice
    let session: OnboardingShortcutSession

    static func keys(_ binding: HotKeyBinding) -> Text {
        Text(verbatim: binding.keycaps.joined(separator: " ")).fontWeight(.semibold).foregroundStyle(.primary)
    }

    var body: some View {
        let keys = Self.keys(session.binding)
        switch notice {
        case .suggestion:
            NoticeCard(
                title: Text("Open Tinycast with \(keys)?"),
                detail: Text("It’s free on this Mac, and you can change it anytime.")
            ) {
                Button(action: session.useSuggestion) { Text("Use \(keys)") }
            }
        case .heldBySpotlight:
            NoticeCard(
                title: Text("Spotlight also uses \(keys)"),
                detail: Text("Turn off Spotlight’s shortcut and use it for Tinycast.")
            ) {
                Button("Replace Spotlight", action: session.replaceSpotlight)
            }
        case .spotlightOff:
            NoticeCard(
                title: Text("\(keys) now opens Tinycast"), detail: Text("Spotlight’s shortcut is turned off.")
            ) {
                Button("Undo", action: session.undoSpotlightReplacement)
            }
        case .taken:
            NoticeCard(
                title: Text("\(keys) is already in use"),
                detail: Text("Disable or change it where it’s assigned to use it in Tinycast."),
                isWarning: true)
        case .rejected(let conflict):
            NoticeCard(
                title: Text("\(Self.keys(conflict.binding)) is used by \(conflict.owner)"),
                detail: Text("Press a different shortcut."), isWarning: true)
        }
    }
}

private struct NoticeCard<Action: View>: View {
    private typealias Notice = Theme.Onboarding.Notice

    let title: Text
    let detail: Text
    var isWarning = false
    @ViewBuilder var action: Action

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Notice.cornerRadius, style: .continuous)
        HStack(spacing: Theme.Spacing.xxl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    if isWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.warning)
                    }
                    title
                }
                .font(.body.weight(.semibold))
                detail
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
                .buttonStyle(NoticeButtonStyle())
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Notice.horizontalInset)
        .padding(.vertical, Notice.verticalInset)
        .background(Notice.fill, in: shape)
        .overlay { shape.strokeBorder(Notice.stroke, lineWidth: Notice.strokeWidth) }
        .frame(width: Notice.width)
    }
}

extension NoticeCard where Action == EmptyView {
    init(title: Text, detail: Text, isWarning: Bool) {
        self.init(title: title, detail: detail, isWarning: isWarning) { EmptyView() }
    }
}

private struct NoticeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NoticeButton(configuration: configuration)
    }

    private struct NoticeButton: View {
        private typealias Notice = Theme.Onboarding.Notice

        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Notice.buttonInset)
                .frame(height: Notice.buttonHeight)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : Notice.disabledOpacity)
                .onHover { hovered = $0 }
        }

        private var fill: Color {
            if configuration.isPressed { return Notice.buttonPressed }
            return hovered ? Notice.buttonHover : Notice.buttonFill
        }
    }
}
