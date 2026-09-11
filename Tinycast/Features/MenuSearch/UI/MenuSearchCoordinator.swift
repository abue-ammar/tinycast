import AppKit

@MainActor
final class MenuSearchCoordinator {
    private let session: MenuSearchSession
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// The app the open snapshot belongs to; activation re-resolves against this, never a retarget.
    private var frozenApp: NSRunningApplication?

    init(
        session: MenuSearchSession, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.session = session
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func show() {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        let app = paletteCoordinator.targetApp
        frozenApp = app
        let target = MenuSearchTarget.classify(
            appName: app?.localizedName,
            isSelf: app?.bundleIdentifier == Bundle.main.bundleIdentifier,
            hasMenuBar: app?.activationPolicy == .regular)
        switch target {
        case .searchable:
            if let app {
                session.startWalk(target: target, pid: app.processIdentifier)
            } else {
                session.present(target: .noApplication, snapshot: [])
            }
        case .selfTarget, .menuLess, .noApplication:
            session.present(target: target, snapshot: [])
        }
        paletteCoordinator.togglePalette(mode: .menuSearch)
    }

    func activate(_ item: MenuSearchItem) {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        guard let app = frozenApp, !app.isTerminated else {
            Task { await self.reportGone(targetName: session.targetName) }
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        app.activate()
        let application = AXMenuAccess.application(for: app.processIdentifier)
        guard
            let leaf = AXMenuAccess.resolveLeaf(
                in: application, path: item.parentComponents, title: item.title),
            AXMenuAccess.isActionable(leaf),
            AXMenuAccess.press(leaf)
        else {
            Task { await self.reportPressFailure(item: item) }
            return
        }
    }

    // MARK: - Reporting

    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: "Tinycast Needs Accessibility Access",
            message: "Searching menus reads the front app's menu bar.",
            symbol: "menubar.rectangle", recovery: "Open Settings")
        if openSettings { Permissions.openAccessibilitySettings() }
    }

    private func reportGone(targetName: String?) async {
        await core.showNotice(
            title: "Couldn't Activate Menu Item",
            message: targetName.map { "\($0) is no longer running." }
                ?? "The application is no longer running.",
            symbol: "menubar.rectangle", tone: .danger)
    }

    private func reportPressFailure(item: MenuSearchItem) async {
        await core.showNotice(
            title: "Couldn't Activate “\(item.title)”",
            message: "Its menu changed before the press landed. Search again and retry.",
            symbol: "menubar.rectangle", tone: .danger)
    }
}
