import Foundation

/// State one role changed, for the other to adopt from the storage both of them share.
enum SharedChange: Codable, Sendable {
    /// The changed values as a binary property list, so they land before cfprefsd delivers them.
    case defaults(values: Data, removed: [String])
    case domain(SharedDomain)
}

/// Shared state kept outside `UserDefaults`, re-read whole when the other role changes it.
enum SharedDomain: String, Codable, Sendable {
    case quicklinks
    case chatPresets
    case customQuickActions
    case launchAtLogin
}

/// Keeps two roles' copies of shared state in step: a change says what to re-read, never how.
@MainActor
final class SharedStateMirror {
    struct Domain {
        let observe: () -> Void
        let reload: () -> Void
    }

    private let defaults = UserDefaults.standard
    private let domainName = Bundle.main.bundleIdentifier ?? ""
    private let send: (SharedChange) -> Void
    private let reloadDefaults: () -> Void
    private let domains: [SharedDomain: Domain]
    private var snapshot: [String: Any] = [:]
    private var defaultsObserver: NotificationToken?
    private var pendingDefaults: Task<Void, Never>?
    /// Bumped before a peer's change is re-read, so the stale observer it trips stays quiet.
    private var generations: [SharedDomain: Int] = [:]

    init(
        domains: [SharedDomain: Domain], reloadDefaults: @escaping () -> Void,
        send: @escaping (SharedChange) -> Void
    ) {
        self.domains = domains
        self.reloadDefaults = reloadDefaults
        self.send = send
    }

    func start() {
        snapshot = defaults.persistentDomain(forName: domainName) ?? [:]
        let token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDefaults() }
        }
        defaultsObserver = NotificationToken(token, center: .default)
        for domain in domains.keys { watch(domain) }
    }

    func apply(_ change: SharedChange) {
        switch change {
        case .defaults(let data, let removed):
            let values =
                (try? PropertyListSerialization.propertyList(from: data, format: nil))
                as? [String: Any] ?? [:]
            for (key, value) in values {
                defaults.set(value, forKey: key)
                snapshot[key] = value
            }
            for key in removed {
                defaults.removeObject(forKey: key)
                snapshot[key] = nil
            }
            reloadDefaults()
        case .domain(let domain):
            generations[domain, default: 0] += 1
            domains[domain]?.reload()
            watch(domain)
        }
    }

    /// Sends what is still waiting out its debounce, so it lands ahead of whatever comes next.
    func flush() {
        guard pendingDefaults != nil else { return }
        pendingDefaults?.cancel()
        sendDefaults()
    }

    private func watch(_ domain: SharedDomain) {
        guard let entry = domains[domain] else { return }
        let generation = generations[domain, default: 0]
        withObservationTracking(entry.observe) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generations[domain, default: 0] == generation else { return }
                watch(domain)
                send(.domain(domain))
            }
        }
    }

    /// One send per burst: a pane edit can write several keys in a row.
    private func scheduleDefaults() {
        guard pendingDefaults == nil else { return }
        pendingDefaults = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.sendDefaults()
        }
    }

    private func sendDefaults() {
        pendingDefaults = nil
        let current = defaults.persistentDomain(forName: domainName) ?? [:]
        let changed = current.filter { key, value in
            !((snapshot[key] as AnyObject?)?.isEqual(value) ?? false)
        }
        let removed = snapshot.keys.filter { current[$0] == nil }
        snapshot = current
        guard !changed.isEmpty || !removed.isEmpty,
            let data = try? PropertyListSerialization.data(
                fromPropertyList: changed, format: .binary, options: 0)
        else { return }
        send(.defaults(values: data, removed: removed))
    }
}
