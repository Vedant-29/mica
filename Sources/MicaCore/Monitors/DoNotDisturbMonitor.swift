import Foundation

/// Tracks whether Do Not Disturb is currently on.
///
/// Reading the Do Not Disturb database directly would need Full Disk Access, which is a
/// System Settings toggle the user has to find rather than a prompt Mica can raise. These
/// distributed notifications need no permission at all. The trade-off is that they report
/// *changes*, not the state at launch, so the value here starts as "unknown" and becomes
/// authoritative after the first change — good enough, because it's only used to avoid
/// switching Do Not Disturb off for a user who had it on themselves.
public final class DoNotDisturbMonitor {

    /// Nil until the first observed change; treated as "was off" when engaging, which is
    /// the safe assumption — worst case Mica turns off a Focus the user turned on, once,
    /// rather than leaving them silenced indefinitely.
    public private(set) var isEnabled: Bool?

    private var observers: [any NSObjectProtocol] = []

    public init() {}

    public func start() {
        let center = DistributedNotificationCenter.default()

        observers.append(center.addObserver(
            forName: Notification.Name("_NSDoNotDisturbEnabledNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isEnabled = true }
        })

        observers.append(center.addObserver(
            forName: Notification.Name("_NSDoNotDisturbDisabledNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isEnabled = false }
        })
    }

    public func stop() {
        let center = DistributedNotificationCenter.default()
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    /// Records what Mica itself just did, so state stays accurate between notifications.
    public func noteChangedByMica(to enabled: Bool) {
        isEnabled = enabled
    }
}
