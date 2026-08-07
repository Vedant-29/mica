import Foundation

/// Catches `SIGTERM` and `SIGINT` so Mica can put the system back before it dies.
///
/// `launchd` sends `SIGTERM` at logout, and `AppKit`'s termination notification does not
/// fire for it. Without this, logging out while engaged would leave the Dock hidden and
/// Do Not Disturb on until the crash-recovery path ran at next login.
///
/// `SIGKILL` is deliberately not handled — it can't be. That is exactly the case the
/// on-disk session snapshot exists to cover.
public final class SignalTrap {

    private var sources: [any DispatchSourceSignal] = []

    public init() {}

    public func install(handler: @escaping @MainActor () -> Void) {
        for signalNumber in [SIGTERM, SIGINT] {
            // The default disposition kills the process outright, before a dispatch
            // source ever gets a chance to run. Ignoring it hands delivery to the source.
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    handler()
                    exit(0)
                }
            }
            source.resume()
            sources.append(source)
        }
    }
}
