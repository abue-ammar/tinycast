import SwiftUI

struct EmojiSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    @State private var jevKey = ""
    @State private var didLoadJevKey = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureCommandsSection(owner: .emoji, anchor: .emojiCommands)

            Section {
                RevealableSecureField(
                    title: "API Key", text: $jevKey, prompt: Text("Optional")
                )
            } header: {
                SettingsSectionHeader(.emojiJev)
            } footer: {
                Text(
                    "Semantic matches, such as a misspelled or conceptual query. "
                        + "Leave this empty and emoji search stays on the local index. "
                        + "The key stays in the Keychain and is not part of a backup."
                )
            }

            Section {
                EmojiColumnCountPicker(selection: $settings.emojiGridColumns)
                // A hand per tone, quicker to scan than a dropdown of tone names.
                Picker(selection: $settings.emojiSkinTone) {
                    ForEach(EmojiSkinTone.allCases) { tone in
                        Text(tone.sample).tag(tone)
                    }
                } label: {
                    SettingsRowTitle(.emojiAppearance, "Emoji Skin Tone")
                }
                .pickerStyle(.segmented)
            } header: {
                SettingsSectionHeader(.emojiAppearance)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.emoji)
        .onAppear {
            guard !didLoadJevKey else { return }
            didLoadJevKey = true
            jevKey = core.jevEmoji.storedKey() ?? ""
        }
        .onChange(of: jevKey) { _, key in
            guard didLoadJevKey else { return }
            core.jevEmoji.saveKey(key)
        }
    }
}

/// Five previews make the picker's starting density legible before the user opens it.
private struct EmojiColumnCountPicker: View {
    @Binding var selection: EmojiGridColumns

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsRowTitle(.emojiAppearance, "Column Count")

            HStack(spacing: Theme.Spacing.xl) {
                ForEach(EmojiGridColumns.allCases) { columns in
                    option(columns)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func option(_ columns: EmojiGridColumns) -> some View {
        let isSelected = selection == columns
        return Button {
            selection = columns
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                EmojiColumnCountPreview(columns: columns.rawValue, isSelected: isSelected)
                Text(columns.rawValue, format: .number)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(columns.rawValue) columns")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EmojiColumnCountPreview: View {
    let columns: Int
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        EmojiGridDots(columns: columns)
            .fill(isSelected ? Theme.Colors.textTertiary : Theme.Colors.border)
            .background(
                shape.fill(isSelected ? Theme.Colors.controlSurface : Color.clear)
            )
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.border : Theme.Colors.cardStroke,
                    lineWidth: Theme.Size.hairline)
            )
            .clipShape(shape)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Theme.Size.emojiSettingsGridPreview)
    }
}

/// Dots share one lattice, so horizontal and vertical runs meet on the exact same point.
private struct EmojiGridDots: Shape {
    let columns: Int

    private static let pointsPerCell = 4
    /// Match the outline's raster weight; subpixel circles render visibly fainter at the same alpha.
    private static let dotDiameter = Theme.Size.hairline

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let subdivisions = columns * Self.pointsPerCell
        guard subdivisions > 0 else { return path }
        let horizontalStep = rect.width / CGFloat(subdivisions)
        let verticalStep = rect.height / CGFloat(subdivisions)
        let radius = Self.dotDiameter / 2

        for row in 0...subdivisions {
            for column in 0...subdivisions {
                let onVertical =
                    column.isMultiple(of: Self.pointsPerCell)
                    && column > 0 && column < subdivisions
                let onHorizontal =
                    row.isMultiple(of: Self.pointsPerCell)
                    && row > 0 && row < subdivisions
                guard onVertical || onHorizontal else { continue }
                let center = CGPoint(
                    x: rect.minX + CGFloat(column) * horizontalStep,
                    y: rect.minY + CGFloat(row) * verticalStep)
                path.addEllipse(
                    in: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: Self.dotDiameter, height: Self.dotDiameter))
            }
        }
        return path
    }
}
