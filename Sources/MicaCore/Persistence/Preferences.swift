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

        static let triggerScreenCapture = "trigger.screenCapture.enabled"
        static let triggerDisplayChange = "trigger.displayChange.enabled"
        static let triggerApps = "trigger.apps.enabled"
        static let triggerSchedule = "trigger.schedule.enabled"
        static let exclusionsEnabled = "exclusions.enabled"

        static let scheduleStart = "trigger.schedule.startMinutes"
        static let scheduleEnd = "trigger.schedule.endMinutes"

        static let dndShortcutOn = "feature.doNotDisturb.shortcutOnID"
        static let dndShortcutOff = "feature.doNotDisturb.shortcutOffID"

        static let hotkeyEnabled = "hotkeyEnabled"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Sensible starting point: the four effects that are instantly reversible and
        // need no setup. Do Not Disturb stays off until its one-time Shortcuts setup is
        // done, and Hide Menu Bar Icons until the user has positioned the indicator —
        // switching either on blind would just look broken.
        let storedFeatures = defaults.array(forKey: Key.enabledFeatures) as? [String]
        self.enabledFeatures = storedFeatures.map { stored in
            Set(stored.compactMap(Feature.init(rawValue:)))
        } ?? [.hideWindows, .hideDock, .hideWallpaper, .hideDesktopItems]

        self.mode = defaults.string(forKey: Key.mode).flatMap(AppMode.init(rawValue:)) ?? .off
        self.lastNonOffMode = defaults.string(forKey: Key.lastNonOffMode)
            .flatMap(AppMode.init(rawValue:)) ?? .auto
        self.hideWindowsScope = defaults.string(forKey: Key.hideWindowsScope)
            .flatMap(HideWindowsScope.init(rawValue:)) ?? .all
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)

        // `bool(forKey:)` returns false for a missing key, which is wrong for anything
        // that should default to on — hence the explicit presence check.
        self.triggerScreenCapture = defaults.boolIfPresent(Key.triggerScreenCapture) ?? true
        self.triggerDisplayChange = defaults.boolIfPresent(Key.triggerDisplayChange) ?? false
        self.triggerApps = defaults.boolIfPresent(Key.triggerApps) ?? true
        self.triggerSchedule = defaults.boolIfPresent(Key.triggerSchedule) ?? false
        self.exclusionsEnabled = defaults.boolIfPresent(Key.exclusionsEnabled) ?? true
        self.hotkeyEnabled = defaults.boolIfPresent(Key.hotkeyEnabled) ?? true

        self.scheduleStartMinutes = defaults.intIfPresent(Key.scheduleStart) ?? 9 * 60
        self.scheduleEndMinutes = defaults.intIfPresent(Key.scheduleEnd) ?? 17 * 60

        self.dndShortcutOnID = defaults.string(forKey: Key.dndShortcutOn)
        self.dndShortcutOffID = defaults.string(forKey: Key.dndShortcutOff)
    }

    // MARK: - Mode and features

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
        didSet { defaults.set(enabledFeatures.map(\.rawValue).sorted(), forKey: Key.enabledFeatures) }
    }

    public var hideWindowsScope: HideWindowsScope {
        didSet { defaults.set(hideWindowsScope.rawValue, forKey: Key.hideWindowsScope) }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    // MARK: - Triggers

    public var triggerScreenCapture: Bool {
        didSet { defaults.set(triggerScreenCapture, forKey: Key.triggerScreenCapture) }
    }
    public var triggerDisplayChange: Bool {
        didSet { defaults.set(triggerDisplayChange, forKey: Key.triggerDisplayChange) }
    }
    public var triggerApps: Bool {
        didSet { defaults.set(triggerApps, forKey: Key.triggerApps) }
    }
    public var triggerSchedule: Bool {
        didSet { defaults.set(triggerSchedule, forKey: Key.triggerSchedule) }
    }
    public var exclusionsEnabled: Bool {
        didSet { defaults.set(exclusionsEnabled, forKey: Key.exclusionsEnabled) }
    }

    public var scheduleStartMinutes: Int {
        didSet { defaults.set(scheduleStartMinutes, forKey: Key.scheduleStart) }
    }
    public var scheduleEndMinutes: Int {
        didSet { defaults.set(scheduleEndMinutes, forKey: Key.scheduleEnd) }
    }

    public var hotkeyEnabled: Bool {
        didSet { defaults.set(hotkeyEnabled, forKey: Key.hotkeyEnabled) }
    }

    // MARK: - Do Not Disturb

    public var dndShortcutOnID: String? {
        didSet { defaults.set(dndShortcutOnID, forKey: Key.dndShortcutOn) }
    }
    public var dndShortcutOffID: String? {
        didSet { defaults.set(dndShortcutOffID, forKey: Key.dndShortcutOff) }
    }

    // MARK: - Derived

    public var triggerToggles: TriggerToggles {
        TriggerToggles(
            screenCapture: triggerScreenCapture,
            displayChange: triggerDisplayChange,
            apps: triggerApps,
            schedule: triggerSchedule,
            exclusions: exclusionsEnabled
        )
    }

    public var scheduleWindow: ScheduleWindow? {
        triggerSchedule
            ? ScheduleWindow(startMinutes: scheduleStartMinutes, endMinutes: scheduleEndMinutes)
            : nil
    }

    public func isEnabled(_ feature: Feature) -> Bool { enabledFeatures.contains(feature) }

    public func setEnabled(_ enabled: Bool, for feature: Feature) {
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
    }
}

extension UserDefaults {
    /// Distinguishes "absent" from "present and false", which `bool(forKey:)` cannot.
    fileprivate func boolIfPresent(_ key: String) -> Bool? {
        object(forKey: key) == nil ? nil : bool(forKey: key)
    }

    fileprivate func intIfPresent(_ key: String) -> Int? {
        object(forKey: key) == nil ? nil : integer(forKey: key)
    }
}
