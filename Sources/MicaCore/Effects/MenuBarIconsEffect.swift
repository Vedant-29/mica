import AppKit

/// Hides other applications' menu bar icons.
public final class MenuBarIconsEffect: PrivacyEffect {

    /// Process-local, like the wallpaper cover: the spacer is a status item Mica owns.
    public typealias PriorState = NoPriorState

    public let feature = Feature.hideMenuBarIcons

    private let spacer = MenuBarSpacerController()

    public init() {}

    public var unavailableReason: String? { nil }

    /// Creates or removes the `‹` handle. Driven by the feature being switched on rather
    /// than by engagement, so the user can position it before it's ever needed.
    public func setInstalled(_ installed: Bool) {
        spacer.setInstalled(installed)
    }

    public func capturePriorState(options: EffectOptions) throws -> PriorState { NoPriorState() }

    public func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws {
        spacer.setCollapsed(desired)
    }

    public func emergencyRestore(prior: PriorState) {
        spacer.setCollapsed(false)
    }
}
