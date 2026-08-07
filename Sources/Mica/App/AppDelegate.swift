import AppKit
import MicaCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.coordinator.emergencyRestoreAll()
    }
}
