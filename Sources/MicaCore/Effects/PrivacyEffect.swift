import Foundation

/// Per-feature settings an effect needs in order to decide what to do.
public nonisolated struct EffectOptions: Equatable, Sendable {
    public var hideWindowsScope: HideWindowsScope
    /// The apps chosen for the two list-based scopes. Ignored by the others.
    public var selectedWindowApps: Set<String>

    public init(
        hideWindowsScope: HideWindowsScope = .all,
        selectedWindowApps: Set<String> = []
    ) {
        self.hideWindowsScope = hideWindowsScope
        self.selectedWindowApps = selectedWindowApps
    }
}

public nonisolated enum EffectError: Error, CustomStringConvertible {
    case unavailable(Feature, reason: String)
    case failed(Feature, reason: String)

    public var description: String {
        switch self {
        case .unavailable(let feature, let reason): "\(feature.displayName) is unavailable: \(reason)"
        case .failed(let feature, let reason): "\(feature.displayName) failed: \(reason)"
        }
    }
}

/// A `PriorState` for effects that have no system state to restore because their side
/// effects are windows and status items owned by this process — they cease to exist the
/// moment Mica does.
public nonisolated struct NoPriorState: Codable, Equatable, Sendable {
    public init() {}
}

/// The type-erased face of an effect, so the coordinator can hold all six in one
/// collection while each keeps a strongly-typed prior state. Erasure happens at the JSON
/// boundary, which is where the state has to end up anyway for crash recovery.
public protocol AnyPrivacyEffect: AnyObject {
    var feature: Feature { get }

    /// Non-nil when the effect cannot run — a missing symbol, or setup the user hasn't
    /// done yet. The coordinator skips these and the popover explains why.
    var unavailableReason: String? { get }

    func captureEncodedPriorState(options: EffectOptions) throws -> Data
    func apply(desired: Bool, encodedPrior: Data?, options: EffectOptions) async throws
    func emergencyRestore(encodedPrior: Data)
}

extension AnyPrivacyEffect {
    public var isAvailable: Bool { unavailableReason == nil }
}

public protocol PrivacyEffect: AnyPrivacyEffect {
    associatedtype PriorState: Codable & Equatable & Sendable

    /// Reads the system state this effect is about to change. Must not mutate anything,
    /// and must be fast and synchronous — it runs inside the blocking pre-mutation
    /// snapshot write, which is what makes crash recovery trustworthy.
    func capturePriorState(options: EffectOptions) throws -> PriorState

    /// Drives the system to an absolute target.
    ///
    /// - `desired == true`: engage. `prior` is guaranteed non-nil.
    /// - `desired == false`: restore exactly `prior`. A nil `prior` means do nothing.
    ///
    /// Contract, and the reason this takes a target rather than being a `toggle()`:
    /// implementations **must** read live system state first and return early if already
    /// there. That makes repeated and interleaved calls converge instead of stranding
    /// the user — mashing the hotkey can't leave the Dock hidden with nothing tracking it.
    /// Implementations must never capture prior state here, and must never treat
    /// `desired` as durable truth; a newer call may already be queued behind this one.
    func apply(desired: Bool, prior: PriorState?, options: EffectOptions) async throws

    /// Best-effort synchronous undo for `SIGTERM`, termination, and power-off.
    /// There may be well under a second before the process is killed, so this must not
    /// be async, spawn processes, or wait on anything.
    func emergencyRestore(prior: PriorState)
}

extension PrivacyEffect {
    public func captureEncodedPriorState(options: EffectOptions) throws -> Data {
        try JSONEncoder().encode(capturePriorState(options: options))
    }

    public func apply(desired: Bool, encodedPrior: Data?, options: EffectOptions) async throws {
        let prior = try encodedPrior.map { try JSONDecoder().decode(PriorState.self, from: $0) }
        try await apply(desired: desired, prior: prior, options: options)
    }

    public func emergencyRestore(encodedPrior: Data) {
        guard let prior = try? JSONDecoder().decode(PriorState.self, from: encodedPrior) else { return }
        emergencyRestore(prior: prior)
    }
}
