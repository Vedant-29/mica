import Foundation

/// The state of the system before Mica changed anything.
///
/// Written to disk *before* the first mutation of every engage sequence. Its presence on
/// disk is the marker that Mica believes it has changed something; if the process dies
/// while engaged, the next launch finds it and puts everything back. Without this a crash
/// leaves the Dock hidden, Do Not Disturb on and applications invisible, with nothing to
/// explain why or any obvious way to undo it.
public nonisolated struct SessionSnapshot: Codable, Equatable, Sendable {

    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var createdAt: Date
    public var processIdentifier: Int32
    /// Distinguishes a crash from a reboot — see `CrashRecovery`.
    public var bootSessionUUID: String?
    public var appVersion: String?
    /// Encoded per-effect prior state, keyed by `Feature.rawValue`.
    public var effects: [String: Data]

    public init(
        schemaVersion: Int = SessionSnapshot.currentSchemaVersion,
        createdAt: Date = Date(),
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        bootSessionUUID: String? = BootSession.current,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        effects: [String: Data]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.processIdentifier = processIdentifier
        self.bootSessionUUID = bootSessionUUID
        self.appVersion = appVersion
        self.effects = effects
    }
}
