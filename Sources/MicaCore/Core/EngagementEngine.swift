import Foundation

/// Which kinds of trigger are currently firing. Used both to pick a reason to show the
/// user and to give a manual override something to expire against.
public nonisolated enum TriggerKind: String, Hashable, Sendable, CaseIterable {
    case screenCapture
    case displayChange
    case app
    case schedule
}

/// A deliberate, temporary departure from what the triggers say — the ⌥⌘S "panic button"
/// while in Auto.
public nonisolated struct ManualOverride: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case forceOn
        case forceOff
    }

    public var kind: Kind

    /// The triggers that were firing when the override was made.
    ///
    /// A `forceOff` expires once all of these clear. That's what makes "reveal my desktop
    /// for a second mid-call" safe: when the call ends the override evaporates, so the
    /// *next* share re-engages automatically. Without it, one press would silently
    /// disarm Mica forever and the user would never know they'd stopped being protected.
    public var firingWhenCreated: Set<TriggerKind>

    public init(kind: Kind, firingWhenCreated: Set<TriggerKind>) {
        self.kind = kind
        self.firingWhenCreated = firingWhenCreated
    }
}

/// Master on/off switches for each trigger, from Settings.
public nonisolated struct TriggerToggles: Equatable, Sendable {
    public var screenCapture: Bool
    public var displayChange: Bool
    public var apps: Bool
    public var schedule: Bool
    public var exclusions: Bool

    public init(
        screenCapture: Bool = true,
        displayChange: Bool = false,
        apps: Bool = true,
        schedule: Bool = false,
        exclusions: Bool = true
    ) {
        self.screenCapture = screenCapture
        self.displayChange = displayChange
        self.apps = apps
        self.schedule = schedule
        self.exclusions = exclusions
    }
}

/// Every raw signal the decision depends on. Making this one `Equatable` value means the
/// engine is a pure function of it, and the whole precedence table is unit-testable
/// without a Mac, a screen share, or a running app.
public nonisolated struct EngagementInputs: Equatable, Sendable {
    public var mode: AppMode
    public var manualOverride: ManualOverride?
    public var screenIsCaptured: Bool
    public var displayIsMirroredOrExtended: Bool
    /// Trigger apps that are running *and* set to Activate. Remind-me apps never appear
    /// here — they only ever produce a notification.
    public var activeTriggerApps: Set<String>
    public var scheduleIsActive: Bool
    public var runningExcludedApps: Set<String>
    public var toggles: TriggerToggles

    public init(
        mode: AppMode = .off,
        manualOverride: ManualOverride? = nil,
        screenIsCaptured: Bool = false,
        displayIsMirroredOrExtended: Bool = false,
        activeTriggerApps: Set<String> = [],
        scheduleIsActive: Bool = false,
        runningExcludedApps: Set<String> = [],
        toggles: TriggerToggles = TriggerToggles()
    ) {
        self.mode = mode
        self.manualOverride = manualOverride
        self.screenIsCaptured = screenIsCaptured
        self.displayIsMirroredOrExtended = displayIsMirroredOrExtended
        self.activeTriggerApps = activeTriggerApps
        self.scheduleIsActive = scheduleIsActive
        self.runningExcludedApps = runningExcludedApps
        self.toggles = toggles
    }
}

public nonisolated enum EngagementReason: Equatable, Sendable {
    case modeOn
    case modeOff
    case manualOverride
    case screenCaptured
    case displayChanged
    case triggerApp(String)
    case schedule
    case noTrigger
    case blockedByExcludedApp(String)

    /// One line for the popover, so the user can always tell *why* Mica is doing what
    /// it's doing rather than guessing.
    public var summary: String {
        switch self {
        case .modeOn: "On"
        case .modeOff: "Off"
        case .manualOverride: "Overridden manually"
        case .screenCaptured: "Your screen is being shared or recorded"
        case .displayChanged: "A display is mirrored or extended"
        case .triggerApp(let name): "\(name) is running"
        case .schedule: "Within the scheduled window"
        case .noTrigger: "Waiting for a trigger"
        case .blockedByExcludedApp(let name): "Paused, \(name) is excluded"
        }
    }
}

public nonisolated struct EngagementDecision: Equatable, Sendable {
    public var shouldEngage: Bool
    public var reason: EngagementReason
    /// Direct user intent, which bypasses the release delay and the minimum dwell.
    /// Making someone wait after they pressed a key feels broken.
    public var isManual: Bool
}

/// Turns the raw signals into a single decision. Pure, with no side effects and no
/// dependency on AppKit — which is the point.
public nonisolated enum EngagementEngine {

    /// Triggers currently firing, respecting each one's master switch.
    public static func firingTriggers(_ inputs: EngagementInputs) -> Set<TriggerKind> {
        var firing: Set<TriggerKind> = []
        if inputs.toggles.screenCapture && inputs.screenIsCaptured { firing.insert(.screenCapture) }
        if inputs.toggles.displayChange && inputs.displayIsMirroredOrExtended { firing.insert(.displayChange) }
        if inputs.toggles.apps && !inputs.activeTriggerApps.isEmpty { firing.insert(.app) }
        if inputs.toggles.schedule && inputs.scheduleIsActive { firing.insert(.schedule) }
        return firing
    }

    public static func decide(_ inputs: EngagementInputs) -> EngagementDecision {
        switch inputs.mode {
        case .off:
            return EngagementDecision(shouldEngage: false, reason: .modeOff, isManual: true)

        case .on:
            // Explicit intent wins over everything, exclusions included. Silently
            // refusing a direct command is the fastest way to make a privacy tool feel
            // broken; the UI says it's overriding instead.
            return EngagementDecision(shouldEngage: true, reason: .modeOn, isManual: true)

        case .auto:
            let firing = firingTriggers(inputs)

            if let override = inputs.manualOverride {
                return EngagementDecision(
                    shouldEngage: override.kind == .forceOn,
                    reason: .manualOverride,
                    isManual: true
                )
            }

            // Exclusion only means something when a trigger is actually firing — with
            // nothing to block, reporting "blocked" would be a lie.
            if inputs.toggles.exclusions, !firing.isEmpty,
               let blocker = inputs.runningExcludedApps.sorted().first {
                return EngagementDecision(
                    shouldEngage: false,
                    reason: .blockedByExcludedApp(blocker),
                    isManual: false
                )
            }

            guard !firing.isEmpty else {
                return EngagementDecision(shouldEngage: false, reason: .noTrigger, isManual: false)
            }

            return EngagementDecision(
                shouldEngage: true,
                reason: reason(for: firing, inputs: inputs),
                isManual: false
            )
        }
    }

    /// Priority affects only which explanation is shown; any firing trigger engages.
    private static func reason(for firing: Set<TriggerKind>, inputs: EngagementInputs) -> EngagementReason {
        if firing.contains(.screenCapture) { return .screenCaptured }
        if firing.contains(.displayChange) { return .displayChanged }
        if firing.contains(.app), let app = inputs.activeTriggerApps.sorted().first {
            return .triggerApp(app)
        }
        return .schedule
    }

    /// Whether a `forceOff` has outlived what it was reacting to.
    public static func overrideHasExpired(_ override: ManualOverride, firing: Set<TriggerKind>) -> Bool {
        guard override.kind == .forceOff else { return false }
        // Nothing it was created against is still firing.
        return firing.isDisjoint(with: override.firingWhenCreated)
    }
}
