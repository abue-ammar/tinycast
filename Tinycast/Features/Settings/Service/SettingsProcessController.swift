import AppKit

/// The main app's side of Settings: it starts Settings' own process and serves it while it runs.
@MainActor
final class SettingsProcessController {
    private struct HyperKeyInspection {
        var takeover: HyperKeyDiagnostics.Takeover?
        var diagnostics: HyperKeyDiagnostics?
    }

    private unowned let core: AppCore
    private var link: ProcessLink<SettingsWire.ToSettings, SettingsWire.ToMainApp>?
    private var mirror: SharedStateMirror?
    private var lastStatus: MainAppStatus?
    /// Read only when the pane asks, as the in-process pane did: the scans are not free.
    private var hyperKeyInspection = HyperKeyInspection()
    private var calls: [UUID: Task<Void, Never>] = [:]
    private var unsavedMCPServers: Set<UUID> = []
    /// Bumped as each process ends, so its status observer cannot outlive it.
    private var generation = 0
    private var pendingShow: (id: UUID, request: SettingsRequest)?
    private var hasShown = false
    private var isClosing = false
    private var stagedBackup: (preview: BackupPreview, staging: BackupStaging)?

    init(core: AppCore) {
        self.core = core
    }

    func show(_ request: SettingsRequest) {
        guard let link else { return launch(request) }
        let id = UUID()
        pendingShow = (id, request)
        guard !isClosing else { return }
        mirror?.flush()
        link.send(.show(id, request))
    }

    func focus() -> Bool {
        guard link != nil else { return false }
        if pendingShow == nil { show(SettingsRequest()) }
        return true
    }

    private func launch(_ request: SettingsRequest) {
        let link: ProcessLink<SettingsWire.ToSettings, SettingsWire.ToMainApp>
        do {
            link = try .spawn(.settings)
        } catch is LaunchedExecutable.Replaced {
            offerRelaunch()
            return
        } catch {
            core.showMessage(String(localized: "Couldn't open Settings"), tone: .danger)
            return
        }
        let mirror = core.makeSharedStateMirror { [weak link] in link?.send(.changed($0)) }
        link.onReceive = { [weak self] in self?.receive($0) }
        link.onClose = { [weak self] error in self?.didClose(error: error) }
        self.link = link
        self.mirror = mirror
        link.start()
        mirror.start()
        show(request)
        observeStatus()
    }

