import SwiftUI

struct MonitorControlToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                    .foregroundStyle(.primary)
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Theme.Colors.primaryAction : Theme.Colors.controlSurface)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .padding(Theme.Spacing.xxs)
                            .frame(width: Theme.Size.monitorControlSwitchHeight)
                    }
                    .frame(width: Theme.Size.monitorControlSwitchWidth, height: Theme.Size.monitorControlSwitchHeight)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}
