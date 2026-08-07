import AppKit

/// Covers the wallpaper on every display.
public final class WallpaperEffect: PrivacyEffect {

    /// Nothing to restore: the cover is a set of windows this process owns, so if Mica
    /// dies they go with it. Recording state for it would only add noise to the crash
    /// snapshot that the pre-mutation write has to flush before anything else can happen.
    public typealias PriorState = NoPriorState

    public let feature = Feature.hideWallpaper

    private let controller = WallpaperCoverController()

    public init() {}

    public var unavailableReason: String? { nil }

    public func capturePriorState(options: EffectOptions) throws -> PriorState { NoPriorState() }

    public func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws {
        guard desired != controller.isShowing else { return }
        if desired {
            controller.show()
        } else {
            controller.hide()
        }
    }

    public func emergencyRestore(prior: PriorState) {
        controller.hide()
    }
}
