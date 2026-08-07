import Foundation

/// Hides desktop icons and desktop widgets using the real macOS settings, so the live
/// wallpaper stays visible underneath rather than being covered over.
public final class DesktopItemsEffect: PrivacyEffect {

    public nonisolated struct PriorState: Codable, Equatable, Sendable {
        public var hideIcons: PrefValue<Bool>
        public var hideWidgets: PrefValue<Bool>
    }

    public let feature = Feature.hideDesktopItems

    public init() {}

    public var unavailableReason: String? { nil }

    public func capturePriorState(options: EffectOptions) throws -> PriorState {
        PriorState(
            hideIcons: WindowManagerPrefs.read(.hideDesktopIcons),
            hideWidgets: WindowManagerPrefs.read(.hideWidgets)
        )
    }

    public func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws {
        // Engaging means "true"; releasing means whatever was there before, which may
        // legitimately be *absent* rather than false.
        let targetIcons: PrefValue<Bool> = desired ? .present(true) : (prior?.hideIcons ?? .absent)
        let targetWidgets: PrefValue<Bool> = desired ? .present(true) : (prior?.hideWidgets ?? .absent)

        var changed = false
        if WindowManagerPrefs.read(.hideDesktopIcons) != targetIcons {
            WindowManagerPrefs.write(targetIcons, to: .hideDesktopIcons)
            changed = true
        }
        if WindowManagerPrefs.read(.hideWidgets) != targetWidgets {
            WindowManagerPrefs.write(targetWidgets, to: .hideWidgets)
            changed = true
        }
        guard changed else { return }

        WindowManagerPrefs.synchronize()
        WindowManagerPrefs.restartWindowManager()
    }

    public func emergencyRestore(prior: PriorState) {
        WindowManagerPrefs.write(prior.hideIcons, to: .hideDesktopIcons)
        WindowManagerPrefs.write(prior.hideWidgets, to: .hideWidgets)
        WindowManagerPrefs.synchronize()
        // Deliberately not restarting WindowManager here: this runs while the process is
        // being torn down, and spawning a child is exactly the kind of thing that won't
        // finish. The settings are written, so the desktop comes back either when
        // WindowManager next reads them or on the next login.
    }
}
