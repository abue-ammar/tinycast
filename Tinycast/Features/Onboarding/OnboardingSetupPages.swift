import SwiftUI

enum OnboardingSetupPages {
    struct Pasting: View {
        let trusted: Bool
        let compact: Bool

        var body: some View {
            VStack(spacing: compact ? Theme.Spacing.xl : Theme.Spacing.xxl) {
                Icon(symbol: "accessibility", compact: compact)
                Header(title: "Paste in Active App") {
                    Text("Accessibility lets Tinycast paste clipboard items and insert snippets.")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.md) {
                        Text("Accessibility").fontWeight(.medium)
                        Text(verbatim: "·").accessibilityHidden(true)
                        Label {
                            Text(trusted ? "Granted" : "Not granted")
                        } icon: {
                            Image(systemName: trusted ? "checkmark.circle.fill" : "circle.dashed")
                        }
                        .foregroundStyle(trusted ? Theme.Colors.success : .secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.cardFill, in: Capsule())
                    .accessibilityElement(children: .combine)
                    if !trusted {
                        Text("Optional — you can enable this later in Settings › Permissions.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Theme.Onboarding.setupWidth)
        }
    }

    struct Import: View {
        @Bindable var model: OnboardingModel
        let compact: Bool
        let contentHeight: CGFloat
        let scroll: ScrollViewProxy
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Namespace private var itemsAnchor
        @State private var showsItems = false
        @State private var collapsedHeight: CGFloat = 0
        @State private var targeted = false

        private var expansionAnimation: Animation? {
            reduceMotion || !Motion.isEnabled ? nil : Theme.Onboarding.pageMotion
        }

        var body: some View {
            VStack(spacing: Theme.Spacing.xxl) {
                Header(title: "Import from Raycast") {
                    Text("Bring your shortcuts, favorites, and clipboard history along.")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    fileCard
                    if model.isRaycastExport && !model.didImport { itemsDisclosure }
                }
                switch model.status {
                case .success(let message):
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.Colors.success)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(
                        Theme.Colors.warning)
                case nil:
                    if model.file == nil {
                        Text("Optional — you can import later in Settings › Backup.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(
                maxWidth: model.isRaycastExport
                    ? Theme.Onboarding.importOptionsWidth : Theme.Onboarding.setupWidth
            )
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                if !showsItems { collapsedHeight = height }
            }
            // Keep the disclosure under the pointer as a centered page grows taller than its viewport.
            .padding(.top, showsItems ? max(0, (contentHeight - collapsedHeight) / 2) : 0)
            .disabled(model.importing)
            .onChange(of: model.file) { showsItems = false }
        }

        private var itemsDisclosure: some View {
            VStack(alignment: .leading, spacing: compact ? Theme.Spacing.md : Theme.Spacing.xl) {
                itemsButton
                if showsItems {
                    ImportItems(selection: $model.selection, compact: compact)
                        .onGeometryChange(for: Bool.self) {
                            $0.size.height > 0
                        } action: { laidOut in
                            if laidOut, showsItems {
                                withAnimation(expansionAnimation) {
                                    scroll.scrollTo(itemsAnchor, anchor: .top)
                                }
                            }
                        }
                }
            }
            .padding(.top, compact ? Theme.Spacing.xxxl : Theme.Spacing.xl)
            .frame(minHeight: showsItems ? contentHeight : nil, alignment: .top)
            .id(itemsAnchor)
            .padding(.top, compact ? -Theme.Spacing.sm : Theme.Spacing.xxs)
        }

        private var itemsButton: some View {
            Button {
                setItemsExpanded(!showsItems)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                        .animation(expansionAnimation) { chevron in
                            chevron.rotationEffect(.degrees(showsItems ? 90 : 0))
                        }
                        .flipsForRightToLeftLayoutDirection(true)
                    Text("Items to import").fontWeight(.medium)
                    Spacer()
                    Text(model.selection.rawValue.nonzeroBitCount, format: .number)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityRepresentation {
                DisclosureGroup(
                    "Items to import", isExpanded: Binding(get: { showsItems }, set: setItemsExpanded)
                ) {
                    EmptyView()
                }
            }
        }

        private func setItemsExpanded(_ expanded: Bool) {
            withAnimation(expanded ? nil : expansionAnimation) { showsItems = expanded }
        }

        private var fileCard: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.dialog)
            return VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: model.chooseFile) {
                        fileLabel
                            .frame(maxWidth: .infinity)
                            .padding(model.file == nil ? Theme.Spacing.xxl : Theme.Onboarding.fileCardInset)
                            .contentShape(.rect)
                    }
                    .help("Choose a .rayconfig file exported from Raycast v2.0 or newer.")
                    if model.file != nil {
                        Button {
                            model.selectFile(nil)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(Theme.Onboarding.fileCardInset)
                                .frame(maxHeight: .infinity)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Remove File")
                        .help("Remove File")
                    }
                }
                .buttonStyle(.plain)
                if model.isRaycastExport && !model.didImport {
                    Divider().padding(.horizontal, Theme.Onboarding.fileCardInset)
                    HStack(spacing: Theme.Spacing.xxl) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Passphrase").font(.headline)
                            Text("Set during export.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        RevealableSecureField(
                            title: String(localized: "Passphrase"), text: $model.passphrase,
                            prompt: Text(verbatim: "")
                        )
                        .font(.body)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: Theme.Onboarding.passphraseWidth)
                        .id(model.file)
                    }
                    .padding(Theme.Onboarding.fileCardInset)
                }
            }
            .background(
                targeted ? Theme.Onboarding.featureIconFill : Theme.Onboarding.fileCardFill, in: shape
            )
            .overlay {
                if targeted {
                    shape.strokeBorder(Theme.Colors.brand, lineWidth: Theme.Size.dropHintStroke)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self, isEnabled: !model.importing) { files, _ in
                if files.count == 1, let file = files.first { model.selectFile(file) }
            }
            .dropConfiguration { DropConfiguration(operation: $0.itemsCount == 1 ? .copy : .forbidden) }
            .onDropSessionUpdated { session in
                targeted = session.itemsCount == 1 && (session.phase == .entering || session.phase == .active)
            }
        }

        @ViewBuilder private var fileLabel: some View {
            if let file = model.file {
                HStack(spacing: Theme.Spacing.xl) {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: Theme.Onboarding.fileGlyphSize, weight: .light))
                        .foregroundStyle(Theme.Onboarding.emblemInk).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(verbatim: file.lastPathComponent)
                            .font(.headline).lineLimit(1).truncationMode(.middle)
                        if model.isRaycastExport {
                            Text("Choose Another File…").font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("This doesn't look like a Raycast export (.rayconfig).")
                                .font(.callout).foregroundStyle(Theme.Colors.warning)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: Theme.Spacing.xl) {
                    if !compact {
                        Icon(
                            symbol: "tray.and.arrow.down", compact: false, glyphScale: 0.4, weight: .regular)
                    }
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("Choose File…").font(.headline)
                        Text("Or drop a .rayconfig file here.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
            }
        }
    }

    private struct ImportItems: View {
        @Binding var selection: RaycastImportOptions
        let compact: Bool

        var body: some View {
            let gap = compact ? Theme.Spacing.xs : Theme.Spacing.sm
            let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: 2)
            VStack(alignment: .leading, spacing: compact ? Theme.Spacing.xl : Theme.Spacing.dialogInset) {
                LazyVGrid(columns: columns, spacing: gap) {
                    ForEach(RaycastImportSelection.categories) { category in
                        let selected = selection.contains(category.option)
                        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row)
                        Button {
                            selection.formSymmetricDifference(category.option)
                        } label: {
                            HStack(spacing: compact ? Theme.Spacing.xs : Theme.Spacing.md) {
                                SettingsSymbolTile(symbol: category.symbol, tint: category.tint)
                                    .opacity(selected ? 1 : 0.6)
                                    .accessibilityHidden(true)
                                Text(category.label)
                                    .font(.callout.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, compact ? Theme.Spacing.md : Theme.Spacing.lg)
                            .padding(
                                .vertical,
                                Theme.Onboarding.importItemPadding - (compact ? Theme.Spacing.xxs : 0)
                            )
                            .background(
                                selected ? Theme.Onboarding.importItemSelectedFill : Theme.Colors.cardFill,
                                in: shape
                            )
                            .contentShape(shape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Button(selection == .all ? "Deselect All" : "Select All") {
                    selection = selection == .all ? [] : .all
                }
                .buttonStyle(.link)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.Colors.brand)
            }
        }
    }

    struct Header<Subtitle: View>: View {
        let title: LocalizedStringKey
        @ViewBuilder let subtitle: Subtitle

        var body: some View {
            VStack(spacing: Theme.Spacing.xl) {
                Text(title)
                    .font(.system(size: Theme.Onboarding.stepTitleSize, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                subtitle.font(.title3)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Icon: View {
        let symbol: String
        let compact: Bool
        var glyphScale: CGFloat = 0.5
        var weight: Font.Weight = .semibold

        var body: some View {
            let diameter = Theme.Onboarding.setupIconSize * (compact ? 0.6 : 1)
            Image(systemName: symbol)
                .font(.system(size: diameter * glyphScale, weight: weight))
                .foregroundStyle(Theme.Onboarding.emblemInk)
                .frame(width: diameter, height: diameter)
                .background(Theme.Onboarding.featureIconFill, in: Circle())
                .accessibilityHidden(true)
        }
    }
}
