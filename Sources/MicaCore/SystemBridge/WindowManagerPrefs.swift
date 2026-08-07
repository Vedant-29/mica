import Foundation

/// Reads and writes the `com.apple.WindowManager` settings behind System Settings →
/// Desktop & Dock → "Show Items on Desktop".
///
/// Using the real settings rather than covering the desktop with an opaque overlay means
/// the live wallpaper keeps showing (and animating) underneath, so "hide icons" and
/// "hide wallpaper" stay genuinely independent features.
public enum WindowManagerPrefs {

    public static let domain = "com.apple.WindowManager"

    public enum Key: String {
        case hideDesktopIcons = "StandardHideDesktopIcons"
        case hideWidgets = "StandardHideWidgets"
    }

    /// Reads a key, preserving the difference between absent and present-but-false.
    ///
    /// That difference is not pedantry: on this machine `StandardHideDesktopIcons` is
    /// absent while `StandardHideWidgets` is present and `0`. Restoring both by writing
    /// `false` would silently add a setting the user never chose.
    public static func read(_ key: Key) -> PrefValue<Bool> {
        let value = CFPreferencesCopyValue(
            key.rawValue as CFString,
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        guard let number = value as? NSNumber else { return .absent }
        return .present(number.boolValue)
    }

    /// Writes a key, or deletes it when restoring a value that was previously absent.
    public static func write(_ value: PrefValue<Bool>, to key: Key) {
        let stored: CFPropertyList? = switch value {
        case .absent: nil                          // passing nil is what performs the delete
        case .present(let flag): flag as CFBoolean
        }
        CFPreferencesSetValue(
            key.rawValue as CFString,
            stored,
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    public static func synchronize() {
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Nudges WindowManager into re-reading its preferences.
    ///
    /// Whether it picks the change up on its own is inconsistent in the field, and there
    /// is no notification to observe, so this is the reliable path. It is far gentler
    /// than the alternatives: WindowManager is `KeepAlive`, respawns in well under a
    /// second, and owns no windows — unlike `killall Finder`, which closes every open
    /// Finder window, or `killall Dock`, which also takes out Mission Control and the
    /// wallpaper. Only called when a value actually changed, so an idempotent re-apply
    /// costs nothing.
    public static func restartWindowManager() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WindowManager"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.effects.error("could not restart WindowManager: \(error, privacy: .public)")
        }
    }
}
