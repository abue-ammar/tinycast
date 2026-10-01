import Foundation

extension TranslationCoordinator {
    var sourceMenu: PopoverMenuContent {
        let automatic = PopoverMenuItem(
            title: "Detect Language", icon: .symbol("wand.and.stars"),
            detail: TranslationLanguages.matches(settings.sourceLanguage, "auto") ? "✓" : nil
        ) { [weak self] in self?.setSourceLanguage("auto") }
        return PopoverMenuContent(
            header: "Source Language",
            items: [automatic] + sourceLanguages.map { language in
                PopoverMenuItem(
                    title: language.name, icon: .blank,
                    detail: TranslationLanguages.matches(settings.sourceLanguage, language.id)
                        ? "✓" : nil
                ) { [weak self] in self?.setSourceLanguage(language.id) }
            })
    }

    var targetMenu: PopoverMenuContent {
        PopoverMenuContent(
            header: "Target Language",
            items: targetLanguages.map { language in
                PopoverMenuItem(
                    title: language.name, icon: .blank,
                    detail: TranslationLanguages.matches(settings.targetLanguage, language.id)
                        ? "✓" : nil
                ) { [weak self] in self?.setTargetLanguage(language.id) }
            })
    }

    var serviceMenu: PopoverMenuContent {
        var items = TranslationProvider.allCases.map { provider in
            PopoverMenuItem(
                title: provider.title, icon: .symbol(provider == .ai ? "sparkles" : "translate"),
                detail: settings.provider == provider ? "✓" : nil
            ) { [weak self] in self?.selectProvider(provider) }
        }
        items += modelGroups.flatMap { group in
            group.options.enumerated().map { index, option in
                let selected = settings.provider == .ai
                    && settings.model.map { option.matches($0) } == true
                return PopoverMenuItem(
                    title: option.title, icon: option.menuIcon,
                    sectionTitle: index == 0 ? group.title : nil,
                    detail: selected ? "✓" : nil
                ) { [weak self] in self?.chooseServiceModel(option.selection) }
            }
        }
        items.append(
            PopoverMenuItem(
                title: "Translation Settings", systemImage: "gearshape", startsSection: true
            ) { [weak self] in self?.openSettings() })
        return PopoverMenuContent(header: "Translation Service", items: items)
    }

    var actionsMenu: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(
                title: "Copy Translation", systemImage: "doc.on.doc", isEnabled: canCopy,
                shortcut: "⌘↩"
            ) { [weak self] in self?.copyTranslation() },
            PopoverMenuItem(
                title: "Swap Languages", systemImage: "arrow.left.arrow.right", isEnabled: canSwap
            ) { [weak self] in self?.swap() },
            PopoverMenuItem(
                title: "Retry Translation", systemImage: "arrow.clockwise", isEnabled: canRetry
            ) { [weak self] in self?.retry() },
            PopoverMenuItem(
                title: "Clear Text", systemImage: "xmark.circle", isEnabled: !text.isEmpty
            ) { [weak self] in self?.clear() },
            PopoverMenuItem(
                title: "Translation Settings", systemImage: "gearshape", startsSection: true
            ) { [weak self] in self?.openSettings() }
        ])
    }
}
