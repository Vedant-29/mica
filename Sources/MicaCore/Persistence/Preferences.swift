import Foundation
import Observation

/// The single place `UserDefaults` is read or written.
///
/// Funnelling every key through one type keeps the storage format auditable (and
/// `defaults read com.vedant.mica` legible while debugging) rather than scattering
/// `@AppStorage` string literals across a dozen views.
@Observable
public final class Preferences {

    public static let shared = Preferences()

    @ObservationIgnored private let defaults: UserDefaults

    /// Keys are persisted strings — changing one silently discards that setting for
    /// anyone who already has it stored.
    private enum Key {
        static let mode = "mode"
        static let lastNonOffMode = "lastNonOffMode"
        static let enabledFeatures = "enabledFeatures"
        static let hideWindowsScope = "feature.hideWindows.scope"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Mica ships engaged-by-default on the four effects that are instantly
        // reversible and need no setup. Do Not Disturb is off until its one-time
        // Shortcuts setup is done, and Hide Menu Bar Icons is off until the user has
        // positioned the indicator — enabling either blind would look broken.
        let storedFeatures = defaults.array(forKey: Key.enabledFeatures) as? [String]
        self.enabledFeatures = storedFeatures.map { stored in
            Set(stored.compactMap(Feature.init(rawValue:)))
        } ?? [.hideWindows, .hideDock, .hideWallpaper, .hideDesktopItems]

        self.mode = defaults.string(forKey: Key.mode)
            .flatMap(AppMode.init(rawValue:)) ?? .off
        self.lastNonOffMode = defaults.string(forKey: Key.lastNonOffMode)
            .flatMap(AppMode.init(rawValue:)) ?? .auto
        self.hideWindowsScope = defaults.string(forKey: Key.hideWindowsScope)
            .flatMap(HideWindowsScope.init(rawValue:)) ?? .all
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    // MARK: - Stored settings

    public var mode: AppMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Key.mode)
            // Remembered so the hotkey can return you to Auto rather than dumping you
            // into Off, which would quietly disarm every trigger you configured.
            if mode != .off { lastNonOffMode = mode }
        }
    }

    public private(set) var lastNonOffMode: AppMode {
        didSet { defaults.set(lastNonOffMode.rawValue, forKey: Key.lastNonOffMode) }
    }

    public var enabledFeatures: Set<Feature> {
        didSet {
            defaults.set(enabledFeatures.map(\.rawValue).sorted(), forKey: Key.enabledFeatures)
        }
    }

    public var hideWindowsScope: HideWindowsScope {
        didSet { defaults.set(hideWindowsScope.rawValue, forKey: Key.hideWindowsScope) }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    // MARK: - Convenience

    public func isEnabled(_ feature: Feature) -> Bool {
        enabledFeatures.contains(feature)
    }

    public func setEnabled(_ enabled: Bool, for feature: Feature) {
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
    }

    /// What ⌥⌘S should do. Kept here rather than in the view so the hotkey handler and
    /// the popover cannot drift apart.
    public func toggleFromHotkey() {
        mode = (mode == .off) ? lastNonOffMode : .off
    }
}
