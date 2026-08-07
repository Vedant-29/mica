import AppKit

/// Hides other applications' windows.
///
/// Works at the application level via `NSRunningApplication.hide()`, which needs no
/// permission and is fully reversible. Notably this also works on Finder — the reason
/// other tools resort to closing Finder's windows is that the convenience API,
/// `NSWorkspace.hideOtherApplications()`, deliberately skips it, not that Finder can't
/// be hidden. Hiding is reversible; closing someone's Finder windows is not.
public final class WindowsEffect: PrivacyEffect {

    public nonisolated struct PriorState: Codable, Equatable, Sendable {
        /// Exactly the applications this effect hid, so restore un-hides only those.
        /// An app the user had already hidden is never in here, and so stays hidden.
        public var hiddenBundleIDs: [String]
    }

    public let feature = Feature.hideWindows

    public init() {}

    public var unavailableReason: String? { nil }

    public func capturePriorState(options: EffectOptions) throws -> PriorState {
        PriorState(hiddenBundleIDs: targets(options: options).compactMap(\.bundleIdentifier))
    }

    public func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws {
        guard let bundleIDs = prior?.hiddenBundleIDs else { return }

        for bundleID in bundleIDs {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                // `hide()` and `unhide()` report whether the *request* was dispatched,
                // not whether it took effect — on this machine hiding Finder succeeded
                // while returning false. So the return value is deliberately ignored;
                // `isHidden` below is the real check.
                guard app.isHidden != desired else { continue }
                _ = desired ? app.hide() : app.unhide()
            }
        }
    }

    public func emergencyRestore(prior: PriorState) {
        for bundleID in prior.hiddenBundleIDs {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where app.isHidden {
                _ = app.unhide()
            }
        }
    }

    /// The applications that would be hidden right now.
    private func targets(options: EffectOptions) -> [NSRunningApplication] {
        let me = NSRunningApplication.current.processIdentifier
        let exempt: String? = switch options.hideWindowsScope {
        case .all: nil
        case .exceptFrontmost: FrontmostTracker.shared.lastFrontmostBundleID
        }

        return NSWorkspace.shared.runningApplications.filter { app in
            // `.regular` only: accessory and background apps have no windows to hide, and
            // including them would pad the restore list with entries that mean nothing.
            guard app.activationPolicy == .regular else { return false }
            // Only what is currently visible, which is what makes restore exact.
            guard !app.isHidden else { return false }
            guard app.processIdentifier != me else { return false }
            if let exempt, app.bundleIdentifier == exempt { return false }
            return true
        }
    }
}
