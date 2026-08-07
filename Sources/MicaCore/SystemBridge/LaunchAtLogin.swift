import Foundation
import ServiceManagement

/// Registers Mica as a login item.
public nonisolated enum LaunchAtLogin {

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `SMAppService` validates the code signature and records the app's identity, so it
    /// wants a stably-signed bundle at a fixed path. A build running out of a temporary
    /// directory will usually be refused.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Result<Void, any Error> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            Log.coordinator.error("launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error, privacy: .public)")
            return .failure(error)
        }
    }
}
