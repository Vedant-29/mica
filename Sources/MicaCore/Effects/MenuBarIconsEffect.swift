import AppKit

/// Hides other applications' menu bar icons.
public final class MenuBarIconsEffect: PrivacyEffect {

    /// Process-local, like the wallpaper cover: the spacer is a status item Mica owns.
    public typealias PriorState = NoPriorState

    public let feature = Feature.hideMenuBarIcons

    private let spacer = MenuBarSpacerController()
    private let banner = ReminderBanner()

    public init() {
        // A collapse that gets undone would otherwise look like the feature silently
        // failing, and the fix — dragging the `‹` handle — isn't guessable.
        spacer.onCollapseAborted = { [weak self] in
            self?.banner.show(
                title: "Menu bar icons stayed visible",
                message: "The ‹ handle is to the right of Mica's icon. ⌘-drag it left of the icon, or Mica would hide itself too.",
                activateTitle: "OK"
            ) {}
        }
    }

    public var unavailableReason: String? { nil }

    /// Hands over Mica's own menu bar item, so the spacer can refuse to hide it.
    public func setOwnStatusItem(_ item: NSStatusItem?) {
        spacer.setOwnStatusItem(item)
    }

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
