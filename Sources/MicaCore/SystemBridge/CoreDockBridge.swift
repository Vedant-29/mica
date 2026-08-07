import Foundation

/// Reads and writes the Dock's auto-hide setting.
///
/// These are private symbols, but they are the *only* prompt-free route. The public
/// alternative, `NSApplication.presentationOptions`, is documented to apply only while
/// your app is the active one — useless for a menu bar utility that is never active.
/// Driving `System Events` over AppleScript works but costs an Automation permission
/// prompt, which is precisely what this app exists to avoid.
///
/// Resolved with `dlsym` rather than `@_silgen_name` deliberately: if Apple ever drops
/// these symbols, `@_silgen_name` turns that into a dyld failure at launch — the whole
/// app dies because one feature went away. This degrades to "Hide Dock is unavailable".
///
/// Despite the name, these do not live in `CoreDock.framework`, which no longer exists
/// on macOS 26. They are exported from `HIServices`, a sub-framework of the public
/// `ApplicationServices`, which AppKit already links — so there is nothing to `dlopen`.
public enum CoreDockBridge {

    private typealias GetAutoHideEnabled = @convention(c) () -> DarwinBoolean
    private typealias SetAutoHideEnabled = @convention(c) (DarwinBoolean) -> Void

    /// `RTLD_DEFAULT` — search every image already loaded into the process.
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static let hiServicesPath =
        "/System/Library/Frameworks/ApplicationServices.framework/Versions/A"
        + "/Frameworks/HIServices.framework/Versions/A/HIServices"

    /// Loaded lazily, and only if the symbols aren't already reachable.
    ///
    /// `RTLD_DEFAULT` only searches images the process has *already* loaded, so it finds
    /// these purely as a side effect of AppKit pulling in ApplicationServices. That held
    /// in a scratch program right up until one didn't import AppKit, at which point the
    /// lookup silently returned nil. Relying on another framework's transitive load order
    /// is not a guarantee, so fall back to loading the owning framework directly.
    private static let hiServicesHandle: UnsafeMutableRawPointer? = dlopen(hiServicesPath, RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        if let pointer = dlsym(rtldDefault, name) {
            return unsafeBitCast(pointer, to: type)
        }
        if let handle = hiServicesHandle, let pointer = dlsym(handle, name) {
            return unsafeBitCast(pointer, to: type)
        }
        return nil
    }

    private static let getter = symbol("CoreDockGetAutoHideEnabled", as: GetAutoHideEnabled.self)
    private static let setter = symbol("CoreDockSetAutoHideEnabled", as: SetAutoHideEnabled.self)

    public static var isAvailable: Bool { getter != nil && setter != nil }

    /// Whether the Dock currently auto-hides, or `nil` if the symbol is gone.
    public static func autoHideEnabled() -> Bool? {
        getter?().boolValue
    }

    /// Applies the setting. The Dock observes this immediately and writes it through to
    /// its own preferences, so there is nothing to synchronize and no `killall Dock`.
    @discardableResult
    public static func setAutoHideEnabled(_ enabled: Bool) -> Bool {
        guard let setter else { return false }
        setter(DarwinBoolean(enabled))
        return true
    }
}
