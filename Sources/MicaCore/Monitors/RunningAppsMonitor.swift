import AppKit

/// Tracks which of a watched set of applications are running.
public final class RunningAppsMonitor {

    public private(set) var runningBundleIDs: Set<String> = []

    private let onChange: (Set<String>) -> Void
    private var observers: [any NSObjectProtocol] = []
    private var pending: DispatchWorkItem?

    public init(onChange: @escaping (Set<String>) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        // NSWorkspace has its own notification centre; observing the default one is the
        // single most common way to get nothing at all here.
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        refresh()
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        pending?.cancel()
        pending = nil
    }

    /// Launching an app produces a burst of notifications, and a bundle identifier isn't
    /// reliably populated on the very first one, so settle briefly before reading.
    private func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    public func refresh() {
        let current = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard current != runningBundleIDs else { return }
        runningBundleIDs = current
        onChange(current)
    }
}
