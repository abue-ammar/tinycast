import Foundation

/// State one role changed, for the other to adopt from the storage both of them share.
enum SharedChange: Codable, Sendable {
    case defaultsEdit(SharedDefaultsEdit)
    case defaultsState(SharedDefaultsState)
    case domain(SharedDomain)
}

/// Shared state kept outside `UserDefaults`, re-read whole when the other role changes it.
enum SharedDomain: String, Codable, CaseIterable, Sendable {
    case quicklinks
    case chatPresets
    case customQuickActions
    case launchAtLogin
    case launcherRanking
    case frequentEmoji
    case calculatorHistory
}

/// Keeps two roles' copies of shared state in step: a change says what to re-read, never how.
@MainActor
final class SharedStateMirror {
    struct Domain {
        let observe: () -> Void
        let reload: () -> Void
        /// Awaited before the peer is told, for a store whose write lands after its change.
        let settle: @MainActor () async -> Void

        init(
            observe: @escaping () -> Void, reload: @escaping () -> Void,
            settle: @escaping @MainActor () async -> Void = {}
        ) {
            self.observe = observe
            self.reload = reload
            self.settle = settle
        }
    }

    private let defaultsMirror: SharedDefaultsMirror
    private let send: (SharedChange) -> Void
    private let domains: [SharedDomain: Domain]
    /// Bumped before a peer's change is re-read, so the stale observer it trips stays quiet.
    private var generations: [SharedDomain: Int] = [:]

    init(
        domain: (SharedDomain) -> Domain, reloadDefaults: @escaping () -> Void,
        send: @escaping (SharedChange) -> Void
    ) {
        domains = Dictionary(uniqueKeysWithValues: SharedDomain.allCases.map { ($0, domain($0)) })
        self.send = send
        defaultsMirror = SharedDefaultsMirror(
            role: .current, defaults: .standard, domainName: Bundle.main.bundleIdentifier ?? "",
            reload: reloadDefaults, send: send)
    }

    func start() {
        defaultsMirror.start()
        for domain in domains.keys { watch(domain) }
    }

    func apply(_ change: SharedChange) {
        switch change {
        case .defaultsEdit(let edit): defaultsMirror.apply(edit)
        case .defaultsState(let state): defaultsMirror.apply(state)
        case .domain(let domain):
            generations[domain, default: 0] += 1
            domains[domain]?.reload()
            watch(domain)
        }
    }

    func flush() { defaultsMirror.flush() }

    private func watch(_ domain: SharedDomain) {
        guard let entry = domains[domain] else { return }
        let generation = generations[domain, default: 0]
        withObservationTracking(entry.observe) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generations[domain, default: 0] == generation else { return }
                watch(domain)
                await domains[domain]?.settle()
                send(.domain(domain))
            }
        }
    }
}

struct SharedDefaultsEdit: Codable, Sendable {
    let revision: UInt64
    let before: Data
    let after: Data
}

struct SharedDefaultsState: Codable, Sendable {
    let acknowledgedEdit: UInt64
    let values: Data
    let removed: Set<String>
}

@MainActor
final class SharedDefaultsMirror {
    private let role: ProcessRole
    private let defaults: UserDefaults
    private let domainName: String
    private let reload: () -> Void
    private let send: (SharedChange) -> Void
    private var snapshot: [String: Any] = [:]
    private var observer: NotificationToken?
    private var pendingFlush: Task<Void, Never>?
    private var editRevision: UInt64 = 0
    private var unacknowledged: [(revision: UInt64, patch: DefaultsPatch)] = []

    init(
        role: ProcessRole, defaults: UserDefaults, domainName: String, reload: @escaping () -> Void,
        send: @escaping (SharedChange) -> Void
    ) {
        self.role = role
        self.defaults = defaults
        self.domainName = domainName
        self.reload = reload
        self.send = send
    }

    func start() {
        snapshot = defaults.persistentDomain(forName: domainName) ?? [:]
        let token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleFlush() }
        }
        observer = NotificationToken(token, center: .default)
    }

    func flush() {
        guard pendingFlush != nil else { return }
        pendingFlush?.cancel()
        pendingFlush = nil
        let current = defaults.persistentDomain(forName: domainName) ?? [:]
        let patch = DefaultsPatch(from: snapshot, to: current)
        snapshot = current
        guard !patch.keys.isEmpty else { return }
        if role == .main {
            publish(patch.keys)
        } else if let before = Self.encode(patch.before), let after = Self.encode(patch.after) {
            editRevision += 1
            unacknowledged.append((editRevision, patch))
            send(.defaultsEdit(SharedDefaultsEdit(revision: editRevision, before: before, after: after)))
        }
    }

    func apply(_ edit: SharedDefaultsEdit) {
        guard role == .main, let before = Self.decode(edit.before), let after = Self.decode(edit.after)
        else { return }
        flush()
        let patch = DefaultsPatch(from: before, to: after)
        let values = Dictionary(
            uniqueKeysWithValues: patch.keys.compactMap { key in
                patch.value(for: key, over: snapshot[key]).map { (key, $0) }
            })
        adopt(values, for: patch.keys)
        editRevision = edit.revision
        publish(patch.keys)
    }

    func apply(_ state: SharedDefaultsState) {
        guard role == .settings, var values = Self.decode(state.values) else { return }
        flush()
        unacknowledged.removeAll { $0.revision <= state.acknowledgedEdit }
        let keys = state.removed.union(values.keys)
        for (_, patch) in unacknowledged {
            for key in keys.intersection(patch.keys) {
                values[key] = patch.value(for: key, over: values[key])
            }
        }
        adopt(values, for: keys)
    }

    private func scheduleFlush() {
        guard pendingFlush == nil else { return }
        pendingFlush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func adopt(_ values: [String: Any], for keys: Set<String>) {
        for key in keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            snapshot[key] = values[key]
        }
        reload()
    }

    private func publish(_ keys: Set<String>) {
        let values = snapshot.filter { keys.contains($0.key) }
        guard let data = Self.encode(values) else { return }
        send(
            .defaultsState(
                SharedDefaultsState(
                    acknowledgedEdit: editRevision, values: data, removed: keys.subtracting(values.keys))))
    }

    private static func encode(_ values: [String: Any]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    private static func decode(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}

private struct DefaultsPatch {
    let keys: Set<String>
    let before: [String: Any]
    let after: [String: Any]

    init(from before: [String: Any], to after: [String: Any]) {
        let keys = Set(before.keys).union(after.keys).filter { !Self.equal(before[$0], after[$0]) }
        self.keys = keys
        self.before = before.filter { keys.contains($0.key) }
        self.after = after.filter { keys.contains($0.key) }
    }

    func value(for key: String, over current: Any?) -> Any? {
        Self.merge(before: before[key], after: after[key], current: current)
    }

    private static func merge(before: Any?, after: Any?, current: Any?) -> Any? {
        guard !equal(before, current),
            let previous = Self.dictionary(before), let proposed = Self.dictionary(after),
            var merged = Self.dictionary(current)
        else { return after }

        let patch = DefaultsPatch(from: previous, to: proposed)
        for key in patch.keys { merged[key] = patch.value(for: key, over: merged[key]) }
        return merged.isEmpty && after == nil ? nil : merged
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        guard let value else { return [:] }
        return value as? [String: Any]
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs else { return rhs == nil }
        guard let rhs else { return false }
        return (lhs as AnyObject).isEqual(rhs)
    }
}
