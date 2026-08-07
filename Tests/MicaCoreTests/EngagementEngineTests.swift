import Testing

@testable import MicaCore

@Suite("Engagement precedence")
struct EngagementEngineTests {

    @Test("Off never engages, whatever is firing")
    func offAlwaysWins() {
        let decision = EngagementEngine.decide(EngagementInputs(
            mode: .off,
            screenIsCaptured: true,
            displayIsMirroredOrExtended: true,
            scheduleIsActive: true
        ))
        #expect(decision.shouldEngage == false)
        #expect(decision.reason == .modeOff)
    }

    @Test("On always engages, even with no trigger")
    func onAlwaysEngages() {
        let decision = EngagementEngine.decide(EngagementInputs(mode: .on))
        #expect(decision.shouldEngage)
        #expect(decision.reason == .modeOn)
    }

    /// Silently refusing an explicit command is the fastest way to make a privacy tool
    /// feel broken, so exclusion is an Auto-mode gate only.
    @Test("An excluded app does not block an explicit On")
    func exclusionsDoNotBlockManualOn() {
        let decision = EngagementEngine.decide(EngagementInputs(
            mode: .on,
            screenIsCaptured: true,
            runningExcludedApps: ["Slack"]
        ))
        #expect(decision.shouldEngage)
    }

    @Test("An excluded app blocks Auto while a trigger is firing")
    func exclusionsBlockAuto() {
        let decision = EngagementEngine.decide(EngagementInputs(
            mode: .auto,
            screenIsCaptured: true,
            runningExcludedApps: ["Slack"]
        ))
        #expect(decision.shouldEngage == false)
        #expect(decision.reason == .blockedByExcludedApp("Slack"))
    }

    /// With nothing firing there is nothing to block, and claiming otherwise would be a
    /// lie in the status line.
    @Test("An excluded app reports nothing when no trigger is firing")
    func exclusionsAreSilentWithoutTriggers() {
        let decision = EngagementEngine.decide(EngagementInputs(
            mode: .auto,
            runningExcludedApps: ["Slack"]
        ))
        #expect(decision.shouldEngage == false)
        #expect(decision.reason == .noTrigger)
    }

    @Test("Auto engages on screen capture")
    func autoEngagesOnCapture() {
        let decision = EngagementEngine.decide(EngagementInputs(mode: .auto, screenIsCaptured: true))
        #expect(decision.shouldEngage)
        #expect(decision.reason == .screenCaptured)
        #expect(decision.isManual == false)
    }

    @Test("A trigger with its master switch off does not fire")
    func disabledTriggersAreInert() {
        let decision = EngagementEngine.decide(EngagementInputs(
            mode: .auto,
            screenIsCaptured: true,
            toggles: TriggerToggles(screenCapture: false)
        ))
        #expect(decision.shouldEngage == false)
    }

    @Test("Remind-me apps never appear as triggers")
    func remindAppsDoNotEngage() {
        // The controller only ever puts Activate-mode apps in `activeTriggerApps`, so an
        // empty set with apps running is the correct representation of remind-only.
        let decision = EngagementEngine.decide(EngagementInputs(mode: .auto, activeTriggerApps: []))
        #expect(decision.shouldEngage == false)
    }

    @Test("A manual override wins over the triggers in Auto")
    func overrideWinsInAuto() {
        let forceOff = EngagementEngine.decide(EngagementInputs(
            mode: .auto,
            manualOverride: ManualOverride(kind: .forceOff, firingWhenCreated: [.screenCapture]),
            screenIsCaptured: true
        ))
        #expect(forceOff.shouldEngage == false)
        #expect(forceOff.isManual)

        let forceOn = EngagementEngine.decide(EngagementInputs(
            mode: .auto,
            manualOverride: ManualOverride(kind: .forceOn, firingWhenCreated: [])
        ))
        #expect(forceOn.shouldEngage)
    }

    /// Without expiry, one press of ⌥⌘S during a call would silently disarm Mica for
    /// every future call and the user would never be told.
    @Test("A force-off override expires once its trigger clears")
    func forceOffExpiresWithItsTrigger() {
        let override = ManualOverride(kind: .forceOff, firingWhenCreated: [.screenCapture])

        #expect(EngagementEngine.overrideHasExpired(override, firing: [.screenCapture]) == false)
        #expect(EngagementEngine.overrideHasExpired(override, firing: []))
        // A different trigger starting is not the one it was reacting to.
        #expect(EngagementEngine.overrideHasExpired(override, firing: [.schedule]))
    }

    @Test("A force-on override does not expire on its own")
    func forceOnPersists() {
        let override = ManualOverride(kind: .forceOn, firingWhenCreated: [])
        #expect(EngagementEngine.overrideHasExpired(override, firing: []) == false)
    }

    @Test("Screen capture outranks other triggers in the explanation")
    func capturePrioritisedInReason() {
        let decision = EngagementEngine.decide(EngagementInputs(
            mode: .auto,
            screenIsCaptured: true,
            displayIsMirroredOrExtended: true,
            scheduleIsActive: true,
            toggles: TriggerToggles(displayChange: true, schedule: true)
        ))
        #expect(decision.reason == .screenCaptured)
    }
}

@Suite("Schedule windows")
struct ScheduleWindowTests {

    @Test("A normal daytime window")
    func daytimeWindow() {
        let window = ScheduleWindow(startMinutes: 9 * 60, endMinutes: 17 * 60)
        #expect(window.contains(minutes: 12 * 60))
        #expect(window.contains(minutes: 9 * 60))
        #expect(window.contains(minutes: 8 * 60) == false)
        // The end is exclusive, so a 09:00–17:00 window is over at 17:00.
        #expect(window.contains(minutes: 17 * 60) == false)
    }

    /// The case a naive `start...end` range check gets silently wrong.
    @Test("A window that crosses midnight")
    func overnightWindow() {
        let window = ScheduleWindow(startMinutes: 22 * 60, endMinutes: 6 * 60)
        #expect(window.contains(minutes: 23 * 60))
        #expect(window.contains(minutes: 2 * 60))
        #expect(window.contains(minutes: 12 * 60) == false)
        #expect(window.contains(minutes: 6 * 60) == false)
    }

    @Test("A zero-length window is never active")
    func emptyWindow() {
        let window = ScheduleWindow(startMinutes: 9 * 60, endMinutes: 9 * 60)
        #expect(window.contains(minutes: 9 * 60) == false)
    }
}
