import Foundation

/// The two Shortcuts Mica runs to turn Do Not Disturb on and off, found by name.
///
/// Mica does not generate these. Turning Focus on requires the Shortcuts "Set Focus"
/// action, and that action only behaves correctly when it is created in the Shortcuts app
/// itself — a programmatically-generated copy imports in a broken "Off" state on macOS 26
/// (the action's on/off parameter isn't something a third party can set reliably, and the
/// created shortcut can't be read back to check). Creating it by hand takes seconds
/// because "Set Focus" already defaults to "Do Not Disturb On until Turned Off", so Mica
/// guides that instead and simply looks the shortcuts up by name.
public nonisolated enum ShortcutInstaller {

    public static let onName = "Mica Do Not Disturb On"
    public static let offName = "Mica Do Not Disturb Off"

    /// The UUIDs of the two shortcuts, if the user has created them.
    public static func findInstalled() -> (on: String?, off: String?) {
        let all = ShortcutsRunner.list()
        return (
            all.first { $0.name == onName }?.uuid,
            all.first { $0.name == offName }?.uuid
        )
    }
}
