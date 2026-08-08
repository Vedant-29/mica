import AppKit
import KeyboardShortcuts
import MicaCore
import Observation

extension KeyboardShortcuts.Name {
    /// Matches the hint shown in the popover header.
    static let toggleMica = Self("toggleMica", default: .init(.s, modifiers: [.option, .command]))
}

/// Composition root: builds every effect, monitor and store once, and owns the wiring
/// between user intent and the system.
@Observable
@MainActor
final class AppEnvironment {

    let preferences: Preferences
    let coordinator: PrivacyCoordinator
    let engagement: EngagementController

    let triggerApps = AppListStore(filename: "TriggerApps.json")
    let excludedApps = AppListStore(filename: "ExcludedApps.json")
    /// Apps chosen for the two list-based Hide Active Windows scopes.
    let windowApps = AppListStore(filename: "WindowApps.json")

    @ObservationIgnored private let menuBarIcons = MenuBarIconsEffect()
    @ObservationIgnored private let doNotDisturbMonitor = DoNotDisturbMonitor()
    @ObservationIgnored private let signalTrap = SignalTrap()
    /// Exposed so Settings can explain when the built-in banner is standing in for
    /// system notifications.
    let notifier = ReminderNotifier()

    init(preferences: Preferences = .shared) {
        self.preferences = preferences

        let dndMonitor = doNotDisturbMonitor
        let effects: [Feature: any AnyPrivacyEffect] = [
            .hideDock: DockEffect(),
            .hideWindows: WindowsEffect(),
            .hideDesktopItems: DesktopItemsEffect(),
            .hideWallpaper: WallpaperEffect(),
            .hideMenuBarIcons: menuBarIcons,
            .doNotDisturb: DoNotDisturbEffect(monitor: dndMonitor) {
                (preferences.dndShortcutOnID, preferences.dndShortcutOffID)
            },
        ]

        let windowApps = self.windowApps
        let coordinator = PrivacyCoordinator(preferences: preferences, effects: effects) {
            EffectOptions(
                hideWindowsScope: preferences.hideWindowsScope,
                selectedWindowApps: windowApps.bundleIDs()
            )
        }
        self.coordinator = coordinator
        self.engagement = EngagementController(
            preferences: preferences,
            coordinator: coordinator,
            triggerApps: triggerApps,
            excludedApps: excludedApps,
            doNotDisturb: dndMonitor,
            notifier: notifier
        )
    }

    /// Ordering matters: recovery has to finish before anything is allowed to engage, or
    /// a stale snapshot could be overwritten by a fresh one before it's been acted on.
    func start() {
        CrashRecovery.runIfNeeded(effects: coordinator.effects)

        signalTrap.install { [weak self] in
            self?.coordinator.emergencyRestoreAll()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.emergencyRestoreAll() }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleMica) { [weak self] in
            guard let self, preferences.hotkeyEnabled else { return }
            engagement.userToggled()
        }

        // Must be watching before anything engages, or "All except frontmost" has
        // nothing to exempt.
        _ = FrontmostTracker.shared

        syncEnabledFeatures()
        engagement.start()
    }

    // MARK: - Intent

    func modeDidChange() {
        engagement.modeDidChange()
    }

    func enabledFeaturesDidChange() {
        syncEnabledFeatures()
        coordinator.enabledFeaturesDidChange()
    }

    func settingsDidChange() {
        engagement.settingsDidChange()
        coordinator.enabledFeaturesDidChange()
    }

    func terminate() {
        coordinator.emergencyRestoreAll()
        NSApp.terminate(nil)
    }

    /// The menu bar spacer exists whenever the feature is switched on, not only while
    /// engaged — otherwise there'd be no `‹` handle to drag into position beforehand.
    private func syncEnabledFeatures() {
        menuBarIcons.setInstalled(preferences.isEnabled(.hideMenuBarIcons))
    }
}
