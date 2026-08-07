import Foundation
import Observation

/// Drives the six effects toward a single target state.
///
/// Reconciliation always drives *every* effect to its absolute target rather than
/// computing a delta. That's what makes the whole thing convergent: a reconcile that gets
/// superseded halfway through can bail out safely, because the newer one re-applies
/// everything from scratch. Combined with each effect's read-then-compare early return,
/// the system reaches the right state from any intermediate mess.
@Observable
public final class PrivacyCoordinator {

    public private(set) var isEngaged = false

    /// Per-feature failures, surfaced in the popover rather than swallowed. One effect
    /// failing must never stop the others — partial privacy beats none.
    public private(set) var errors: [Feature: String] = [:]

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored public let effects: [Feature: any AnyPrivacyEffect]

    /// Encoded prior state for every effect currently applied. The keys are the source of
    /// truth for "what has Mica changed", and drive both restore and the snapshot file.
    @ObservationIgnored private var active: [Feature: Data] = [:]

    @ObservationIgnored private var target = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var chain: Task<Void, Never>?

    public init(
        preferences: Preferences,
        effects: [Feature: any AnyPrivacyEffect],
        store: SnapshotStore = .shared
    ) {
        self.preferences = preferences
        self.effects = effects
        self.store = store
    }

    // MARK: - Intent

    public func setEngaged(_ engaged: Bool) {
        guard engaged != target else { return }
        target = engaged
        isEngaged = engaged
        scheduleReconcile()
    }

    /// Called when the set of enabled features changes, so toggling one mid-session
    /// engages or releases just that effect.
    public func enabledFeaturesDidChange() {
        scheduleReconcile()
    }

    private func scheduleReconcile() {
        generation += 1
        let generation = generation
        let previous = chain
        // Serialised behind the previous run so two effects never race on the same
        // system setting; the generation check lets a superseded run exit early.
        chain = Task { [weak self] in
            await previous?.value
            await self?.reconcile(generation: generation)
        }
    }

    // MARK: - Reconciliation

    private func reconcile(generation: Int) async {
        let options = EffectOptions(hideWindowsScope: preferences.hideWindowsScope)

        let wanted: Set<Feature> = target
            ? Set(Feature.allCases.filter { preferences.isEnabled($0) && effects[$0]?.isAvailable == true })
            : []

        let toEngage = Feature.engageOrder.filter { wanted.contains($0) && active[$0] == nil }
        let toRelease = Feature.disengageOrder.filter { !wanted.contains($0) && active[$0] != nil }

        // Capture every prior state first, then flush it to disk, and only then mutate.
        // Any other order leaves a window where the system is changed but nothing on disk
        // says how to change it back.
        var captured: [Feature: Data] = [:]
        for feature in toEngage {
            guard let effect = effects[feature] else { continue }
            do {
                captured[feature] = try effect.captureEncodedPriorState(options: options)
                errors[feature] = nil
            } catch {
                errors[feature] = String(describing: error)
                Log.coordinator.error("capture failed for \(feature.rawValue, privacy: .public): \(error, privacy: .public)")
            }
        }
        if !captured.isEmpty {
            active.merge(captured) { _, new in new }
            persistSnapshot()
        }

        for feature in toEngage {
            guard generation == self.generation else { return }
            guard let effect = effects[feature], let prior = active[feature] else { continue }
            await run(feature) { try await effect.apply(desired: true, encodedPrior: prior, options: options) }
        }

        for feature in toRelease {
            guard generation == self.generation else { return }
            guard let effect = effects[feature] else { continue }
            let prior = active[feature]
            await run(feature) { try await effect.apply(desired: false, encodedPrior: prior, options: options) }
            active[feature] = nil
        }

        if active.isEmpty {
            store.delete()
        } else if !toRelease.isEmpty {
            persistSnapshot()
        }
    }

    private func run(_ feature: Feature, _ body: () async throws -> Void) async {
        do {
            try await body()
            errors[feature] = nil
        } catch {
            errors[feature] = String(describing: error)
            Log.coordinator.error("\(feature.rawValue, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    private func persistSnapshot() {
        // Only effects whose changes outlive the process are worth recording; the
        // wallpaper cover and menu bar spacer vanish with Mica on their own.
        let persistent = active.filter { $0.key.mutatesPersistentSystemState }
        guard !persistent.isEmpty else {
            store.delete()
            return
        }
        let payload = Dictionary(uniqueKeysWithValues: persistent.map { ($0.key.rawValue, $0.value) })
        store.writeBlocking(SessionSnapshot(effects: payload))
    }

    // MARK: - Teardown

    /// Synchronous best-effort restore for termination, `SIGTERM` and power-off.
    /// There may be well under a second here, so nothing async and nothing that waits.
    public func emergencyRestoreAll() {
        for feature in Feature.disengageOrder {
            guard let payload = active[feature], let effect = effects[feature] else { continue }
            effect.emergencyRestore(encodedPrior: payload)
        }
        active.removeAll()
        store.delete()
    }
}
