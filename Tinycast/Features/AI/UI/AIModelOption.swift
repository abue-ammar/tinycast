import Foundation

struct AIModelOption: Identifiable {
    let selection: AIModelSelection
    let title: String
    let sourceTitle: String
    let menuIcon: PopoverMenuIcon

    static let appleIntelligenceIcon = PopoverMenuIcon.symbol("apple.intelligence")

    @MainActor
    static func availableGroups(
        settings: AISettingsStore, subscription: ChatGPTSubscriptionManager,
        installedAI: InstalledAIManager
    ) -> [AIModelOptionGroup] {
        let enabled = settings.enabledInstalledProviders
        let claude = installedAI.status(for: .claude)
        let grok = installedAI.status(for: .grok)
        let openCode = installedAI.status(for: .openCode)
        let cursor = installedAI.status(for: .cursor)
        return groupedCatalog(
            appleIntelligence: settings.isAppleIntelligenceAvailable(),
            codex: enabled.contains(.codex) && subscription.isConnected
                ? subscription.models : [],
            claude: enabled.contains(.claude) && claude.isReady ? claude.models : [],
            grok: enabled.contains(.grok) && grok.isReady ? grok.models : [],
            openCode: enabled.contains(.openCode) && openCode.isReady ? openCode.models : [],
            cursor: enabled.contains(.cursor) && cursor.isReady ? cursor.models : [],
            connections: settings.connections)
    }

    /// An unrecognised model keeps the generic sparkle rather than borrowing someone's mark.
    static func icon(_ brand: AIBrand?) -> PopoverMenuIcon {
        brand.map { .asset($0.assetName) } ?? .symbol("sparkles")
    }

    static let cursorIcon = PopoverMenuIcon.symbol("cursorarrow.rays")

    /// Every route the Mac can reach, on-device first: it is the one an unconfigured Mac has.
    private static func catalog(
        appleIntelligence: Bool,
        codex: [ChatGPTSubscription.Model],
        claude: [InstalledAIModel],
        grok: [InstalledAIModel],
        openCode: [InstalledAIModel],
        cursor: [InstalledAIModel],
        connections: [AIConnection]
    ) -> [AIModelOption] {
        let onDevice =
            appleIntelligence
            ? [
                AIModelOption(
                    selection: .appleIntelligence, title: AppleIntelligence.title,
                    sourceTitle: "On device", menuIcon: appleIntelligenceIcon)
            ] : []
        let codex = codex.map { model in
            AIModelOption(
                selection: .codex(model: model.id, effort: nil),
                title: model.name,
                sourceTitle: "Codex",
                menuIcon: .asset(AIBrand.openAI.assetName))
        }
        let claude = claude.map { model in
            AIModelOption(
                selection: .claude(model: model.id, effort: nil), title: model.name,
                sourceTitle: "Claude", menuIcon: .asset(AIBrand.claude.assetName))
        }
        let grok = grok.map { model in
            AIModelOption(
                selection: .grok(model: model.id, effort: nil), title: model.name,
                sourceTitle: "Grok", menuIcon: .asset(AIBrand.x.assetName))
        }
        let openCode = openCode.map { model in
            AIModelOption(
                selection: .openCode(model: model.id, effort: nil), title: model.name,
                sourceTitle: "OpenCode", menuIcon: icon(AIBrand.resolve(model: model.id)))
        }
        let cursor = cursor.map { model in
            AIModelOption(
                selection: .cursor(model: model.id, effort: nil), title: model.name,
                sourceTitle: "Cursor", menuIcon: cursorIcon)
        }
        let api = connections.flatMap { connection in
            connection.models.map { model in
                AIModelOption(
                    selection: .api(connection: connection.id, model: model, effort: nil),
                    title: model,
                    sourceTitle: connection.title,
                    menuIcon: icon(AIBrand.resolve(provider: connection.provider, model: model)))
            }
        }
        return onDevice + codex + claude + grok + openCode + cursor + api
    }

    private static func groupedCatalog(
        appleIntelligence: Bool,
        codex: [ChatGPTSubscription.Model],
        claude: [InstalledAIModel],
        grok: [InstalledAIModel],
        openCode: [InstalledAIModel],
        cursor: [InstalledAIModel],
        connections: [AIConnection]
    ) -> [AIModelOptionGroup] {
        var groups: [AIModelOptionGroup] = []
        for option in catalog(
            appleIntelligence: appleIntelligence, codex: codex, claude: claude, grok: grok,
            openCode: openCode, cursor: cursor, connections: connections)
        {
            if groups.last?.id == option.selection.source {
                groups[groups.count - 1].options.append(option)
            } else {
                groups.append(
                    AIModelOptionGroup(
                        source: option.selection.source, title: option.sourceTitle,
                        options: [option]))
            }
        }
        return groups
    }

    /// The model list only names a route; the effort it comes with is the one that route defaults to.
    @MainActor
    static func withDefaultEffort(
        _ selection: AIModelSelection, settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager
    ) -> AIModelSelection {
        let model = selection.model
        let effort: String?
        switch selection.source {
        case .appleIntelligence:
            return selection
        case .codex:
            effort = subscription.models.first { $0.id == model }?.resolvedEffort(nil)
        case .claude, .grok, .openCode, .cursor:
            effort = installedAI.models(for: selection.source)
                .first { $0.id == model }?.resolvedEffort(nil)
        case .api(let connection):
            effort = settings.connection(id: connection)?
                .reasoningOptions(for: model)?.resolvedEffort(nil)
        }
        return selection.withEffort(effort)
    }

    @MainActor
    static func efforts(
        for selection: AIModelSelection?, settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager
    ) -> [ChatGPTSubscription.Effort] {
        guard let selection else { return [] }
        let model = selection.model
        switch selection.source {
        case .appleIntelligence:
            return []
        case .codex:
            return subscription.models.first { $0.id == model }?.efforts ?? []
        case .claude, .grok, .openCode, .cursor:
            return installedAI.models(for: selection.source).first { $0.id == model }?.efforts ?? []
        case .api(let connection):
            return settings.connection(id: connection)?.reasoningOptions(for: model)?
                .efforts.map { ChatGPTSubscription.Effort(id: $0, detail: nil) } ?? []
        }
    }

    var id: AIModelSelection { selection }
    func matches(_ other: AIModelSelection) -> Bool {
        selection.source == other.source && selection.model == other.model
    }
}

struct AIModelOptionGroup: Identifiable {
    let source: AIModelSource
    let title: String
    var options: [AIModelOption]
    var id: AIModelSource { source }
}
