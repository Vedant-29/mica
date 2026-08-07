import Foundation

/// Smooths a boolean signal with independent rising and falling delays.
///
/// The asymmetry is the whole point. Engaging is never delayed — any latency there is a
/// privacy leak, and a screen share that starts before the desktop is hidden defeats the
/// app. Releasing *is* delayed, because capture signals flap hard during teardown and a
/// 50 ms hide/show cycle across six effects looks broken and leaves state half-applied.
public final class EdgeDebouncer {

    public private(set) var value: Bool

    private let risingDelay: TimeInterval
    private let fallingDelay: TimeInterval
    private let onChange: (Bool) -> Void
    private var pending: DispatchWorkItem?

    public init(
        initial: Bool = false,
        risingDelay: TimeInterval = 0,
        fallingDelay: TimeInterval,
        onChange: @escaping (Bool) -> Void
    ) {
        self.value = initial
        self.risingDelay = risingDelay
        self.fallingDelay = fallingDelay
        self.onChange = onChange
    }

    /// - Parameter immediate: skips the delay entirely. Used for direct user input,
    ///   which should never be made to wait.
    public func set(_ newValue: Bool, immediate: Bool = false) {
        // A pending change to the opposite value is now stale either way.
        pending?.cancel()
        pending = nil

        guard newValue != value else { return }

        let delay = immediate ? 0 : (newValue ? risingDelay : fallingDelay)
        guard delay > 0 else {
            value = newValue
            onChange(newValue)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.value != newValue else { return }
                self.value = newValue
                self.pending = nil
                self.onChange(newValue)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Drops any pending transition without applying it.
    public func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
