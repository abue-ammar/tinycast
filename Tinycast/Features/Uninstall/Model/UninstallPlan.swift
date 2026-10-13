import Foundation

/// Bytes, plus whether the walk hit its budget so a huge tree can honestly read "at least".
struct MeasuredSize: Hashable, Sendable {
    var bytes: Int64 = 0
    var isLowerBound = false

    static let zero = MeasuredSize()

    var formatted: String {
        // Without this an empty folder renders as "Zero kB", which reads as a bug.
        let size = bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
        return isLowerBound ? "≥ " + size : size
    }
}

struct UninstallCandidate: Identifiable, Hashable, Sendable {
    /// Standardized, and what `UninstallSelection` stores.
    let path: String
    /// Row title, with `.app` stripped from the bundle.
    let name: String
    /// Row subtitle: the enclosing directory, tilde-abbreviated.
    let locationLabel: String
    let evidence: UninstallEvidence
    let isDirectory: Bool
    /// Nil until a directory's walk lands; a file's size comes straight from its `lstat`.
    var size: MeasuredSize?
    let protection: UninstallProtection

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var isLocked: Bool { !protection.isRemovable }
    var lockReason: String? { protection.lockReason }
}

/// Everything attributable to one app, bundle pinned first.
struct UninstallPlan: Equatable, Sendable {
    let target: UninstallTarget
    var candidates: [UninstallCandidate]
    let isTargetRunning: Bool

    var removableIDs: Set<UninstallCandidate.ID> {
        Set(candidates.lazy.filter { !$0.isLocked }.map(\.id))
    }

    var lockedCount: Int { candidates.count { $0.isLocked } }

    var totalBytes: Int64 { candidates.reduce(0) { $0 + ($1.size?.bytes ?? 0) } }

    /// Everything removable, name matches included: exact, confined, and undoable.
    var defaultSelection: UninstallSelection {
        UninstallSelection(plan: self, checked: removableIDs)
    }

    /// How a walk lands on the row it measured, without disturbing the order or the checked set.
    mutating func setSize(_ size: MeasuredSize, forPath path: String) {
        guard let index = candidates.firstIndex(where: { $0.path == path }) else { return }
        candidates[index].size = size
    }
}

/// The one holder of the checked set; one intersection keeps a locked candidate out.
struct UninstallSelection: Equatable, Sendable {
    private(set) var checked: Set<UninstallCandidate.ID>

    init(plan: UninstallPlan, checked: Set<UninstallCandidate.ID> = []) {
        self.checked = checked.intersection(plan.removableIDs)
    }

    mutating func toggle(_ id: UninstallCandidate.ID, in plan: UninstallPlan) {
        if checked.contains(id) {
            checked.remove(id)
        } else if plan.removableIDs.contains(id) {
            checked.insert(id)
        }
    }

    func isChecked(_ id: UninstallCandidate.ID) -> Bool { checked.contains(id) }

    var count: Int { checked.count }

    func bytes(in plan: UninstallPlan) -> Int64 {
        plan.candidates.reduce(0) { $0 + (checked.contains($1.id) ? ($1.size?.bytes ?? 0) : 0) }
    }

    func candidates(in plan: UninstallPlan) -> [UninstallCandidate] {
        plan.candidates.filter { checked.contains($0.id) }
    }
}
