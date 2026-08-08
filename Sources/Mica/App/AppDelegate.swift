import AppKit
import MicaCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.start()
    }

    /// Handles `mica://settings`, and `mica://windows` and friends for a specific tab.
    ///
    /// Menu-bar-only apps are awkward to drive from scripts or aliases, and this also
    /// gives the settings window a route that doesn't depend on the popover working.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "mica" {
            let host = url.host() ?? ""
            environment.settingsWindow.show(tab: SettingsTab(rawValue: host))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.coordinator.emergencyRestoreAll()
    }
}
