// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit

/// Owns rooms: presence, the one enter funnel with its gate, the preview, the picker, cleanup.
@MainActor
@Observable
final class RoomCoordinator {
    @ObservationIgnored private let store: RoomStore
    @ObservationIgnored private let minimums: RoomMinimumSizeStore
    @ObservationIgnored private let ledger: RoomParkingLedger
    @ObservationIgnored private let session: RoomSession
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let appIndex: AppIndex
    @ObservationIgnored private let hotKeys: HotKeyManager
    @ObservationIgnored private let favorites: FavoritesStore
    @ObservationIgnored private let visibility: VisibilityStore
    @ObservationIgnored private let ranking: LauncherRankingStore
    @ObservationIgnored private let aliases: AliasStore
    @ObservationIgnored private let palette: PaletteState
    @ObservationIgnored private let paletteCoordinator: PaletteCoordinator
    /// Dialog and message-HUD presentation. Never state this type owns.
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private let preview = RoomPreviewController()
    /// Window work runs one at a time, in order: two passes at once would undo each other.
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Set while ↵ has handed the preview to the windows moving in under it.
    @ObservationIgnored private var isEntering = false
    /// The room whose windows the picker starts with, held until the desk has been read.
    @ObservationIgnored private var pendingPreselection: Room?
    /// Apps rooms hid since the feature was last switched off; a ⌘H of the user's is never here.
    @ObservationIgnored private var hiddenByRooms = Set<pid_t>()
    /// The desk read in flight, so two openings in one turn sweep once.
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// The room last entered and not yet left, which the Rooms screen marks.
    private(set) var currentRoomID: UUID?

    init(
        store: RoomStore, minimums: RoomMinimumSizeStore, ledger: RoomParkingLedger,
        session: RoomSession, settings: AppSettings, appIndex: AppIndex, hotKeys: HotKeyManager,
        favorites: FavoritesStore, visibility: VisibilityStore, ranking: LauncherRankingStore,
        aliases: AliasStore, palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.minimums = minimums
        self.ledger = ledger
        self.session = session
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    private static let commands: Set<CommandID> = [.switchRoom, .createRoom]

    // MARK: - Feature presence

    func applyRoomsPresence() {
        let enabled = settings.windowManagementEnabled
        appIndex.setWindowRooms(enabled && settings.windowRoomsShowInLauncher ? store.rooms : [])
        appIndex.setCommandsVisible(Self.commands, enabled)
        appIndex.setCommandsListed(Self.commands, settings.windowRoomsShowInLauncher)
    }

    /// Switching the feature off brings every parked window home, and the room's hidden apps.
    func applyEnabled() {
        applyRoomsPresence()
        guard !settings.windowManagementEnabled else { return }
        if palette.mode == .rooms || palette.mode == .roomWindows { palette.prepare(mode: .launcher) }
        let hidden = hiddenByRooms
        hiddenByRooms = []
        currentRoomID = nil
        inTurn { [ledger] in await RoomRunner.restoreEverything(hiddenApps: hidden, ledger: ledger) }
    }

    /// Windows a crash left parked come home at launch; nothing is unhidden, nothing else moves.
    func recoverParkedWindows() {
        guard !ledger.isEmpty, Permissions.isAccessibilityTrusted() else { return }
        inTurn { [ledger] in RoomRunner.returnParkedWindows(ledger: ledger) }
    }

    /// Synchronous, so no window is left off-screen once Tinycast is gone.
    func prepareForTermination() {
        work?.cancel()
        work = nil
        preview.hide()
        RoomRunner.returnParkedWindows(ledger: ledger)
    }

    // MARK: - The Rooms screen

    func showRooms() {
        guard settings.windowManagementEnabled else { return }
        guard Permissions.ensureAccessibility() else {
            Task { await reportPermissionFailure() }
            return
        }
        paletteCoordinator.togglePalette(mode: .rooms)
    }

    /// Every open reads the desk anew, one turn after the screen appears so it never waits on AX.
    func load() {
        guard settings.windowManagementEnabled, Permissions.isAccessibilityTrusted() else { return }
        guard !session.isLoaded, loading == nil else { return }
        loading = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            self.loading = nil
            guard !Task.isCancelled, self.isScreenOpen else { return }
            self.session.present(
                RoomWindowSweep.snapshot(), parked: Set(self.ledger.entries.keys))
            self.applyPreselection()
        }
    }

