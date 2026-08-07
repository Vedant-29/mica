import AppKit

/// The C callback the window server invokes. It cannot capture context, so it hops to
/// the main actor and re-reads the flag rather than trying to interpret the payload —
/// the notification is only ever used as a hint that *something* changed.
private nonisolated func screenWatcherNotifyProc(
    _ type: Int32,
    _ data: UnsafeMutableRawPointer?,
    _ dataLength: Int32,
    _ context: UnsafeMutableRawPointer?
) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated { ScreenCaptureMonitor.shared?.refresh() }
    }
}

/// Detects when anything is capturing the screen.
///
/// `CGSIsScreenWatcherPresent` reads the window server's own capture-stream count — the
/// same counter behind Apple's purple recording indicator — so one boolean covers Zoom,
/// Meet, Teams, QuickTime, ⌘⇧5, OBS and macOS Screen Sharing alike. It is private, and
/// there is genuinely no public equivalent: `ScreenCaptureKit` tells you what is
/// *shareable*, never what is being shared, and `CGDisplayIsCaptured` only fires for
/// exclusive full-display capture, which none of the above use.
///
/// Some Apple-internal streams can mark themselves exempt from that count, so a small
/// class of captures is invisible here. The design bias is therefore toward false
/// positives: engaging unnecessarily costs the user nothing, missing a share costs them
/// the thing this app exists to prevent.
public final class ScreenCaptureMonitor {

    /// The C callback has no context pointer of its own, so it needs somewhere to look.
    fileprivate static var shared: ScreenCaptureMonitor?

    private typealias IsScreenWatcherPresent = @convention(c) () -> DarwinBoolean
    private typealias NotifyProc = @convention(c) (
        Int32, UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?
    ) -> Void
    private typealias RegisterNotifyProc = @convention(c) (
        NotifyProc?, Int32, UnsafeMutableRawPointer?
    ) -> Int32

    /// Window server events for a capture client attaching and detaching.
    private static let remoteConnectEvent: Int32 = 1502
    private static let remoteDisconnectEvent: Int32 = 1503

    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static func symbol<T>(_ names: [String], as type: T.Type) -> T? {
        for name in names {
            if let pointer = dlsym(rtldDefault, name) {
                return unsafeBitCast(pointer, to: type)
            }
        }
        return nil
    }

    /// CoreGraphics re-exports the SkyLight symbol, so either name may resolve.
    private static let probe = symbol(
        ["CGSIsScreenWatcherPresent", "SLSIsScreenWatcherPresent"],
        as: IsScreenWatcherPresent.self
    )
    private static let register = symbol(
        ["CGSRegisterNotifyProc", "SLSRegisterNotifyProc"],
        as: RegisterNotifyProc.self
    )

    public static var isSupported: Bool { probe != nil }

    public private(set) var isCaptured = false
    /// Best-effort name of whatever is capturing, for display only. Never gates anything.
    public private(set) var capturerName: String?

    private let onChange: (Bool) -> Void
    private var pollTimer: Timer?

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        guard Self.probe != nil else {
            Log.monitors.notice("screen capture detection unavailable: symbol not found")
            return
        }
        Self.shared = self

        // Notifications make it instant; the poll makes it correct. There is no way to
        // unregister a notify proc, and events can be missed, so the timer is the
        // backstop rather than the primary signal.
        if let register = Self.register {
            _ = register(screenWatcherNotifyProc, Self.remoteConnectEvent, nil)
            _ = register(screenWatcherNotifyProc, Self.remoteDisconnectEvent, nil)
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            MainActor.assumeIsolated { Self.shared?.refresh() }
        }
        timer.tolerance = 0.5
        pollTimer = timer

        refresh()
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if Self.shared === self { Self.shared = nil }
    }

    fileprivate func refresh() {
        guard let probe = Self.probe else { return }
        let captured = probe().boolValue
        guard captured != isCaptured else { return }

        isCaptured = captured
        capturerName = captured ? CaptureAttribution.likelyCapturer() : nil
        Log.monitors.notice("screen capture \(captured ? "started" : "stopped", privacy: .public)")
        onChange(captured)
    }
}
