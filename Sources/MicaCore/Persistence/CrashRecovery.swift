import AppKit

/// Restores the system after Mica was killed while engaged.
public enum CrashRecovery {

    public struct Outcome: Sendable {
        public var restored: [Feature]
        public var skipped: [Feature]
    }

    /// Runs at launch, before any monitor is allowed to engage anything.
    ///
    /// A snapshot on disk means a previous run changed the system and never got to put it
    /// back. The interesting case is telling *how* it died, because that changes what is
    /// safe to restore.
    @discardableResult
    public static func runIfNeeded(
        effects: [Feature: any AnyPrivacyEffect],
        store: SnapshotStore = .shared
    ) -> Outcome? {
        guard let snapshot = store.read() else { return nil }

        // Another copy of Mica is already running and owns this snapshot; restoring
        // would tear down the privacy state it is actively maintaining.
        if snapshot.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           isRunning(pid: snapshot.processIdentifier) {
            Log.recovery.notice("snapshot belongs to a live Mica (pid \(snapshot.processIdentifier)); leaving it alone")
            return nil
        }

        // Hidden-application state does not survive a restart — macOS starts everything
        // visible. Replaying a window-hiding snapshot across a reboot could therefore
        // only ever unhide something the *user* hid themselves after logging back in.
        let rebooted = snapshot.bootSessionUUID != BootSession.current
        if rebooted {
            Log.recovery.notice("snapshot predates the current boot; skipping window restore")
        }

        var restored: [Feature] = []
        var skipped: [Feature] = []

        // Reverse of engage order, so windows come back before the desktop is uncovered.
        for feature in Feature.disengageOrder {
            guard let payload = snapshot.effects[feature.rawValue] else { continue }
            guard let effect = effects[feature] else { continue }

            if rebooted && feature == .hideWindows {
                skipped.append(feature)
                continue
            }

            effect.emergencyRestore(encodedPrior: payload)
            restored.append(feature)
        }

        store.delete()
        Log.recovery.notice("restored \(restored.count) effect(s) after an unexpected quit")

        return Outcome(restored: restored, skipped: skipped)
    }

    private static func isRunning(pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.bundleIdentifier == Bundle.main.bundleIdentifier && !app.isTerminated
    }
}
