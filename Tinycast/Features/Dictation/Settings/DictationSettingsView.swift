import AppKit
import AVFoundation
import SwiftUI

struct DictationSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var microphones: [AVCaptureDevice] = []
    @State private var modelSize: Int64?
    @State private var microphoneAccess = Permissions.microphoneAccess()
    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .dictationDictation, title: "Enable Dictation",
                        subtitle: "Transcribe speech on your Mac with a local model.")
                }
                if microphoneAccess != .authorized {
                    HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: SettingsListMetrics.iconSize)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Microphone access required")
                                .foregroundStyle(.orange)
                            Text("Needed to record your dictation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.Spacing.lg)
                        Button(
                            microphoneAccess == .notDetermined
                                ? "Grant Access…" : "Open System Settings"
                        ) {
                            if microphoneAccess == .notDetermined {
                                Task {
                                    _ = await Permissions.requestMicrophoneAccess()
                                    microphoneAccess = Permissions.microphoneAccess()
                                }
                            } else {
                                Permissions.openMicrophoneSettings()
                            }
                        }
                    }
                }
            }
            .settingsAnchor(.dictationDictation)

            if settings.dictationEnabled {
                Section {
                    Picker(selection: $settings.dictationMode) {
                        ForEach(DictationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        SettingsRowTitle(.dictationCommands, "Shortcut behavior")
                    }
                    HStack {
                        SettingsRowTitle(.dictationCommands, "Shortcut")
                        Spacer()
                        ShortcutRecorder(action: .dictation)
                    }
                    if settings.dictationMode == .pushToTalk {
                        let issue = coordinator.holdShortcutIssue
                        Text(
                            issue ?? "Hold a key combination or a single modifier; release it to transcribe. "
                                + "Double taps work in toggle mode."
                        )
                        .font(.caption)
                        .foregroundStyle(issue == nil ? Color.secondary : Color.orange)
                    }
                } header: {
                    SettingsSectionHeader(.dictationCommands)
                }

                Section {
                    Picker(selection: familyBinding) {
                        ForEach(DictationModel.Family.allCases) { family in
                            Text(family.rawValue).tag(family)
                        }
                    } label: {
                        SettingsRowTitle(.dictationModel, "Engine")
                        Text(
                            settings.dictationModel.family.summary + " · " + settings.dictationModel.coverage)
                    }
                    Picker(selection: $settings.dictationModel) {
                        ForEach(
                            DictationModel.allCases.filter { $0.family == settings.dictationModel.family }
                        ) { model in
                            Text(model.variantTitle).tag(model)
                        }
                    } label: {
                        SettingsRowTitle(.dictationModel, "Model")
                        Text(settings.dictationModel.summary)
                    }

                    let installed = coordinator.models.isInstalled(settings.dictationModel)
                    let downloading = coordinator.models.downloading == settings.dictationModel
                    if downloading {
                        DownloadProgressView(models: coordinator.models)
                    } else {
                        LabeledContent {
                            if installed {
                                Button("Remove") { removeModel(settings.dictationModel) }
                                    .disabled(
                                        coordinator.models.transcribing || coordinator.models.removing != nil)
                            } else {
                                Button("Download") { downloadModel(settings.dictationModel) }
                                    .disabled(
                                        coordinator.models.downloading != nil
                                            || coordinator.models.removing == settings.dictationModel)
                            }
                        } label: {
                            Text(installed ? "Installed" : "Not installed")
                            Text(modelDescription)
                        }
                    }
                    if settings.dictationModel.isQwen, installed {
                        Picker(selection: languageBinding) {
                            Text("Auto").tag("")
                            Divider()
                            ForEach(DictationLanguage.allCases) { language in
                                Text(language.rawValue).tag(language.rawValue)
                            }
                        } label: {
                            SettingsRowTitle(.dictationModel, "Language")
                        }
                    }
                } header: {
                    SettingsSectionHeader(.dictationModel)
                }

                Section {
                    Picker(selection: $settings.dictationIdleRelease) {
                        ForEach(DictationIdleRelease.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        SettingsRowTitle(.dictationMemory, "Release model from memory")
                    }
                } header: {
                    SettingsSectionHeader(.dictationMemory)
                } footer: {
                    Text("Releasing it when idle frees memory. The next dictation takes a moment longer.")
                }

                Section {
                    Picker(selection: microphoneBinding) {
                        Text(microphones.isEmpty ? "No microphone available" : "System default")
                            .tag("")
                        if !microphones.isEmpty { Divider() }
                        ForEach(microphones, id: \.uniqueID) { microphone in
                            Text(microphone.localizedName).tag(microphone.uniqueID)
                        }
                    } label: {
                        SettingsRowTitle(.dictationOutput, "Microphone")
                    }
                    Picker(selection: $settings.dictationDestination) {
                        ForEach(DictationDestination.allCases) { destination in
                            Text(destination.title).tag(destination)
                        }
                    } label: {
                        SettingsRowTitle(.dictationOutput, "When finished")
                    }
                    Toggle(isOn: $settings.dictationAdaptsCapitalization) {
                        SettingsRowTitle(.dictationOutput, "Adapt capitalization")
                        Text("Match the first letter to the text before the cursor.")
                    }
                } header: {
                    SettingsSectionHeader(.dictationOutput)
                } footer: {
                    Text(
                        "Press Return to finish dictating or Escape to cancel. Protected fields may refuse insertion."
                    )
                }

            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.dictation)
        .onAppear {
            microphoneAccess = Permissions.microphoneAccess()
            if settings.dictationEnabled { microphones = DictationCapture.microphones }
        }
        .onChange(of: settings.dictationEnabled) { _, enabled in
            if enabled { microphones = DictationCapture.microphones }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification)
            {
                microphoneAccess = Permissions.microphoneAccess()
                if settings.dictationEnabled { microphones = DictationCapture.microphones }
            }
        }
        .task(id: settings.dictationEnabled ? settings.dictationModel : nil) {
            modelSize = nil
            guard settings.dictationEnabled else { return }
            coordinator.models.refreshInstalledModels()
            await refreshModelSize(settings.dictationModel)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.dictationEnabled },
            set: { coordinator.setEnabled($0) })
    }

    private var microphoneBinding: Binding<String> {
        Binding(
            get: { settings.dictationMicrophone ?? "" },
            set: { settings.dictationMicrophone = $0.isEmpty ? nil : $0 })
    }

    private var familyBinding: Binding<DictationModel.Family> {
        Binding(
            get: { settings.dictationModel.family },
            set: {
                settings.dictationModel = $0 == .parakeet ? .redux : .qwenSmall
            })
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { settings.dictationLanguage ?? "" },
            set: {
                settings.dictationLanguage = $0.isEmpty ? nil : $0
            })
    }

    private var modelDescription: String {
        modelSize.map { "\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)) on disk" }
            ?? "About \(settings.dictationModel.approximateInstalledMegabytes) MB on disk"
    }

    private struct DownloadProgressView: View {
        let models: DictationModelStore

        var body: some View {
            let progress = models.downloadProgress
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                LabeledContent {
                    Button("Cancel") { models.cancelDownload() }
                } label: {
                    Text(title)
                }
                if let progress, progress.total > 0 {
                    ProgressView(value: Double(progress.received), total: Double(progress.total))
                        .tint(.accentColor)
                        .accessibilityLabel("Model download progress")
                    HStack {
                        let received = progress.received.formatted(.byteCount(style: .file))
                        let total = progress.total.formatted(.byteCount(style: .file))
                        Text("\(received) of \(total)")
                        Spacer()
                        Text(
                            Double(progress.received) / Double(progress.total),
                            format: .percent.precision(.fractionLength(0)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Preparing model download")
                }
            }
        }

        private var title: String {
            guard let progress = models.downloadProgress else { return "Preparing download…" }
            return progress.total > 0 && progress.received >= progress.total
                ? "Finishing download…" : "Downloading model…"
        }
    }

    private func refreshModelSize(_ model: DictationModel) async {
        let size = await coordinator.models.installedSize(model)
        if !Task.isCancelled, settings.dictationModel == model { modelSize = size }
    }

    private func downloadModel(_ model: DictationModel) {
        Task {
            await coordinator.downloadModel(model)
            await refreshModelSize(model)
        }
    }

    private func removeModel(_ model: DictationModel) {
        Task {
            await coordinator.removeModel(model)
            await refreshModelSize(model)
        }
    }
}
