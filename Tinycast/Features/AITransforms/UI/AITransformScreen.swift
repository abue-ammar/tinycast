import AppKit
import SwiftUI

/// The palette screen presenting the interactive AI transformation session.
struct AITransformScreen: PaletteScreen {
    struct EmptyRow: Identifiable {
        let id = 0
    }

    let session: AITransformSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [EmptyRow] { [EmptyRow()] }

    var primaryActionTitle: String {
        switch session.phase {
        case .idle:
            return "Transform"
        case .processing:
            return "Processing…"
        case .completed:
            return vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Insert" : "Refine"
        case .failed:
            return "Retry"
        }
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        !session.isProcessing
    }

    func secondary(at selection: Int) -> Bool {
        copyAction()
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        if case .completed = session.phase {
            items = [
                PopoverMenuItem(
                    title: "Insert in Previous App", systemImage: "arrow.down.doc", shortcut: "↵",
                    action: { insertResult() }),
                PopoverMenuItem(
                    title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘C",
                    action: { copyToClipboard() }),
                PopoverMenuItem(
                    title: "Regenerate", systemImage: "arrow.clockwise", shortcut: "⌘R",
                    action: { regenerate() })
            ]
            if !session.originalSelection.isEmpty {
                items.append(
                    PopoverMenuItem(
                        title: session.isShowingDiff ? "Show Clean Text" : "Show Diff Highlights",
                        systemImage: "plusminus", shortcut: "⌘D",
                        action: { session.toggleDiff() }))
                items.append(
                    PopoverMenuItem(
                        title: "Copy Original Input", systemImage: "text.quote",
                        action: {
                            Paster.copyPlainText(session.originalSelection)
                            core.showMessage("Copied original text", tone: .neutral)
                        }))
            }
        } else if case .failed = session.phase {
            items = [
                PopoverMenuItem(
                    title: "Retry", systemImage: "arrow.clockwise", shortcut: "↵",
                    action: { regenerate() })
            ]
        }
        return PopoverMenuContent(header: session.presetName, items: items)
    }

    func activate(at selection: Int) {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch session.phase {
        case .idle:
            if !query.isEmpty {
                Task {
                    let (key, baseURL) = await resolveCredentials()
                    session.executeCustomInput(query, apiKey: key, baseURL: baseURL)
                }
                vm.query = ""
            }
        case .processing:
            break
        case .completed:
            if !query.isEmpty {
                refine(with: query)
            } else {
                insertResult()
            }
        case .failed:
            if !query.isEmpty {
                refine(with: query)
            } else {
                regenerate()
            }
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            AITransformScreenView(
                session: session,
                onInsert: { insertResult() },
                onCopy: { copyToClipboard() },
                onRegenerate: { regenerate() },
                onRetry: { regenerate() }
            )
        )
    }

    func regenerateAction() {
        if case .completed = session.phase {
            regenerate()
        }
    }

    func copyAction() -> Bool {
        if case .completed = session.phase {
            copyToClipboard()
            return true
        }
        return false
    }
    func toggleDiffAction() -> Bool {
        if case .completed = session.phase, !session.originalSelection.isEmpty {
            session.toggleDiff()
            return true
        }
        return false
    }

    // MARK: - Actions

    private func insertResult() {
        let output = session.currentOutput
        guard !output.isEmpty else { return }
        let target = session.targetApp
        let original = session.originalSelection
        let presetName = session.presetName

        // Close palette first
        core.paletteCoordinator.hidePalette(restoreFocus: false)

        Task {
            let outcome = await core.aiTextDelivery.replaceSelection(
                output,
                originalSelection: original,
                in: target
            )
            switch outcome {
            case .replaced, .pasted:
                core.showMessage("“\(presetName)” applied", tone: .neutral)
            case .copiedToClipboard:
                core.showMessage("Couldn’t paste back — result copied", tone: .neutral)
            case .failed(let msg):
                await core.showNotice(
                    title: presetName, message: msg, symbol: "exclamationmark.triangle", tone: .danger)
            }
        }
    }

    private func copyToClipboard() {
        let output = session.currentOutput
        guard !output.isEmpty else { return }
        Paster.copyPlainText(output)
        core.showMessage("Copied to clipboard", tone: .neutral)
    }

    private func regenerate() {
        Task {
            let (key, baseURL) = await resolveCredentials()
            session.regenerate(apiKey: key, baseURL: baseURL)
        }
        vm.query = ""
    }

    private func refine(with query: String) {
        Task {
            let (key, baseURL) = await resolveCredentials()
            session.refine(followUp: query, apiKey: key, baseURL: baseURL)
        }
        vm.query = ""
    }

    private func resolveCredentials() async -> (key: String, baseURL: String) {
        if let preset = session.preset,
            let config = await core.aiTransformCoordinator.resolveConfig(for: preset)
        {
            return (config.key, config.baseURL.absoluteString)
        }
        let fallbackKey = SecretStore.secret(account: SecretStore.aiAPIKeyAccount) ?? ""
        return (fallbackKey, core.settings.aiBaseURL)
    }
}
