import AppKit
import UserNotifications

/// Reminders for trigger apps set to "Remind me".
///
/// Prefers real system notifications, but falls back to drawing its own banner. That
/// fallback is not defensive padding — it is the expected path on a personally-built app:
/// macOS refuses `UNUserNotificationCenter` authorization to anything that fails Gatekeeper
/// assessment, and only a notarized Developer ID signature passes. Without the fallback,
/// the Remind-me trigger would appear to work and never do anything.
public final class ReminderNotifier: NSObject, UNUserNotificationCenterDelegate {

    private nonisolated static let categoryID = "MICA_REMINDER"
    private nonisolated static let activateActionID = "MICA_ACTIVATE"

    /// Invoked when the user chooses Activate.
    public var onActivate: (() -> Void)?

    /// Whether system notifications are usable. Surfaced so Settings can explain the
    /// fallback rather than leaving the user wondering.
    public private(set) var systemNotificationsAvailable = false

    /// Apps already reminded about this run, so relaunching Slack five times doesn't
    /// produce five reminders.
    private var remindedBundleIDs: Set<String> = []

    private let banner = ReminderBanner()

    public override init() { super.init() }

    public func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let activate = UNNotificationAction(
            identifier: Self.activateActionID,
            title: "Activate",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID,
                actions: [activate],
                intentIdentifiers: [],
                options: []
            )
        ])

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.systemNotificationsAvailable = granted && error == nil
                    if let error {
                        Log.monitors.notice(
                            "system notifications unavailable (\(error.localizedDescription, privacy: .public)); using the built-in reminder banner"
                        )
                    }
                }
            }
        }
    }

    public func remind(appName: String, bundleID: String) {
        guard !remindedBundleIDs.contains(bundleID) else { return }
        remindedBundleIDs.insert(bundleID)

        guard systemNotificationsAvailable else {
            banner.show(
                title: "\(appName) is running",
                message: "Would you like to turn Mica on?",
                activateTitle: "Activate"
            ) { [weak self] in
                self?.onActivate?()
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(appName) is running"
        content.body = "Would you like to turn Mica on?"
        content.categoryIdentifier = Self.categoryID
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: bundleID, content: content, trigger: nil)
        )
    }

    /// Lets an app be reminded about again once it has quit.
    public func forget(bundleIDs: Set<String>) {
        remindedBundleIDs.subtract(bundleIDs)
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isActivate = response.actionIdentifier == Self.activateActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        if isActivate {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.onActivate?() }
            }
        }
        completionHandler()
    }

    /// Mica has no windows, so without this the notification would be suppressed
    /// whenever it happened to be the frontmost process.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
