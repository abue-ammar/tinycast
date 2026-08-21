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
        switch session.phase {
        case .processing:
            return false
        case .idle, .completed, .failed:
            return true
        }
    }

    func secondary(at selection: Int) -> Bool {
        if case .completed = session.phase {
            copyToClipboard()
            return true
        }
        return false
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []

        if case .completed = session.phase {
            items.append(
                PopoverMenuItem(
                    title: "Insert in Previous App",
                    systemImage: "arrow.down.doc",
                    shortcut: "↵",
                    action: { insertResult() }
                )
            )
            items.append(
                PopoverMenuItem(
                    title: "Copy to Clipboard",
                    systemImage: "doc.on.doc",
                    shortcut: "⌘C",
                    action: { copyToClipboard() }
                )
            )
            items.append(
                PopoverMenuItem(
                    title: "Regenerate",
                    systemImage: "arrow.clockwise",
                    shortcut: "⌘R",
                    action: { regenerate() }
                )
            )
        } else if case .failed = session.phase {
            items.append(
                PopoverMenuItem(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    shortcut: "↵",
                    action: { regenerate() }
                )
            )
        }

        return PopoverMenuContent(header: session.presetName, items: items)
    }

    func activate(at selection: Int) {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch session.phase {
        case .idle:
            if !query.isEmpty {
                refine(with: query)
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
        let key = SecretStore.secret(account: SecretStore.aiAPIKeyAccount) ?? ""
        session.regenerate(apiKey: key, baseURL: core.settings.aiBaseURL)
        vm.query = ""
    }

    private func refine(with query: String) {
        let key = SecretStore.secret(account: SecretStore.aiAPIKeyAccount) ?? ""
        session.refine(followUp: query, apiKey: key, baseURL: core.settings.aiBaseURL)
        vm.query = ""
    }
}
