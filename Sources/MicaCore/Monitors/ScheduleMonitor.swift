import Foundation

/// A daily time window, stored as minutes past midnight.
public nonisolated struct ScheduleWindow: Equatable, Sendable {
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    /// Whether `minutes` past midnight falls inside the window.
    ///
    /// A window whose end is before its start wraps around midnight (22:00 → 06:00),
    /// which is the case a naive `start...end` range check gets silently wrong.
    public func contains(minutes: Int) -> Bool {
        guard startMinutes != endMinutes else { return false }
        if startMinutes < endMinutes {
            return minutes >= startMinutes && minutes < endMinutes
        }
        return minutes >= startMinutes || minutes < endMinutes
    }

    public static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

public final class ScheduleMonitor {

    public private(set) var isActive = false

    public var window: ScheduleWindow? {
        didSet {
            guard window != oldValue else { return }
            refresh()
        }
    }

    private let onChange: (Bool) -> Void
    private var timer: Timer?

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        // Checking once a minute is plenty for a minute-resolution window, and is far
        // more robust across sleep and clock changes than scheduling a one-shot timer
        // for the next boundary — a Mac asleep at the boundary would simply miss it.
        let timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        timer.tolerance = 5
        self.timer = timer
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        let active = window?.contains(minutes: ScheduleWindow.minutes(from: Date())) ?? false
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }
}