    /// Leaving both Rooms screens drops the desk and the preview, unless a room is moving in.
    func screensDidClose() {
        pendingPreselection = nil
        loading?.cancel()
        loading = nil
        session.reset()
        if !isEntering { preview.hide() }
    }

    func paletteDidHide() {
        guard !isEntering else { return }
        pendingPreselection = nil
        loading?.cancel()
        loading = nil
        session.reset()
        preview.hide()
    }

    private var isScreenOpen: Bool {
        palette.isVisible && (palette.mode == .rooms || palette.mode == .roomWindows)
    }

    func rows(for query: String) -> [RoomRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let recent = store.rooms.sorted(by: Room.enteredMoreRecently)
        let folded = FuzzyMatch.Query(trimmed)
        let matched =
            folded.isEmpty
            ? recent
            : recent.enumerated()
                .compactMap { position, room -> (Room, Int, Int)? in
                    let fields = SearchFields(
                        [SearchAlias.name(room.name)]
                            + room.windows.map { SearchAlias.owner($0.appName) })
                    return SearchRelevance.quality(folded, fields: fields).map { (room, $0, position) }
                }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
                .map(\.0)
        var rows = matched.map(RoomRow.room)
        if !trimmed.isEmpty {
            let existing = store.room(named: trimmed)
            rows.append(existing.map { .edit($0) } ?? .create(name: trimmed))
        }
        return rows
    }

    func layout(of room: Room) -> RoomLayoutKind {
        room.layout(onDisplay: targetDisplayUUID)
    }

    /// Tab: the next layout that fits here, and the preview glides to it.
    func cycleLayout(of room: Room, backwards: Bool) {
        guard let snapshot = session.snapshot, let screen = snapshot.screen(uuid: targetDisplayUUID)
        else { return }
        let choices = RoomPlan.layoutChoices(
            for: room, windows: snapshot.windows, on: screen, gap: gap,
            minimums: minimums.sizes, claimed: store.claimedWindowIDs(excluding: room.id))
        guard
            let next = RoomPlan.nextLayout(
                after: room.layout(onDisplay: screen.display.uuid), in: choices,
                backwards: backwards)
        else {
            core.showMessage("Only one layout fits these windows here", tone: .neutral)
            return
        }
        // The screen previews the selected room as it changes, so the cards glide from here.
        store.setLayout(next, for: room.id, onDisplay: screen.display.uuid)
    }

    /// What the room looks like on this display, drawn from the desk the screen read.
    func preview(_ room: Room?) {
        guard let room, let snapshot = session.snapshot,
            let screen = snapshot.screen(uuid: targetDisplayUUID)
        else { return preview.hide() }
        let plan = RoomPlan.make(
            room, windows: snapshot.windows, on: screen, gap: gap, minimums: minimums.sizes,
            claimed: store.claimedWindowIDs(excluding: room.id))
        let cards = plan.placements.compactMap { placement in
            snapshot.window(placement.handle).map { card(for: $0, at: placement.frame) }
        }
        guard !cards.isEmpty else { return preview.hide() }
        // Back to front, so the main window's card ends on top, as the window itself will.
        preview.show(cards.reversed(), avoiding: paletteCoordinator.panelFrame)
    }

    // MARK: - Entering

    /// The one funnel for a Rooms row, a launcher entry, a shortcut and the pane alike.
    func enterRoom(id: UUID) {
        guard settings.windowManagementEnabled, let room = store.room(id: id) else { return }
        // The preview holds while the windows move in under it, then fades.
        isEntering = preview.isShowing
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        let context = RoomRunner.Context(
            gap: gap, displayUUID: targetDisplayUUID,
            claimed: store.claimedWindowIDs(excluding: room.id), minimums: minimums, ledger: ledger)
        inTurn { [weak self] in
            let outcome = await RoomRunner.enter(room, context: context)
            guard let self else { return }
            self.isEntering = false
            self.preview.hide(settling: true)
            self.session.reset()
            self.hiddenByRooms.formUnion(outcome.hiddenApps)
            if outcome.placed > 0 {
                self.currentRoomID = room.id
                self.store.markEntered(id: room.id, at: Date())
            }
            await self.report(outcome, for: room)
        }
    }

