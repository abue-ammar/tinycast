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
    /// Bumped as each process ends, so its status observer cannot outlive it.
    private var generation = 0

    init(core: AppCore) {
        self.core = core
    }

    func show(_ request: SettingsRequest) {
        guard let link else { return launch(request) }
        mirror?.flush()
        link.send(.show(request))
    }

    func focus() -> Bool {
        guard link != nil else { return false }
        show(SettingsRequest())
        return true
    }

    private func launch(_ request: SettingsRequest) {
        let link: ProcessLink<SettingsWire.ToSettings, SettingsWire.ToMainApp>
        do {
            link = try .spawn(.settings)
        } catch {
            core.showMessage(String(localized: "Couldn't open Settings"), tone: .danger)
            return
        }
        let mirror = core.makeSharedStateMirror { [weak link] in link?.send(.changed($0)) }
        link.onReceive = { [weak self] in self?.receive($0) }
        link.onClose = { [weak self] in self?.didClose() }
        self.link = link
        self.mirror = mirror
        link.start()
        mirror.start()
        link.send(.show(request))
        observeStatus()
    }

    private func receive(_ message: SettingsWire.ToMainApp) {
        switch message {
        case .changed(let change): mirror?.apply(change)
        case .recordingShortcut(let recording): core.hotKeys.isRecordingInSettings = recording
        case .perform(let action): perform(action)
        case .call(let id, let call): calls[id] = run(call, id: id)
        case .cancelCall(let id): calls.removeValue(forKey: id)?.cancel()
        case .openURL(let url): core.handleOpenURL(url)
        case .activate: activateSettings()
        }
    }

    /// This app received the click or key that asked for Settings, so only it may pass focus on.
    private func activateSettings() {
        guard let pid = link?.childProcessIdentifier,
            let settings = NSRunningApplication(processIdentifier: pid)
        else { return }
        settings.activate(from: .current)
    }

    private func didClose() {
        link = nil
        mirror = nil
        lastStatus = nil
        hyperKeyInspection = HyperKeyInspection()
        calls.values.forEach { $0.cancel() }
        calls = [:]
        generation += 1
        // A Settings process that died mid-recording would otherwise leave every shortcut off.
        core.hotKeys.isRecordingInSettings = false
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
        case .editQuicklink(let id):
            core.quicklinkCoordinator.editQuicklink(id.flatMap(core.quicklinks.quicklink(id:)))
        case .editSnippet(let id):
            core.snippetCoordinator.editSnippet(id.flatMap(core.snippetsStore.record(id:)))
        case .createRoom:
            core.roomCoordinator.createRoom()
        case .editRoomWindows(let id):
            guard let room = core.rooms.room(id: id) else { return }
            core.roomCoordinator.editWindows(of: room)
        case .enterRoom(let id):
            core.roomCoordinator.enterRoom(id: id)
        case .runWindowLayout(let id):
            core.windowLayoutCoordinator.runWindowLayout(id: id)
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
        case .reconnectMCPServer(let id):
            core.mcpCoordinator.reconnect(id)
        case .disconnectMCPServer(let id):
            core.mcpCoordinator.disconnectSignedOut(id)
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
        case .reloadImportedData:
            core.launcherRanking.reload()
            core.frequentEmoji.reload()
            core.calcHistory.reload()
            core.pinnedEmoji.reload()
            core.clipboardStore.load()
            Task { _ = await core.notesStore.reload() }
        case .checkForUpdates:
            core.updateCoordinator.checkForUpdates()
        case .showSupport:
            core.supportCoordinator.showSupport()
        }
    }

    /// The extension runtime is the main app's; a later extensions process slots in behind this.
    private func run(_ call: ExtensionCall, id: UUID) -> Task<Void, Never> {
        let extensions = core.extensions
        let report: @MainActor @Sendable (ExtensionCallEvent) -> Void = { [weak self] event in
            self?.link?.send(.callEvent(id, event))
        }
        let onProgress: @Sendable (ExtensionInstaller.Progress) -> Void = { progress in
            Task { @MainActor in report(.installing(progress)) }
        }
        return Task {
            var result = ExtensionCallResult()
            do {
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
                    result.failures = await extensions.importAllFromRaycast(chosen) { report(.imported($0)) }
                case .update(let names):
                    result.failures = await extensions.update(names)
                case .installListing(let listing):
                    try await extensions.install(listing, onProgress: onProgress)
                case .installGitHub(let source):
                    let settings = core.settings
                    result.installedTitle =
                        try await extensions.install(
                            source, packageManager: settings.extensionPackageManager,
                            additionalSearchPaths: settings.extensionCustomSearchPaths,
                            onProgress: onProgress
                        ).title
                case .uninstall(let name):
                    if let owner = extensions.installed.first(where: { $0.manifest.name == name }) {
                        await extensions.uninstall(owner)
                    }
                }
            } catch {
                result.error = error.localizedDescription
            }
            calls[id] = nil
            report(.finished(result))
        }
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
        guard let link, status != lastStatus else { return }
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