    private func offerRelaunch() {
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Relaunch Tinycast?"),
                    message: String(
                        localized: """
                            Tinycast was updated while it was running. \
                            Open Settings again after it relaunches.
                            """),
                    symbol: "arrow.down.circle", confirmTitle: String(localized: "Relaunch"), tone: .neutral,
                    confirmRole: .standard, dismissTitle: String(localized: "Later"))
            else { return }
            core.relaunch()
        }
    }

    private func receive(_ message: SettingsWire.ToMainApp) {
        switch message {
        case .changed(let change): mirror?.apply(change)
        case .recordingShortcut(let recording): core.hotKeys.isRecordingInSettings = recording
        case .perform(let action): perform(action)
        case .call(let id, let call): start(call, id: id)
        case .cancelCall(let id):
            calls.removeValue(forKey: id)?.cancel()
            if stagedBackup?.preview.id == id { discardStagedBackup() }
        case .openURL(let url): core.handleOpenURL(url)
        case .activate(let id):
            hasShown = true
            if pendingShow?.id == id { pendingShow = nil }
            activateSettings()
        case .closing:
            mirror?.flush()
            isClosing = true
            link?.send(.readyToClose)
        }
    }

    /// This app received the click or key that asked for Settings, so only it may pass focus on.
    private func activateSettings() {
        guard let pid = link?.childProcessIdentifier,
            let settings = NSRunningApplication(processIdentifier: pid)
        else { return }
        settings.activate(from: .current)
    }

    private func didClose(error: Error?) {
        let reopen = hasShown || isClosing ? pendingShow?.request : nil
        let showFailure = !isClosing && (error != nil || !hasShown)
        pendingShow = nil
        hasShown = false
        isClosing = false
        link = nil
        mirror = nil
        lastStatus = nil
        hyperKeyInspection = HyperKeyInspection()
        calls.values.forEach { $0.cancel() }
        calls = [:]
        discardStagedBackup()
        for id in unsavedMCPServers { core.mcpCoordinator.discardUnsaved(id) }
        unsavedMCPServers.removeAll()
        generation += 1
        // A Settings process that died mid-recording would otherwise leave every shortcut off.
        core.hotKeys.isRecordingInSettings = false
        if let reopen {
            launch(reopen)
        } else if showFailure {
            core.showMessage(
                SettingsWire.Failure.disconnected.localizedDescription, tone: .danger)
        }
    }

    // MARK: - Actions

    private func perform(_ action: SettingsAction) {
        switch action {
        case .resetLauncherRanking:
            core.launcherRanking.resetAll()
            send(makeStatus())
        case .inspectHyperKey(let diagnostics):
            inspectHyperKey(diagnostics: diagnostics)
        case .restartHyperKey:
            core.hyperKey.restart()
            inspectHyperKey(diagnostics: true)
        case .setICloudSyncEnabled(let enabled):
            core.cloudSyncCoordinator.setEnabled(enabled)
        case .setICloudSyncIncluded(let category, let included):
            core.cloudSyncCoordinator.setIncluded(included, for: category)
        case .refreshICloudSync:
            core.cloudSyncCoordinator.refresh()
        case .renameThisMac(let name):
            core.cloudSyncCoordinator.renameThisMac(name)
        case .removeSyncDevice(let id):
            core.cloudSyncCoordinator.removeDevice(id)
        case .deleteICloudData:
            Task { await core.cloudSyncCoordinator.deleteCloudData() }
        case .editCustomCommand(let id):
            core.customCommandCoordinator.editCustomCommand(id.flatMap(core.customCommands.command(id:)))
        case .deleteCustomCommand(let id):
            core.customCommandCoordinator.removeCustomCommand(id: id)
        case .editQuicklink(let id):
            core.quicklinkCoordinator.editQuicklink(id.flatMap(core.quicklinks.quicklink(id:)))
        case .deleteQuicklink(let id):
            Task { await core.quicklinkCoordinator.removeQuicklink(id: id) }
        case .editSnippet(let id):
            core.snippetCoordinator.editSnippet(id.flatMap(core.snippetsStore.record(id:)))
        case .createRoom:
            core.roomCoordinator.createRoom()
        case .editRoomWindows(let id):
            guard let room = core.rooms.room(id: id) else { return }
            core.roomCoordinator.editWindows(of: room)
        case .deleteRoom(let id):
            core.roomCoordinator.removeRoom(id: id)
        case .enterRoom(let id):
            core.roomCoordinator.enterRoom(id: id)
        case .runWindowLayout(let id):
            core.windowLayoutCoordinator.runWindowLayout(id: id)
        case .deleteWindowLayout(let id):
            core.windowLayoutCoordinator.deleteWindowLayout(id: id)
        case .deleteCustomWindowSize(let id):
            core.customWindowSizeCoordinator.removeCustomWindowSize(id: id)
        case .deleteCustomQuickAction(let id):
            core.quickActionCoordinator.removeCustomQuickAction(id: id)
        case .setShortcut(let action, let binding):
            core.hotKeys.setBinding(binding, for: action)
        case .clearClipboardHistory:
            core.clipboardCoordinator.clearHistory()
        case .rebuildFileIndex:
            core.fileSearchCoordinator.rebuildIndex()
        case .refreshFileAccess:
            core.fileIndexer.refreshAccess()
        case .reloadCalendar:
            core.calendarCoordinator.applyEnabled()
        case .downloadDictationModel(let model):
            Task { await core.dictationCoordinator.downloadModel(model) }
        case .removeDictationModel(let model):
            Task { await core.dictationCoordinator.removeModel(model) }
        case .cancelDictationDownload:
            core.dictationModels.cancelDownload()
        case .refreshDictationModels:
            core.dictationModels.refreshInstalledModels()
        case .refreshInstalledAI(let kind):
            if kind == .codex {
                core.chatGPTSubscription.refresh()
            } else {
                core.installedAI.refresh(kind: kind)
            }
        case .installedAILaunchChanged(let kind):
            core.aiSettings.noteLaunchChanged(for: kind)
        case .discardUnsavedMCPServer(let id):
            core.mcpCoordinator.discardUnsaved(id)
            unsavedMCPServers.remove(id)
        case .setSettingsFile(.stop):
            core.stopSettingsFile()
        case .setSettingsFile(.start(let importing)):
            core.startSettingsFile(importing: importing)
        case .setExtensionAppearance(let name, let appearance):
            core.extensions.setAppearance(appearance, for: name)
            send(makeStatus())
        case .setExtensionBackground(let reference, let enabled):
            core.extensions.setBackgroundEnabled(
                enabled, extension: reference.extensionName, command: reference.commandName)
            send(makeStatus())
        case .setExtensionMenuBar(let reference, let enabled):
            core.extensionCoordinator.setMenuBarEnabled(enabled, reference: reference)
            send(makeStatus())
        case .setExtensionPreference(let name, let key, let value):
            core.extensions.storage.setPreference(extension: name, key: key, value: value)
        case .discardBackup(let id):
            if stagedBackup?.preview.id == id { discardStagedBackup() }
        case .checkForUpdates:
            core.updateCoordinator.checkForUpdates()
        case .showSupport:
            core.supportCoordinator.showSupport()
        }
    }

    private func start(_ call: SettingsWire.Call, id: UUID) {
        guard let link, !isClosing, calls[id] == nil else { return }
        let report: @MainActor @Sendable (ExtensionCallEvent) -> Void = { [weak link] event in
            link?.send(.extensionProgress(id, event))
        }
        calls[id] = Task { [weak self, weak link] in
            guard let self, let link else { return }
            let reply: SettingsWire.Reply
            do {
                try Task.checkCancellation()
                switch call {
                case .extensions(let call): reply = try await performExtension(call, report: report)
                case .mcp(let call): reply = try await performMCP(call)
                case .backup(let call): reply = try await performBackup(call, id: id)
                }
            } catch is CancellationError {
                reply = .cancelled
            } catch {
                reply = .failure(error.localizedDescription)
            }
            calls[id] = nil
            guard self.link === link, !isClosing else { return }
            mirror?.flush()
            if case .mcp = call { send(makeStatus()) }
            link.send(.reply(id, reply))
        }
    }

    private func performExtension(
        _ call: ExtensionCall, report: @escaping @MainActor @Sendable (ExtensionCallEvent) -> Void
    ) async throws -> SettingsWire.Reply {
        let extensions = core.extensions
        let onProgress: @Sendable (ExtensionInstaller.Progress) -> Void = { progress in
            Task { @MainActor in report(.installing(progress)) }
        }
        var result = ExtensionCallResult()
        switch call {
        case .refresh:
            await extensions.refresh()
        case .checkForUpdates:
            await extensions.checkForUpdates()
        case .installFolder(let folder):
            try await extensions.install(from: folder)
        case .importFromRaycast(let directories):
            let chosen = await Task.detached(priority: .userInitiated) {
                ExtensionCatalog.importableFromRaycast().filter { directories.contains($0.directory) }
            }.value
            try Task.checkCancellation()
            result.failures = await extensions.importAllFromRaycast(chosen) { report(.imported($0)) }
        case .update(let names):
            result.failures = await extensions.update(names)
        case .installListing(let listing):
            try await extensions.install(listing, onProgress: onProgress)
        case .installGitHub(let source):
            let settings = core.settings
            result.installedTitle = try await extensions.install(
                source, packageManager: settings.extensionPackageManager,
                additionalSearchPaths: settings.extensionCustomSearchPaths,
                onProgress: onProgress
            ).title
        case .uninstall(let name):
            if let owner = extensions.installed.first(where: { $0.manifest.name == name }) {
                await extensions.uninstall(owner)
            }
        }
        return .extensions(result)
    }

    private func performMCP(_ call: MCPSettingsCall) async throws -> SettingsWire.Reply {
        let coordinator = core.mcpCoordinator
        switch call {
        case .signIn(let server, let credentials):
            if core.mcpSettings.server(id: server.id) == nil { unsavedMCPServers.insert(server.id) }
            try await coordinator.signIn(server, credentials: credentials)
        case .signOut(let id):
            try coordinator.signOut(id)
        case .test(let server, let secrets):
            return .mcp(await coordinator.test(server, secrets: secrets))
        case .save(let server, let secrets):
            try coordinator.save(server, secrets: secrets)
            unsavedMCPServers.remove(server.id)
        case .remove(let id):
            try coordinator.remove(id)
        }
        return .mcp(nil)
    }

    private func performBackup(_ call: BackupSettingsCall, id: UUID) async throws -> SettingsWire.Reply {
        switch call {
        case .prepare(let file):
            let generation = generation
            let (staging, preview) = try await BackupActions.openBackup(at: file, id: id)
            guard generation == self.generation, !Task.isCancelled, !isClosing else {
                staging.discard()
                throw CancellationError()
            }
            discardStagedBackup()
            stagedBackup = (preview, staging)
            return .backupPreview(preview)
        case .apply(let id, let categories):
            guard let stagedBackup, stagedBackup.preview.id == id else { throw CancellationError() }
            self.stagedBackup = nil
            defer { stagedBackup.staging.discard() }
            let selected = categories.intersection(stagedBackup.preview.manifest.categories)
            let summary = await Task {
                await BackupApplier.apply(selected, from: stagedBackup.staging.bundle, to: core)
            }.value
            return .backupMessage(BackupActions.summaryText(summary))
        case .export(let destination, let categories):
            let result = try await BackupActions.exportBackup(
                core: core, categories: categories, to: destination)
            return .backupMessage(BackupActions.exportText(result))
        case .importRaycast(let url, let passphrase, let options):
            let result = try await Task {
                try await BackupActions.importRaycast(
                    core: core, file: url, passphrase: passphrase, options: options)
            }.value
            return .backupMessage(BackupActions.raycastText(result))
        }
    }

    private func discardStagedBackup() {
        stagedBackup?.staging.discard()
        stagedBackup = nil
    }

    private func inspectHyperKey(diagnostics: Bool) {
        let manager = core.hyperKey
        let report = diagnostics ? manager.diagnostics() : nil
        hyperKeyInspection = HyperKeyInspection(
            takeover: report?.takeover ?? manager.takeover(), diagnostics: report)
        send(makeStatus())
    }

    // MARK: - Status

    /// Coalesced, so a download's progress costs a message a tick rather than one per byte.
    private func observeStatus() {
        let generation = generation
        let status = withObservationTracking {
            makeStatus()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.generation == generation else { return }
                observeStatus()
            }
        }
        send(status)
    }

    private func send(_ status: MainAppStatus) {
        guard let link, !isClosing, status != lastStatus else { return }
        lastStatus = status
        link.send(.status(status))
    }

    private func makeStatus() -> MainAppStatus {
        let models = core.dictationModels
        let progress = models.downloadProgress
        let cloud = core.cloudSyncCoordinator
        let updates = core.updateCoordinator
        return MainAppStatus(
            hiddenCommands: core.appIndex.hiddenCommands,
            unlistedCommands: core.appIndex.unlistedCommands,
            launcherRankingIsEmpty: core.launcherRanking.isEmpty,
            hyperKey: MainAppStatus.HyperKey(
                status: core.hyperKey.status, route: core.hotKeys.capture.hyperRoute,
                takeover: hyperKeyInspection.takeover, diagnostics: hyperKeyInspection.diagnostics),
            modifierTapsNeedAccessibility: core.hotKeys.modifierTapMonitor.needsAccessibility,
            snippetsNeedAccessibility: core.snippetListener.status == .needsAccessibility,
            fileIndex: core.fileIndexer.status,
            cloudSync: MainAppStatus.CloudSync(
                status: cloud.status, stopReason: cloud.stopReason, counts: cloud.counts,
                thisMac: cloud.devices.name, otherDevices: cloud.otherDevices),
            dictationModels: MainAppStatus.DictationModels(
                installed: models.installedModels, downloading: models.downloading,
                received: progress?.received, total: progress?.total, removing: models.removing,
                transcribing: models.transcribing),
            mcpStatuses: Dictionary(
                uniqueKeysWithValues: core.mcpSettings.servers.map {
                    ($0.id, core.mcpCoordinator.status(of: $0.id))
                }),
            mcpAuthentication: core.mcpOAuth.statuses,
            updates: MainAppStatus.Updates(
                updatesItself: updates.updatesItself, isChecking: updates.isChecking,
                lastCheckedAt: updates.lastCheckedAt, availableVersion: updates.availableVersion?.description),
            extensions: extensionsStatus())
    }

    private func extensionsStatus() -> MainAppStatus.Extensions {
        let extensions = core.extensions
        var status = MainAppStatus.Extensions(
            catalogRevision: extensions.installed.hashValue,
            updates: extensions.updates.mapValues(\.title), updating: extensions.updating)
        for owner in extensions.installed {
            let name = owner.manifest.name
            status.appearances[name] = extensions.appearances.appearance(for: name)
            for command in owner.manifest.commands {
                var metadata = extensions.backgroundInfo(extension: name, command: command.name)
                metadata.menuBarSnapshot = nil
                let reference = ExtensionCommandRef(extensionName: name, commandName: command.name)
                status.commands[reference.entryID] = metadata
            }
        }
        return status
    }
}
