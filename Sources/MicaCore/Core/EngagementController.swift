import AppKit
import Observation

/// Wires the monitors to the engine to the coordinator.
///
/// Everything that observes the world lives here; everything that decides lives in
/// `EngagementEngine`, which is a pure function and therefore testable on its own.
@Observable
public final class EngagementController {

    public private(set) var decision = EngagementDecision(
        shouldEngage: false, reason: .modeOff, isManual: true
    )

    /// Name of whatever is capturing the screen, when it could be identified.
    public private(set) var capturerName: String?


    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let coordinator: PrivacyCoordinator
    @ObservationIgnored public let triggerApps: AppListStore
    @ObservationIgnored public let excludedApps: AppListStore
    @ObservationIgnored private let notifier: ReminderNotifier

    @ObservationIgnored private var screenCapture: ScreenCaptureMonitor?
    @ObservationIgnored private var display: DisplayMonitor?
    @ObservationIgnored private var runningApps: RunningAppsMonitor?
    @ObservationIgnored private var schedule: ScheduleMonitor?

    @ObservationIgnored private var manualOverride: ManualOverride?
    @ObservationIgnored private var releaseDebouncer: EdgeDebouncer?

    /// Held disengaged until the monitors have completed their first scan, so launching
    /// doesn't produce a visible engage-then-release flap.
    @ObservationIgnored private var isStarted = false

    public init(
        preferences: Preferences,
        coordinator: PrivacyCoordinator,
        triggerApps: AppListStore,
        excludedApps: AppListStore,
        notifier: ReminderNotifier
    ) {
        self.preferences = preferences
        self.coordinator = coordinator
        self.triggerApps = triggerApps
        self.excludedApps = excludedApps
        self.notifier = notifier
    }

    // MARK: - Lifecycle

    public func start() {
        // Engage instantly; release only after things have settled. Capture signals flap
        // hard while a share tears down, and thrashing six effects on a 50 ms blip both
        // looks broken and risks leaving state half-applied.
        releaseDebouncer = EdgeDebouncer(risingDelay: 0, fallingDelay: 1.5) { [weak self] engaged in
            self?.coordinator.setEngaged(engaged)
        }

        let screenCapture = ScreenCaptureMonitor { [weak self] _ in self?.evaluate() }
        screenCapture.start()
        self.screenCapture = screenCapture

        let display = DisplayMonitor { [weak self] _ in self?.evaluate() }
        display.start()
        self.display = display

        let runningApps = RunningAppsMonitor { [weak self] running in
            self?.handleRunningAppsChanged(running)
        }
        runningApps.start()
        self.runningApps = runningApps

        let schedule = ScheduleMonitor { [weak self] _ in self?.evaluate() }
        schedule.window = preferences.scheduleWindow
        schedule.start()
        self.schedule = schedule

        notifier.onActivate = { [weak self] in self?.activateFromReminder() }
        notifier.start()

        isStarted = true

        // A positive statement at startup, so "nothing in the log" can be distinguished
        // from "the monitors never came up" — the rest of the logging here is
        // change-driven and stays silent on an idle machine.
        Log.monitors.notice("""
            monitors started — capture detection \
            \(ScreenCaptureMonitor.isSupported ? "available" : "UNAVAILABLE", privacy: .public), \
            displays \(NSScreen.screens.count, privacy: .public), \
            trigger apps \(self.triggerApps.entries.count, privacy: .public), \
            excluded apps \(self.excludedApps.entries.count, privacy: .public)
            """)

        evaluate(immediate: true)
    }

    public func stop() {
        screenCapture?.stop()
        display?.stop()
        runningApps?.stop()
        schedule?.stop()
    }

    // MARK: - User intent

    /// ⌥⌘S, and the Activate button on a reminder.
    public func userToggled() {
        switch preferences.mode {
        case .on:
            preferences.mode = .off
        case .off:
            preferences.mode = preferences.lastNonOffMode
        case .auto:
            // In Auto, flip what the user is currently seeing without abandoning the
            // triggers they configured. A `forceOff` expires on its own once whatever
            // caused the engagement goes away.
            manualOverride = ManualOverride(
                kind: decision.shouldEngage ? .forceOff : .forceOn,
                firingWhenCreated: EngagementEngine.firingTriggers(currentInputs())
            )
        }
        evaluate(immediate: true)
    }

    public func modeDidChange() {
        // A deliberate mode change supersedes any override.
        manualOverride = nil
        evaluate(immediate: true)
    }

    public func settingsDidChange() {
        schedule?.window = preferences.scheduleWindow
        schedule?.refresh()
        evaluate()
    }

    private func activateFromReminder() {
        switch preferences.mode {
        case .on: break
        case .off: preferences.mode = .on
        case .auto:
            manualOverride = ManualOverride(kind: .forceOn, firingWhenCreated: [])
        }
        evaluate(immediate: true)
    }

    // MARK: - Evaluation

    private func handleRunningAppsChanged(_ running: Set<String>) {
        // Let an app be reminded about again next time it launches.
        notifier.forget(bundleIDs: triggerApps.bundleIDs(action: .remind).subtracting(running))

        for entry in triggerApps.entries where entry.action == .remind {
            guard running.contains(entry.bundleID) else { continue }
            guard preferences.mode == .auto, !decision.shouldEngage else { continue }
            // Don't nag while an excluded app is running — that's the user saying "not
            // during this".
            guard currentInputs().runningExcludedApps.isEmpty else { continue }
            notifier.remind(appName: entry.displayName, bundleID: entry.bundleID)
        }

        evaluate()
    }

    private func currentInputs() -> EngagementInputs {
        let running = runningApps?.runningBundleIDs ?? []

        // Only Activate-mode apps can engage anything; Remind-me apps exist purely to
        // produce a notification.
        let activeTriggers = triggerApps.entries
            .filter { $0.action == .activate && running.contains($0.bundleID) }
            .map(\.displayName)

        let excluded = excludedApps.entries
            .filter { running.contains($0.bundleID) }
            .map(\.displayName)

        return EngagementInputs(
            mode: preferences.mode,
            manualOverride: manualOverride,
            screenIsCaptured: screenCapture?.isCaptured ?? false,
            displayIsMirroredOrExtended: display?.isMirroredOrExtended ?? false,
            activeTriggerApps: Set(activeTriggers),
            scheduleIsActive: schedule?.isActive ?? false,
            runningExcludedApps: Set(excluded),
            toggles: preferences.triggerToggles
        )
    }

    private func evaluate(immediate: Bool = false) {
        guard isStarted else { return }

        var inputs = currentInputs()

        // Expire a spent override before deciding, so the next share re-engages by itself.
        if let override = manualOverride,
           EngagementEngine.overrideHasExpired(override, firing: EngagementEngine.firingTriggers(inputs)) {
            manualOverride = nil
            inputs.manualOverride = nil
        }

        let decision = EngagementEngine.decide(inputs)
        self.decision = decision
        capturerName = screenCapture?.capturerName

        // Direct user input is never made to wait.
        releaseDebouncer?.set(decision.shouldEngage, immediate: immediate || decision.isManual)
    }
}
