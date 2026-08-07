import Foundation

/// Turns Do Not Disturb on while engaged.
///
/// The only effect that needs one-time setup, because macOS exposes no way for a
/// third-party app to set Focus. The user creates two Shortcuts once; Mica runs them.
public final class DoNotDisturbEffect: PrivacyEffect {

    public nonisolated struct PriorState: Codable, Equatable, Sendable {
        public var wasEnabled: Bool
    }

    public let feature = Feature.doNotDisturb

    private let monitor: DoNotDisturbMonitor
    private let shortcutIDs: () -> (on: String?, off: String?)

    public init(monitor: DoNotDisturbMonitor, shortcutIDs: @escaping () -> (on: String?, off: String?)) {
        self.monitor = monitor
        self.shortcutIDs = shortcutIDs
    }

    public var unavailableReason: String? {
        guard ShortcutsRunner.isAvailable else {
            return "The Shortcuts command line tool isn't available on this Mac."
        }
        let ids = shortcutIDs()
        guard ids.on != nil, ids.off != nil else {
            return "Do Not Disturb needs a one-time setup. Open Settings → Features to finish it."
        }
        return nil
    }

    public func capturePriorState(options: EffectOptions) throws -> PriorState {
        PriorState(wasEnabled: monitor.isEnabled ?? false)
    }

    public func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws {
        // Releasing restores what was there before, which may well have been "on" if the
        // user had a Focus running already — in that case Mica must leave it alone.
        let target = desired ? true : (prior?.wasEnabled ?? false)
        guard monitor.isEnabled != target else { return }

        let ids = shortcutIDs()
        guard let uuid = target ? ids.on : ids.off else {
            throw EffectError.unavailable(feature, reason: "no shortcut configured")
        }

        // Off the main actor: this spawns a process and waits for it, and blocking the
        // main thread here would freeze the popover mid-engage.
        let succeeded = await Task.detached { ShortcutsRunner.run(uuid: uuid) }.value
        guard succeeded else {
            throw EffectError.failed(feature, reason: "the Do Not Disturb shortcut didn't run")
        }
        monitor.noteChangedByMica(to: target)
    }

    public func emergencyRestore(prior: PriorState) {
        guard !prior.wasEnabled, monitor.isEnabled != false else { return }
        guard let uuid = shortcutIDs().off else { return }
        // Contrary to the usual "no subprocesses in an emergency restore" rule, this one
        // is worth attempting: being left permanently silenced is the most user-visible
        // way this app can fail. The timeout is short so it can't stall shutdown.
        _ = ShortcutsRunner.run(uuid: uuid, timeout: 3)
    }
}
