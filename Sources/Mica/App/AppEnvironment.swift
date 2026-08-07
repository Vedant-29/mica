import AppKit
import KeyboardShortcuts
import MicaCore
import Observation

extension KeyboardShortcuts.Name {
    /// Matches the hint shown in the popover header.
    static let toggleMica = Self("toggleMica", default: .init(.s, modifiers: [.option, .command]))
}

/// Composition root: builds every effect and the coordinator once, and owns the wiring
/// between user intent (mode, hotkey, feature toggles) and the effects.
@Observable
@MainActor
final class AppEnvironment {

    let preferences: Preferences
    let coordinator: PrivacyCoordinator

    @ObservationIgnored private let menuBarIcons = MenuBarIconsEffect()
    @ObservationIgnored private let signalTrap = SignalTrap()

    init(preferences: Preferences = .shared) {
        self.preferences = preferences

        let effects: [Feature: any AnyPrivacyEffect] = [
            .hideDock: DockEffect(),
            .hideWindows: WindowsEffect(),
            .hideDesktopItems: DesktopItemsEffect(),
            .hideWallpaper: WallpaperEffect(),
            .hideMenuBarIcons: menuBarIcons,
        ]
        self.coordinator = PrivacyCoordinator(preferences: preferences, effects: effects)
    }

    /// Ordering matters: recovery has to finish before anything is allowed to engage,
    /// or a stale snapshot could be overwritten by a fresh one before it's been acted on.
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
            self?.toggleFromHotkey()
        }

        // The FrontmostTracker has to be watching before anything engages, or
        // "All except frontmost" has nothing to exempt.
        _ = FrontmostTracker.shared

        syncEnabledFeatures()
        syncEngagement()
    }

    // MARK: - Intent

    func modeDidChange() {
        syncEngagement()
    }

    func enabledFeaturesDidChange() {
        syncEnabledFeatures()
        coordinator.enabledFeaturesDidChange()
    }

    func toggleFromHotkey() {
        preferences.toggleFromHotkey()
        syncEngagement()
    }

    func terminate() {
        coordinator.emergencyRestoreAll()
        NSApp.terminate(nil)
    }

    // MARK: - Wiring

    private func syncEngagement() {
        // Auto is inert until the trigger monitors land; for now only an explicit On
        // engages anything.
        coordinator.setEngaged(preferences.mode == .on)
    }

    /// The menu bar spacer exists whenever the feature is switched on, not only while
    /// engaged — otherwise there'd be no `‹` handle to drag into position beforehand.
    private func syncEnabledFeatures() {
        menuBarIcons.setInstalled(preferences.isEnabled(.hideMenuBarIcons))
    }
}
