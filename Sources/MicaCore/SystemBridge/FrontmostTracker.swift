import AppKit

/// Remembers the last application that was frontmost other than Mica itself.
///
/// `NSWorkspace.frontmostApplication` can't answer this at the moment it's needed:
/// engaging from the popover requires activating Mica first, so by the time the effect
/// runs, "frontmost" is Mica — and "All except frontmost" would hide the very window the
/// user was looking at. Watching activations continuously means the answer is already
/// known before any of that happens.
public final class FrontmostTracker {

    public static let shared = FrontmostTracker()

    public private(set) var lastFrontmostBundleID: String?

    private var observer: (any NSObjectProtocol)?

    private init() {
        record(NSWorkspace.shared.frontmostApplication)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.record(app) }
        }
    }

    // No `deinit`: this is a process-lifetime singleton, so it is never deallocated and
    // the observer never needs removing. (A nonisolated deinit couldn't touch the
    // main-actor stored property anyway.)

    private func record(_ app: NSRunningApplication?) {
        guard let app,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              // Accessory apps have no windows to be "in front of", so treating one as
              // the frontmost app would exempt something that was never visible.
              app.activationPolicy == .regular
        else { return }
        lastFrontmostBundleID = app.bundleIdentifier
    }
}