    private func inTurn(_ body: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await body()
        }
    }

    // MARK: - Making and editing rooms

    /// The picker for a room named on the Rooms screen; with no name yet, that screen first.
    func createRoom(named name: String = "") {
        guard settings.windowManagementEnabled else { return }
        guard !name.isEmpty else {
            if paletteCoordinator.isShowing(.rooms) { nameIsMissing() } else { showRooms() }
            return
        }
        guard Permissions.ensureAccessibility() else {
            Task { await reportPermissionFailure() }
            return
        }
        openPicker(editing: nil, name: name)
    }

    func editWindows(of room: Room) {
        openPicker(editing: room, name: room.name)
    }

    private func openPicker(editing room: Room?, name: String) {
        if paletteCoordinator.isVisible {
            palette.push(mode: .roomWindows)
        } else {
            paletteCoordinator.showPalette(mode: .roomWindows)
        }
        session.beginPicking(named: name, editing: room?.id, picked: [])
        // A push opens no screen through the coordinator, so the desk is read from here.
        load()
        preselect(room)
    }

    /// An edited room's windows start picked, in its order; a new room starts with none.
    private func preselect(_ room: Room?) {
        pendingPreselection = room
        applyPreselection()
    }

    /// Runs once the desk is read: before then there are no windows to match against.
    private func applyPreselection() {
        guard let room = pendingPreselection, let snapshot = session.snapshot else { return }
        pendingPreselection = nil
        let assignment = RoomWindowMatcher.assign(
            room.windows, to: snapshot.windows, claimed: store.claimedWindowIDs(excluding: room.id))
        // A member with no open window stays in the room as its app, not dropped.
        let picks = room.windows.indices.map { index -> RoomSession.Pick in
            if let live = assignment[index] { return .window(handle: snapshot.windows[live].handle) }
            let window = room.windows[index]
            return .app(
                RoomSession.App(
                    bundleID: window.bundleID, name: window.appName,
                    url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleID)))
        }
        // Two closed windows of one app collapse into the one app they now stand for.
        var seen = Set<RoomSession.Pick>()
        session.beginPicking(
            named: room.name, editing: room.id, picked: picks.filter { seen.insert($0).inserted })
        previewPicked()
    }

    func togglePick(_ pick: RoomSession.Pick) {
        session.togglePick(pick)
        previewPicked()
    }

    /// Open windows matching `query`, then apps that are not open: those join as their app.
    func pickerRows(for query: String) -> [RoomPickerRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let windows =
            trimmed.isEmpty
            ? session.pickable
            : session.pickable.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.appName.localizedCaseInsensitiveContains(trimmed)
            }
        let open = Set(session.pickable.map(\.bundleID))
        let pickedApps = session.picked.compactMap { pick -> RoomSession.App? in
            guard case .app(let app) = pick else { return nil }
            return app
        }
        // Without a query only the picked apps show: the whole Applications folder is noise.
        let apps =
            trimmed.isEmpty
            ? pickedApps
            : appIndex.apps.lazy
                .filter { $0.kind == .application && $0.name.localizedCaseInsensitiveContains(trimmed) }
                .compactMap { entry -> RoomSession.App? in
                    guard let bundleID = entry.bundleID, !open.contains(bundleID) else { return nil }
                    return RoomSession.App(bundleID: bundleID, name: entry.name, url: entry.url)
                }
                .prefix(Self.appResultLimit).map { $0 }
        return windows.map(RoomPickerRow.window) + apps.map(RoomPickerRow.app)
    }

    private static let appResultLimit = 30

    /// The picked members as the room they would make here: Auto, in the order picked.
    func previewPicked() {
        guard let snapshot = session.snapshot, let screen = snapshot.screen(uuid: targetDisplayUUID)
        else { return }
        let members = session.picked.compactMap { member(for: $0, in: snapshot) }
        let frames = RoomLayoutEngine.frames(
            count: members.count, kind: .auto, in: screen.screen.visibleFrame, gap: gap,
            minimums: members.map { minimums.size(for: $0.bundleID) })
        let cards = zip(members, frames).map { member, frame in
            RoomPreviewCard(
                id: member.id, frame: frame, appName: member.appName, title: member.title,
                appURL: member.appURL)
        }
        guard !cards.isEmpty else { return preview.hide() }
        preview.show(cards.reversed(), avoiding: paletteCoordinator.panelFrame)
    }

    private struct Member {
        let id: String
        let bundleID: String
        let appName: String
        let title: String
        let appURL: URL?
    }

    private func member(for pick: RoomSession.Pick, in snapshot: RoomWindowSweep.Snapshot) -> Member? {
        switch pick {
        case .window(let handle):
            guard let window = snapshot.window(handle) else { return nil }
            return Member(
                id: card(for: window, at: .zero).id, bundleID: window.bundleID,
                appName: window.appName, title: window.title, appURL: window.appURL)
        case .app(let app):
            return Member(
                id: "app:" + app.bundleID, bundleID: app.bundleID, appName: app.name, title: "",
                appURL: app.url)
        }
    }

    func nameIsMissing() {
        core.showMessage("Type a name for the room first", tone: .neutral)
    }

    /// ⌘↵ in the picker: the picked windows and apps become the room, in the order picked.
    func savePicked() {
        guard let snapshot = session.snapshot else { return }
        let picks = session.picked
        guard !picks.isEmpty else {
            core.showMessage("Pick at least one window or app for the room", tone: .neutral)
            return
        }
        let name = session.roomName
        let base = session.editingID.flatMap(store.room(id:)) ?? Room(name: name)
        let windows = picks.compactMap { pick -> RoomLiveWindow? in
            guard case .window(let handle) = pick else { return nil }
            return snapshot.window(handle)
        }
        var room = base
        if !windows.isEmpty {
            guard let (learned, _) = learn(base, from: windows, in: snapshot, keepsOrder: true)
            else { return }
            room = learned
        }
        // `learn` keeps the picked order, so its windows slot back between the apps one by one.
        var learnedWindows = room.windows.makeIterator()
        room.windows = picks.compactMap { pick in
            switch pick {
            case .window: return learnedWindows.next()
            case .app(let app):
                return RoomWindow(bundleID: app.bundleID, appName: app.name, title: "")
            }
        }
        room.name = name
        do {
            if session.editingID == nil { try store.add(room) } else { try store.update(room) }
        } catch {
            core.showMessage(error.errorDescription ?? "Couldn't save the room", tone: .danger)
            return
        }
        enterRoom(id: room.id)
    }

    /// Remembers how the room's open windows sit now: the closest layout, or exactly as is.
    func rememberArrangement(of room: Room) {
        guard let snapshot = session.snapshot else { return }
        let assignment = RoomWindowMatcher.assign(
            room.windows, to: snapshot.windows, claimed: store.claimedWindowIDs(excluding: room.id))
        let arranged = room.windows.indices.filter { index in
            assignment[index].map { !snapshot.windows[$0].isMinimized && !snapshot.windows[$0].isAppHidden }
                ?? false
        }
        let windows = arranged.compactMap { assignment[$0].map { snapshot.windows[$0] } }
        // A member filled by title or by app has a new ID, so only the matcher knows it is here.
        let kept = room.windows.indices.filter { !arranged.contains($0) }.map { room.windows[$0] }
        guard !windows.isEmpty else {
            core.showMessage("None of \(room.name)’s windows are open", tone: .neutral)
            return
        }
        guard
            let (updated, reading) = learn(
                room, from: windows, keeping: kept, in: snapshot, keepsOrder: false)
        else { return }
        do {
            try store.update(updated)
        } catch {
            core.showMessage(error.errorDescription ?? "Couldn't save the room", tone: .danger)
            return
        }
        core.showMessage("\(room.name) — remembered as \(reading.kind.title)", tone: .success)
    }

    /// Read on the display most of the windows share, which is where their arrangement is.
    private func learn(
        _ room: Room, from windows: [RoomLiveWindow], keeping kept: [RoomWindow] = [],
        in snapshot: RoomWindowSweep.Snapshot, keepsOrder: Bool
    ) -> (Room, RoomArrangement.Reading)? {
        let screens = snapshot.screens.map(\.screen)
        let hosts = windows.map { WindowPlacementEngine.screen(containing: $0.frame, in: screens)?.id }
        let counts = Dictionary(grouping: hosts.compactMap { $0 }, by: { $0 }).mapValues(\.count)
        let host = counts.max { $0.value < $1.value }?.key
        guard
            let screen = snapshot.screens.first(where: { $0.screen.id == host })
                ?? snapshot.screen(uuid: targetDisplayUUID)
        else { return nil }
        let result = RoomArrangement.learn(
            room, from: windows, keeping: kept, on: screen, spansDisplays: counts.count > 1, gap: gap,
            minimums: windows.map { minimums.size(for: $0.bundleID) }, keepsOrder: keepsOrder)
        return (result.room, result.reading)
    }

    func deleteRoom(_ room: Room) {
        Task { [weak self] in
            guard let self else { return }
            let confirmed = await self.core.confirm(
                title: "Delete “\(room.name)”?",
                message: "Its windows stay open. Its shortcut goes with it.",
                symbol: Room.sfSymbol, confirmTitle: "Delete")
            guard confirmed, let removed = self.store.remove(id: room.id) else { return }
            if self.currentRoomID == removed.id { self.currentRoomID = nil }
            self.removeReferences(ids: [removed.id], entryIDs: [removed.entryID])
        }
    }

    @discardableResult
    func replaceRooms(_ incoming: [Room]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.rooms.map { ($0.id, $0) })
        let count = store.replace(with: incoming)
        let removed = Set(previous.keys).subtracting(store.rooms.map(\.id))
        removeReferences(ids: removed, entryIDs: Set(removed.compactMap { previous[$0]?.entryID }))
        return count
    }

    private func removeReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.windowRoom(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs { ranking.reset(itemKey: entryID) }
    }

    // MARK: - Helpers

    private var gap: CGFloat { CGFloat(settings.windowGap) }

    /// The display the palette opens on, so the room lands where the preview is drawn.
    private var targetDisplayUUID: String? {
        (settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary).flatMap(AXScreens.uuid)
    }

    private func card(for window: RoomLiveWindow, at frame: CGRect) -> RoomPreviewCard {
        RoomPreviewCard(
            id: window.windowID.map(String.init) ?? "\(window.bundleID)|\(window.handle)",
            frame: frame, appName: window.appName, title: window.title, appURL: window.appURL)
    }

    // MARK: - Reporting

    private func report(_ outcome: RoomRunner.Outcome, for room: Room) async {
        if outcome.isBlockedOnPermission { return await reportPermissionFailure() }
        guard outcome.placed > 0 else {
            await core.showNotice(
                title: "Couldn't Enter “\(room.name)”",
                message: "None of its windows are open. Open them, then choose them again.",
                symbol: Room.sfSymbol, tone: .danger)
            return
        }
        let missing = Set(outcome.missing).sorted()
        guard !missing.isEmpty else { return }
        core.showMessage(
            "\(room.name) — \(missing.joined(separator: ", ")) not open", tone: .neutral)
    }

    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: "Tinycast Needs Accessibility Access",
            message: "Rooms move and hide other apps' windows.",
            symbol: Room.sfSymbol, recovery: "Open Settings")
        if openSettings { Permissions.openAccessibilitySettings() }
    }
}

/// One row of the Rooms screen: a room, or the one typed name offered as a new room.
enum RoomRow: Identifiable, Hashable {
    case room(Room)
    /// The typed name is an existing room's: choose its windows again.
    case edit(Room)
    case create(name: String)

    var id: String {
        switch self {
        case .room(let room): room.entryID
        case .edit(let room): "edit:" + room.entryID
        case .create: "create-room"
        }
    }
}
