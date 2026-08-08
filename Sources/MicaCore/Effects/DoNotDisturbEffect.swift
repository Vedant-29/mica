import Foundation

/// Turns Do Not Disturb on while engaged, off when released.
///
/// macOS gives a third-party app no way to set Focus except by running a Shortcut, so
/// that is all this does: run the on-shortcut to engage, the off-shortcut to release.
///
/// It deliberately does not try to read the current Focus state. There is no reliable,
/// permission-free way to do that on macOS 26 (the old notifications are dead, the private
/// service is entitlement-gated, and the state file needs Full Disk Access), and the
/// feature doesn't need it: engage turns Focus on, release turns it off. The only
/// consequence is that if Do Not Disturb was already on before Mica engaged, releasing
/// turns it off — an acceptable, predictable trade for not depending on a broken API.
public final class DoNotDisturbEffect: PrivacyEffect {

    /// Empty: there is no prior state to restore, because release always simply turns
    /// Focus off. Kept as a type so the effect still fits the crash-safe snapshot, whose
    /// job here is just to run the off-shortcut on recovery.
    public typealias PriorState = NoPriorState

    public let feature = Feature.doNotDisturb

    private let shortcutIDs: () -> (on: String?, off: String?)

    public init(shortcutIDs: @escaping () -> (on: String?, off: String?)) {
        self.shortcutIDs = shortcutIDs
    }

    public var unavailableReason: String? {
        guard ShortcutsRunner.isAvailable else {
            return "The Shortcuts app isn't available on this Mac."
        }
        let ids = shortcutIDs()
        guard ids.on != nil, ids.off != nil else {
            return "Set up Do Not Disturb in Settings to use it."
        }
        return nil
    }

    public func capturePriorState(options: EffectOptions) throws -> PriorState { NoPriorState() }

    public func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws {
        let ids = shortcutIDs()
        guard let uuid = desired ? ids.on : ids.off else {
            throw EffectError.unavailable(feature, reason: "no shortcut configured")
        }
        // Off the main actor: this spawns a process and waits for it, and blocking the
        // main thread would freeze the popover mid-engage.
        let succeeded = await Task.detached { ShortcutsRunner.run(uuid: uuid) }.value
        guard succeeded else {
            throw EffectError.failed(feature, reason: "the Do Not Disturb shortcut didn't run")
        }
    }

    public func emergencyRestore(prior: PriorState) {
        // Being left silenced is the most user-visible way this app can fail, so this is
        // worth a subprocess despite the usual "no spawning during teardown" rule. The
        // short timeout keeps it from stalling shutdown.
        guard let uuid = shortcutIDs().off else { return }
        _ = ShortcutsRunner.run(uuid: uuid, timeout: 3)
    }
}
