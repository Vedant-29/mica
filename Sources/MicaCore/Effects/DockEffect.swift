import Foundation

public final class DockEffect: PrivacyEffect {

    public nonisolated struct PriorState: Codable, Equatable, Sendable {
        public var autoHideWasEnabled: Bool
    }

    public let feature = Feature.hideDock

    public init() {}

    public var unavailableReason: String? {
        CoreDockBridge.isAvailable
            ? nil
            : "This version of macOS no longer exposes the Dock's auto-hide setting."
    }

    public func capturePriorState(options: EffectOptions) throws -> PriorState {
        guard let enabled = CoreDockBridge.autoHideEnabled() else {
            throw EffectError.unavailable(feature, reason: "could not read the Dock's auto-hide setting")
        }
        return PriorState(autoHideWasEnabled: enabled)
    }

    public func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws {
        let target = desired ? true : (prior?.autoHideWasEnabled ?? false)

        guard let current = CoreDockBridge.autoHideEnabled() else {
            throw EffectError.unavailable(feature, reason: "could not read the Dock's auto-hide setting")
        }
        guard current != target else { return }

        guard CoreDockBridge.setAutoHideEnabled(target) else {
            throw EffectError.failed(feature, reason: "could not change the Dock's auto-hide setting")
        }
    }

    public func emergencyRestore(prior: PriorState) {
        CoreDockBridge.setAutoHideEnabled(prior.autoHideWasEnabled)
    }
}
