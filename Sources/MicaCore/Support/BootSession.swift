import Foundation

/// The kernel's identifier for the current boot.
///
/// Used to tell a crash apart from a reboot when a stale session snapshot is found.
/// The distinction matters: hidden-application state does not survive a restart, so
/// replaying a window-hiding snapshot across a reboot could only ever *wrongly* unhide
/// something the user hid themselves.
public nonisolated enum BootSession {

    public static let current: String? = read()

    private static func read() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}
