import AppKit

/// Detects a second display being attached or the screen being mirrored.
///
/// Entirely public API, unlike capture detection.
public final class DisplayMonitor {

    public private(set) var isMirroredOrExtended = false

    private let onChange: (Bool) -> Void
    private var observer: (any NSObjectProtocol)?
    private var pending: DispatchWorkItem?

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        refresh()
    }

    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        pending?.cancel()
        pending = nil
    }

    /// One plug or unplug fires this notification several times, and again on wake.
    private func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func refresh() {
        let screens = NSScreen.screens
        let mirrored = screens.contains { screen in
            guard let id = screen.displayID else { return false }
            return CGDisplayIsInMirrorSet(id) != 0
        }
        let value = screens.count > 1 || mirrored

        guard value != isMirroredOrExtended else { return }
        isMirroredOrExtended = value
        Log.monitors.notice("display topology: \(value ? "mirrored or extended" : "single", privacy: .public)")
        onChange(value)
    }
}
